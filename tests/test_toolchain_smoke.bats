#!/usr/bin/env bats
# test_toolchain_smoke.bats — Group 5: Profile-Specific Toolchain Smoke Tests
# (SDD §4.5). Slow tier — full toolchain compilation. Runs against the real
# production image tags, read-only (SDD §5); fixture sources are bind-mounted
# readonly, builds happen in a separate writable scratch directory.

# T-2 (systems) and T-3 (research) were retired with their profiles in
# #189; their IDs are not reused. T-3 carried this file's only recorded
# negative control (#101 step 7), so T-1 has not been seen failing on a
# runner.
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
        sh -c "$(profile_smoke_command crypto)"
    [ "$status" -eq 0 ]
}

# bats test_tags=slow
@test "T-4: every committed combination passes each member's smoke test" {
    # A later member can break an earlier one: its files and ENV values win
    # (docs/designs/0194-profile-composition.md, Consequences). B-5 shows the
    # mechanism on fixtures; this runs the real members in the real images.
    local combos
    combos="$(declared_combos)"
    if [ -z "$combos" ]; then
        skip "no combination is committed in config/config.sh"
    fi

    local name members member cmd n=0
    while read -r name members; do
        if ! engine_inspect "claude-${name}" > /dev/null 2>&1; then
            echo "claude-${name} image not found — build it first with: ./build.sh ${name}" >&2
            return 1
        fi
        for member in $members; do
            cmd="$(profile_smoke_command "$member")" \
                || { echo "no smoke command for member '${member}' in tests/lib/profiles.bash" >&2; return 1; }
            n=$(( n + 1 ))
            register_container "${CONTAINER_NAME}-${n}"
            run engine_run --rm --name "${CONTAINER_NAME}-${n}" "claude-${name}" sh -c "$cmd"
            [ "$status" -eq 0 ] || { echo "${name}: ${member}'s smoke test failed: $output" >&2; return 1; }
        done
    done <<< "$combos"
}
