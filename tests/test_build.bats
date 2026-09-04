#!/usr/bin/env bats
# test_build.bats — Group 1: Build Hierarchy (SDD §4.1)
#
# B-1 invokes ./build.sh directly because it validates build.sh's own
# dependency-ordering behavior; build.sh has no custom-tag option, so this
# one test necessarily builds the real "claude-base"/"claude-crypto" tags,
# same as a developer running it normally would. B-2/B-3/B-4 build directly
# against the Dockerfiles with isolated ":test" tags (SDD §5) since they
# validate the Dockerfiles themselves, not build.sh's orchestration.

load 'lib/engine'
load 'lib/teardown'

SANDBOX_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
    engine_available || {
        echo "engine '${ENGINE}' is unreachable — is the daemon running?" >&2
        return 1
    }
}

teardown() {
    teardown_registered
}

# bats test_tags=fast
@test "B-1: ./build.sh crypto builds base before crypto, both present" {
    run bash "${SANDBOX_DIR}/build.sh" crypto
    [ "$status" -eq 0 ]

    base_line=$(echo "$output" | grep -n "Building claude-base" | head -1 | cut -d: -f1)
    crypto_line=$(echo "$output" | grep -n "Building claude-crypto" | head -1 | cut -d: -f1)
    [ -n "$base_line" ]
    [ -n "$crypto_line" ]
    [ "$base_line" -lt "$crypto_line" ]

    engine_inspect claude-base > /dev/null 2>&1
    engine_inspect claude-crypto > /dev/null 2>&1
}

# bats test_tags=fast
@test "B-2: HOST_UID build-arg propagates to the resulting image's user" {
    engine_build --build-arg HOST_UID=1234 -t claude-base:test "${SANDBOX_DIR}/base/"
    register_image "claude-base:test"

    run engine_run --rm claude-base:test id -u
    [ "$status" -eq 0 ]
    # entrypoint.sh always runs first and logs "[entrypoint] ..." lines to
    # stdout before exec-ing the overridden CMD — filter those out rather
    # than asserting on the raw combined output.
    id_output=$(echo "$output" | grep -v '^\[entrypoint\]')
    [ "$id_output" = "1234" ]
}

# bats test_tags=slow
@test "B-3: each Dockerfile builds cleanly standalone, without a prior full-build cache" {
    engine_build --no-cache -t claude-base:test "${SANDBOX_DIR}/base/"
    register_image "claude-base:test"

    # crypto/systems/research all hardcode "FROM claude-base" (the production
    # tag, not ":test") — that FROM clause can't be parameterized without
    # editing the Dockerfiles, which is out of scope for this suite (SDD
    # §2.3). So isolating *these* builds from a prior full build still
    # requires claude-base to already exist; fail loudly and name the fix
    # rather than silently aliasing or skipping (SDD §8).
    if ! engine_inspect claude-base > /dev/null 2>&1; then
        echo "claude-base image not found — build it first with: ./build.sh base" >&2
        return 1
    fi

    for component in crypto systems research; do
        engine_build --no-cache -t "claude-${component}:test" "${SANDBOX_DIR}/${component}/"
        register_image "claude-${component}:test"
    done
}

# B-4 lives in tests/test_control_declarations.bats (Group 9). It greps two
# tracked scripts and starts no container, so it does not belong behind this
# file's engine gate — see SDD §6.2.
