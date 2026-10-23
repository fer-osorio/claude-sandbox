#!/usr/bin/env bats
# test_runtime_posture.bats — Group 2: Runtime Security Posture (SDD §4.2)
#
# Runs against the real production image tags, read-only (SDD §5) — these
# tests prove what a developer's actual session enforces, not a synthetic
# stand-in.

# Negative-controlled on a hosted runner on 2026-10-20 (#101 step 7), in
# runs 39501749415 and 39503913002, dispatched on throwaway probe branches.
# Each probe was one commit and none was merged:
#   - start.sh's unknown-image check removed -> R-4 reported start.sh's
#     "does not exist" error instead of "unknown image". Observed in both
#     runs.
#   - --cap-drop=ALL removed from start.sh's session container -> nothing
#     reported in the second run, whose failure list was complete. R-2
#     and R-3 pass their own --cap-drop and --security-opt flags to
#     engine_run, so they show the engine applies them, not that start.sh
#     does. Every start.sh call in this file exits before the run command.
# R-1, R-2, R-3 and R-5 have not been seen failing on a runner.
#
# Every assertion in this file needs a container engine, a built image,
# or both, which is what the tag selects on — not speed. See #101 and
# docs/designs/0101-container-test-tier-in-ci.md.
# bats file_tags=container

load 'lib/engine'
load 'lib/teardown'

SANDBOX_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCRATCH_FIXTURE="${BATS_TEST_DIRNAME}/fixtures/scratch-project"

setup() {
    engine_available || {
        echo "engine '${ENGINE}' is unreachable — is the daemon running?" >&2
        return 1
    }
    if ! engine_inspect claude-base > /dev/null 2>&1; then
        echo "claude-base image not found — build it first with: ./build.sh base" >&2
        return 1
    fi
    CONTAINER_NAME="test-claude-base-$$"
}

teardown() {
    teardown_registered
    # `|| true` matters: under bats' `set -e`, a failing first link in this
    # && chain (R7_TMPDIR/R8_TMPDIR unset, the case for every test but R-7/
    # R-8) would otherwise leave the chain's own nonzero status as the last
    # thing teardown() executes, which bats reports as a teardown failure
    # on every single test in this file, not just R-7/R-8.
    [ -n "${R7_TMPDIR:-}" ] && [ -d "$R7_TMPDIR" ] && rm -rf "$R7_TMPDIR" || true
    [ -n "${R8_TMPDIR:-}" ] && [ -d "$R8_TMPDIR" ] && rm -rf "$R8_TMPDIR" || true
}

# bats test_tags=fast
@test "R-1: container runs as claude-agent, never root" {
    register_container "$CONTAINER_NAME"
    run engine_run --rm --name "$CONTAINER_NAME" claude-base whoami
    [ "$status" -eq 0 ]
    # entrypoint.sh always runs first and logs "[entrypoint] ..." lines to
    # stdout before exec-ing the overridden CMD — filter those out rather
    # than asserting on the raw combined output.
    whoami_output=$(echo "$output" | grep -v '^\[entrypoint\]')
    [ "$whoami_output" = "claude-agent" ]
}

# bats test_tags=fast
@test "R-2: all capabilities are dropped on a running container" {
    #
    # Docker preserves the literal "ALL" token passed via --cap-drop in
    # .HostConfig.CapDrop, but Podman normalizes/expands it and does not
    # echo back the substring "ALL" — even though capabilities genuinely
    # are dropped at the kernel level (containers/podman#14882, #7747).
    # Assert on the real kernel state instead of engine-specific inspect
    # bookkeeping, per the same rationale as R-6.
    register_container "$CONTAINER_NAME"
    engine_run -d --rm --name "$CONTAINER_NAME" --cap-drop=ALL claude-base sleep 30

    run engine_exec "$CONTAINER_NAME" cat /proc/1/status
    [ "$status" -eq 0 ]
    cap_eff=$(echo "$output" | awk '/^CapEff:/ {print $2}')
    [ "$cap_eff" = "0000000000000000" ]
}

