#!/usr/bin/env bats
# test_config.bats — Group: Layered Config (docs/designs/sandbox-config-file.md)
#
# Covers config.sh's own correctness and the four-layer precedence chain
# (hardcoded defaults < config.sh < config.local.sh < env var), not
# container runtime behavior — no engine daemon is required for any test
# in this file, so setup() does not gate on engine_available.
#
# None of these tests touch a real config.local.sh: an operator's own
# gitignored file must never be read, written, or deleted by the test
# suite (see docs/designs/sandbox-config-file.md's discussion of why a
# .gitignore entry, not test tooling, is the boundary here).

SANDBOX_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

@test "C-1: env var overrides config.sh's value for the same variable" {
    # bats test_tags=fast
    run env ENGINE=docker bash -c '
        set -euo pipefail
        cd "'"${SANDBOX_DIR}"'"
        _ENV_ENGINE="${ENGINE:-}"
        ENGINE="podman"
        source "./config.sh"
        ENGINE="${_ENV_ENGINE:-$ENGINE}"
        echo "$ENGINE"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "docker" ]
}

@test "C-2: config.sh overrides the hardcoded layer-1 default when no env var is set" {
    # bats test_tags=fast
    run bash -c '
        set -euo pipefail
        cd "'"${SANDBOX_DIR}"'"
        ENGINE="sentinel-default-value"
        source "./config.sh"
        echo "$ENGINE"
    '
    [ "$status" -eq 0 ]
    [ "$output" != "sentinel-default-value" ]
}

@test "C-3: config.sh's PROFILES matches the profile directories actually present" {
    # bats test_tags=fast
    run bash -c '
        set -euo pipefail
        cd "'"${SANDBOX_DIR}"'"
        source "./config.sh"
        printf "%s\n" "${PROFILES[@]}"
    '
    [ "$status" -eq 0 ]

    for dir in base crypto systems research; do
        [ -f "${SANDBOX_DIR}/${dir}/Dockerfile" ]
        echo "$output" | grep -qx "$dir"
    done
}

@test "C-4: config.sh's PROFILE_BASE only references profiles PROFILES actually declares" {
    # bats test_tags=fast
    # Regression guard: a typo'd or stale base-dependency entry (e.g.
    # pointing at a renamed/removed profile) would silently no-op the
    # build.sh dependency lookup rather than fail loudly.
    run bash -c '
        set -euo pipefail
        cd "'"${SANDBOX_DIR}"'"
        source "./config.sh"
        for key in "${!PROFILE_BASE[@]}"; do
            printf "%s\n" "${PROFILE_BASE[$key]}"
        done
    '
    [ "$status" -eq 0 ]

    profiles_list=$(bash -c '
        set -euo pipefail
        cd "'"${SANDBOX_DIR}"'"
        source "./config.sh"
        printf "%s\n" "${PROFILES[@]}"
    ')

    while IFS= read -r base_dep; do
        [ -z "$base_dep" ] && continue
        echo "$profiles_list" | grep -qx "$base_dep"
    done <<< "$output"
}

@test "C-5: build.sh rejects a target not present in config.sh's PROFILES, without touching an engine" {
    # bats test_tags=fast
    # No engine daemon required: dispatch to the "Unknown target" branch
    # happens before build.sh ever shells out to $ENGINE.
    run bash "${SANDBOX_DIR}/build.sh" definitely-not-a-real-profile
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown target"* ]]
}

@test "C-6: build.sh and start.sh both source config.sh, not a re-copied literal list" {
    # bats test_tags=fast
    # Structural guard for the drift problem this design exists to fix:
    # both scripts must read PROFILES from the same sourced file rather
    # than hardcoding their own copies that could silently diverge again.
    grep -Eq 'source "\$\{?SANDBOX_DIR\}?/config\.sh"' "${SANDBOX_DIR}/build.sh"
    grep -Eq 'source "\$\{?SANDBOX_DIR\}?/config\.sh"' "${SANDBOX_DIR}/start.sh"
}
