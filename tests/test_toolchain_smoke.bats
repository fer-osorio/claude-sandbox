#!/usr/bin/env bats
# test_toolchain_smoke.bats — Group 5: Profile-Specific Toolchain Smoke Tests
# (SDD §4.5). Slow tier — full toolchain compilation. Runs against the real
# production image tags, read-only (SDD §5); fixture sources are bind-mounted
# readonly, builds happen in a separate writable scratch directory.

# Negative-controlled on a hosted runner on 2026-10-20 (#101 step 7), in
# runs 39501749415 and 39503913002, dispatched on throwaway probe branches.
# Each probe was one commit and none was merged:
#   - latexmk removed from research/Dockerfile's package list -> T-3
#     reported it. Named in the second run. The first counted 13 failures
#     but named only 10, because Actions keeps 10 error annotations per
#     step.
# T-1 and T-2 have not been seen failing on a runner.
#
# Every assertion in this file needs a container engine, a built image,
# or both, which is what the tag selects on — not speed. See #101 and
# docs/designs/0101-container-test-tier-in-ci.md.
# bats file_tags=container

load 'lib/engine'
load 'lib/teardown'

SANDBOX_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
CPP_FIXTURE="${BATS_TEST_DIRNAME}/fixtures/cpp-minimal"
TEX_FIXTURE="${BATS_TEST_DIRNAME}/fixtures/research-minimal"

setup() {
    engine_available || {
        echo "engine '${ENGINE}' is unreachable — is the daemon running?" >&2
        return 1
    }
    CONTAINER_NAME="test-claude-toolchain-$$"
}

teardown() {
    teardown_registered
}

# bats test_tags=slow
@test "T-1: crypto profile — softhsm2-util and p11-kit are functional" {
    if ! engine_inspect claude-crypto > /dev/null 2>&1; then
        echo "claude-crypto image not found — build it first with: ./build.sh crypto" >&2
        return 1
    fi

    register_container "$CONTAINER_NAME"
    run engine_run --rm --name "$CONTAINER_NAME" claude-crypto \
        sh -c 'softhsm2-util --show-slots && p11-kit list-modules'
    [ "$status" -eq 0 ]
}

# bats test_tags=slow
@test "T-2: systems profile — minimal CMake project builds and links against GTest" {
    if ! engine_inspect claude-systems > /dev/null 2>&1; then
        echo "claude-systems image not found — build it first with: ./build.sh systems" >&2
        return 1
    fi

    register_container "$CONTAINER_NAME"
    run engine_run --rm --name "$CONTAINER_NAME" \
        --mount "type=bind,source=${CPP_FIXTURE},target=/workspace,readonly" \
        claude-systems \
        sh -c 'cmake -S /workspace -B /tmp/build -GNinja && cmake --build /tmp/build && /tmp/build/cpp_minimal_test'
    [ "$status" -eq 0 ]
}

# bats test_tags=slow
@test "T-3: research profile — minimal LaTeX document compiles via latexmk" {
    if ! engine_inspect claude-research > /dev/null 2>&1; then
        echo "claude-research image not found — build it first with: ./build.sh research" >&2
        return 1
    fi

    register_container "$CONTAINER_NAME"
    run engine_run --rm --name "$CONTAINER_NAME" \
        --mount "type=bind,source=${TEX_FIXTURE},target=/workspace,readonly" \
        claude-research \
        sh -c 'mkdir -p /tmp/out && latexmk -pdf -outdir=/tmp/out /workspace/main.tex && test -f /tmp/out/main.pdf'
    [ "$status" -eq 0 ]
}