# bats test_tags=fast
@test "R-3: no-new-privileges security option is active" {
    register_container "$CONTAINER_NAME"
    engine_run -d --rm --name "$CONTAINER_NAME" --security-opt=no-new-privileges claude-base sleep 30

    run engine_inspect --format '{{.HostConfig.SecurityOpt}}' "$CONTAINER_NAME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no-new-privileges"* ]]
}

# bats test_tags=fast
@test "R-4: unknown image is rejected before any container starts" {
    run bash "${SANDBOX_DIR}/start.sh" "$SCRATCH_FIXTURE" nonexistent-image
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown image"* ]]

    ! engine_ps -a --filter "name=claude-scratch-project-" --format '{{.Names}}' | grep -q .
}

# bats test_tags=fast
@test "R-5: missing (unbuilt) image is rejected with build guidance, not a silent pull" {
    target=""
    for candidate in crypto systems research; do
        if ! engine_inspect "claude-${candidate}" > /dev/null 2>&1; then
            target="$candidate"
            break
        fi
    done

    if [ -z "$target" ]; then
        # A skip, not a failure (#159). Refusing to delete a production image
        # to manufacture an unbuilt tag is correct — SDD §5 makes runtime-test
        # images read-only — but a fully-built machine is the normal state
        # after ./build.sh all, so reporting red there made the suite
        # un-greenable on a correctly set up host. R-7's comment below already
        # called this "R-5's environment-conditional skip"; it now is one.
        #
        # One line rather than the five it replaces: bats puts the reason on
        # the TAP line, so a multi-line reason would corrupt the output the
        # harness reads.
        reason="all of crypto/systems/research are built; R-5 needs an"
        reason="${reason} unbuilt tag and must not delete a production image"
        reason="${reason} (SDD §5) — '${ENGINE} rmi claude-crypto' to exercise it"
        skip "$reason"
    fi

    run bash "${SANDBOX_DIR}/start.sh" "$SCRATCH_FIXTURE" "$target"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Build it first with: ./build.sh ${target}"* ]]
    ! engine_inspect "claude-${target}" > /dev/null 2>&1
}

# hostfidelity: this assertion depends on the host's cgroup layout and cannot
# be made faithfully on a hosted runner. It fails on ubuntu-latest in all three
# #101 spike runs even with "memory" present in the delegated controller set,
# so delegation is not the sufficient condition one would expect. The container
# tier excludes it by this tag and the operator verifies it instead; the
# ceiling of one in ci.yml is what stops the tag becoming an escape hatch for
# any container test that happens to be failing.
# bats test_tags=fast,hostfidelity
@test "R-6: cgroups memory limit is actually enforced, not just accepted" {
    #
    # Regression test for a real finding (0025-podman-migration.md §6.2-D,
    # claude-code-security-plan.md Change 17): under a WSL2 host without
    # cgroups v2 "memory" delegated to the user session, Podman accepted
    # --memory without error but never actually enforced it. A --memory
    # flag that's merely accepted, not enforced, is a silent
    # Denial-of-Service-relevant regression — assert on the real outcome,
    # not just that start.sh/build.sh pass the flag through.
    #
    # We only assert on exit 137 (SIGKILL), not .State.OOMKilled. Once
    # delegation is actually fixed, exit 137 + a matching "Memory cgroup
    # out of memory: Killed process" line in dmesg confirm the kernel
    # genuinely enforced the cgroup limit — but Podman's own OOM watcher
    # never emits an "oom" event or sets OOMKilled under this host's
    # nested rootless cgroup layout (.../user@<uid>.service/user.slice/
    # libpod-<id>.scope/container), so that field can't be trusted here.
    # See 0025-podman-migration.md §6.2-D follow-up.
    register_container "$CONTAINER_NAME"

    userns_args=()
    if [ "$ENGINE" = "podman" ]; then
        userns_args=(--userns=keep-id:uid=1000,gid=1000)
    fi

    run engine_run --name "$CONTAINER_NAME" --memory=100m \
        --cap-drop=ALL --security-opt=no-new-privileges \
        "${userns_args[@]}" \
        claude-base python3 -c "bytearray(500 * 1024 * 1024)"
    [ "$status" -eq 137 ]
}

