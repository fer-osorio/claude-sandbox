#!/usr/bin/env bats
# test_build.bats — Group 1: Build Hierarchy (SDD §4.1)
#
# B-1 invokes ./build.sh directly because it validates build.sh's own
# dependency-ordering behavior; build.sh has no custom-tag option, so this
# one test necessarily builds the real "claude-base"/"claude-crypto" tags,
# same as a developer running it normally would. B-2/B-3/B-4 build directly
# against the Dockerfiles with isolated ":test" tags (SDD §5) since they
# validate the Dockerfiles themselves, not build.sh's orchestration.

# Negative-controlled on a hosted runner on 2026-10-20 (#101 step 7), in
# runs 39501749415 and 39503913002, dispatched on throwaway probe branches.
# Each probe was one commit and none was merged:
#   - build_with_deps with its base build removed -> B-1 reported that
#     "Building claude-base" was absent from ./build.sh crypto's output.
#     Observed in both runs.
# B-2 and B-3 have not been seen failing on a runner.
#
# Every assertion in this file needs a container engine, a built image,
# or both, which is what the tag selects on — not speed. See #101 and
# docs/designs/0101-container-test-tier-in-ci.md.
# bats file_tags=container

load 'lib/engine'
load 'lib/teardown'
load 'lib/profiles'

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
    engine_build --build-arg HOST_UID=1234 -t claude-base:test "${SANDBOX_DIR}/profiles/base/"
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
    engine_build --no-cache -t claude-base:test "${SANDBOX_DIR}/profiles/base/"
    register_image "claude-base:test"

    # Children are built on the claude-base:test just built, through the
    # PARENT_IMAGE argument every child takes (C-41,
    # docs/designs/0194-profile-composition.md). Before #194 they named
    # claude-base literally, so this test needed a production base from an
    # earlier build and was not isolated from it.
    local component
    for component in $(declared_child_profiles); do
        engine_build --no-cache --build-arg PARENT_IMAGE=claude-base:test \
            -t "claude-${component}:test" "${SANDBOX_DIR}/profiles/${component}/"
        register_image "claude-${component}:test"
    done
}

# bats test_tags=slow
@test "B-5: two contract-following profiles compose into one working image" {
    # The image-level half of composition: a member built on another
    # member keeps both members' files and PATH entries, still runs as
    # claude-agent, and still starts through the base entrypoint. Built
    # directly with ":test" tags, as B-2 and B-3 are, so teardown can remove
    # them (SDD §5); build.sh's chaining of the same arguments is C-46.
    local fx="${SANDBOX_DIR}/tests/fixtures/profiles"
    engine_build -t claude-base:test "${SANDBOX_DIR}/profiles/base/"
    register_image "claude-base:test"
    engine_build --build-arg PARENT_IMAGE=claude-base:test \
        -t claude-fixture-a:test "${fx}/fixture-a/"
    register_image "claude-fixture-a:test"
    engine_build --build-arg PARENT_IMAGE=claude-fixture-a:test \
        -t claude-fixture-ab:test "${fx}/fixture-b/"
    register_image "claude-fixture-ab:test"

    run engine_run --rm claude-fixture-ab:test \
        sh -c 'cat /etc/fixture-a.marker /etc/fixture-b.marker; fixture-a; fixture-b; whoami'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[entrypoint] Starting global layer injection"* ]]
    [ "$(echo "$output" | grep -v '^\[entrypoint\]')" = "a
b
fixture-a
fixture-b
claude-agent" ]
}

# B-4 lives in tests/test_control_declarations.bats (Group 9). It greps two
# tracked scripts and starts no container, so it does not belong behind this
# file's engine gate — see SDD §6.2.
