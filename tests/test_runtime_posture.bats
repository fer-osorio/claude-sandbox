#!/usr/bin/env bats
# test_runtime_posture.bats — Group 2: Runtime Security Posture (SDD §4.2)
#
# Runs against the real production image tags, read-only (SDD §5) — these
# tests prove what a developer's actual session enforces, not a synthetic
# stand-in.

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
}

@test "R-1: container runs as claude-agent, never root" {
    # bats test_tags=fast
    register_container "$CONTAINER_NAME"
    run engine_run --rm --name "$CONTAINER_NAME" claude-base whoami
    [ "$status" -eq 0 ]
    # entrypoint.sh always runs first and logs "[entrypoint] ..." lines to
    # stdout before exec-ing the overridden CMD — filter those out rather
    # than asserting on the raw combined output.
    whoami_output=$(echo "$output" | grep -v '^\[entrypoint\]')
    [ "$whoami_output" = "claude-agent" ]
}

@test "R-2: all capabilities are dropped on a running container" {
    # bats test_tags=fast
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

@test "R-3: no-new-privileges security option is active" {
    # bats test_tags=fast
    register_container "$CONTAINER_NAME"
    engine_run -d --rm --name "$CONTAINER_NAME" --security-opt=no-new-privileges claude-base sleep 30

    run engine_inspect --format '{{.HostConfig.SecurityOpt}}' "$CONTAINER_NAME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no-new-privileges"* ]]
}

@test "R-4: unknown image is rejected before any container starts" {
    # bats test_tags=fast
    run bash "${SANDBOX_DIR}/start.sh" "$SCRATCH_FIXTURE" nonexistent-image
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown image"* ]]

    ! engine_ps -a --filter "name=claude-scratch-project-" --format '{{.Names}}' | grep -q .
}

@test "R-5: missing (unbuilt) image is rejected with build guidance, not a silent pull" {
    # bats test_tags=fast
    target=""
    for candidate in crypto systems research; do
        if ! engine_inspect "claude-${candidate}" > /dev/null 2>&1; then
            target="$candidate"
            break
        fi
    done

    if [ -z "$target" ]; then
        echo "All of claude-crypto/systems/research are already built locally." >&2
        echo "R-5 needs a valid-but-unbuilt tag to exercise this path, and this" >&2
        echo "suite must never remove a real production image to manufacture one" >&2
        echo "(SDD §5 — runtime-test images are read-only, never mutated)." >&2
        echo "Remove one manually with '${ENGINE} rmi claude-<tag>' to run this test." >&2
        return 1
    fi

    run bash "${SANDBOX_DIR}/start.sh" "$SCRATCH_FIXTURE" "$target"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Build it first with: ./build.sh ${target}"* ]]
    ! engine_inspect "claude-${target}" > /dev/null 2>&1
}

@test "R-6: cgroups memory limit is actually enforced, not just accepted" {
    # bats test_tags=fast
    #
    # Regression test for a real finding (podman-migration.md §6.2-D,
    # claude_code_security_plan.md Change 17): under a WSL2 host without
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
    # See podman-migration.md §6.2-D follow-up.
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