# bats test_tags=fast
@test "R-7: /workspace bind mount is genuinely readable and writable under SELinux" {
    #
    # Regression test for a real finding (claude-code-security-plan.md
    # Change 19, 0025-podman-migration.md §6.2 Tampering follow-up): a bind
    # mount with correct POSIX bits (0755, owned by claude-agent) was fully
    # unreadable and unwritable from inside a Podman container on an
    # SELinux-enforcing host, because start.sh's --mount invocations never
    # relabeled the host path — a MAC-layer EACCES on top of correct Unix
    # permissions. Only meaningful on a host where SELinux is actually
    # enforcing; on a non-enforcing host this passes identically before and
    # after the fix and would report a false green, so skip instead (same
    # rationale as R-5's environment-conditional skip).
    if ! command -v getenforce > /dev/null 2>&1 || [ "$(getenforce)" != "Enforcing" ]; then
        skip "host is not SELinux-enforcing — this regression is only observable under enforcing SELinux"
    fi

    register_container "$CONTAINER_NAME"

    R7_TMPDIR="$(mktemp -d)"
    echo "known-content-$$" > "${R7_TMPDIR}/preexisting.txt"

    relabel_arg=""
    userns_args=()
    if [ "$ENGINE" = "podman" ]; then
        relabel_arg=",relabel=shared"
        userns_args=(--userns=keep-id:uid=1000,gid=1000)
    fi

    engine_run -d --rm --name "$CONTAINER_NAME" \
        --mount "type=bind,source=${R7_TMPDIR},target=/workspace${relabel_arg}" \
        --cap-drop=ALL --security-opt=no-new-privileges \
        "${userns_args[@]}" \
        claude-base sleep 30

    run engine_exec "$CONTAINER_NAME" cat /workspace/preexisting.txt
    [ "$status" -eq 0 ]
    [ "$output" = "known-content-$$" ]

    run engine_exec "$CONTAINER_NAME" sh -c 'echo written-from-container > /workspace/written.txt'
    [ "$status" -eq 0 ]

    [ -f "${R7_TMPDIR}/written.txt" ]
    [ "$(cat "${R7_TMPDIR}/written.txt")" = "written-from-container" ]
}

# bats test_tags=fast
@test "R-8: relabel=shared (not private) allows two concurrent sessions on the same host path" {
    #
    # R-7 alone doesn't validate the shared-vs-private design decision in
    # Change 19 — a relabel=private (:Z) mount would also pass a
    # single-container read/write check; it only breaks a *second*
    # concurrent container on the same host path, which is exactly the
    # GLOBAL_BASE/GLOBAL_OVERLAY scenario "shared" was chosen for. Confirms
    # the choice empirically rather than by inspection alone.
    if ! command -v getenforce > /dev/null 2>&1 || [ "$(getenforce)" != "Enforcing" ]; then
        skip "host is not SELinux-enforcing — this regression is only observable under enforcing SELinux"
    fi
    if [ "$ENGINE" != "podman" ]; then
        skip "relabel=shared is a Podman-specific --mount suboption; not applicable under ENGINE=docker"
    fi

    register_container "${CONTAINER_NAME}-a"
    register_container "${CONTAINER_NAME}-b"

    R8_TMPDIR="$(mktemp -d)"
    echo "shared-content" > "${R8_TMPDIR}/f.txt"

    engine_run -d --rm --name "${CONTAINER_NAME}-a" \
        --mount "type=bind,source=${R8_TMPDIR},target=/workspace,relabel=shared" \
        --cap-drop=ALL --security-opt=no-new-privileges \
        --userns=keep-id:uid=1000,gid=1000 \
        claude-base sleep 30

    engine_run -d --rm --name "${CONTAINER_NAME}-b" \
        --mount "type=bind,source=${R8_TMPDIR},target=/workspace,relabel=shared" \
        --cap-drop=ALL --security-opt=no-new-privileges \
        --userns=keep-id:uid=1000,gid=1000 \
        claude-base sleep 30

    run engine_exec "${CONTAINER_NAME}-a" cat /workspace/f.txt
    [ "$status" -eq 0 ]
    [ "$output" = "shared-content" ]
    run engine_exec "${CONTAINER_NAME}-b" cat /workspace/f.txt
    [ "$status" -eq 0 ]
    [ "$output" = "shared-content" ]
}
