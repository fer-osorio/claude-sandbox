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

@test "R-2: CapDrop: [ALL] is present on a running container" {
    # bats test_tags=fast
    register_container "$CONTAINER_NAME"
    engine_run -d --rm --name "$CONTAINER_NAME" --cap-drop=ALL claude-base sleep 30

    run engine_inspect --format '{{.HostConfig.CapDrop}}' "$CONTAINER_NAME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALL"* ]]
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
