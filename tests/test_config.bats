#!/usr/bin/env bats
# test_config.bats — Group: Layered Config (docs/designs/sandbox-config-file.md)
#
# Covers config.sh's own correctness and the four-layer precedence chain
# (hardcoded defaults < config.sh < config.local.sh < env var), not
# container runtime behavior — no engine daemon is required for any test
# in this file, so setup() does not gate on engine_available. Every test
# here therefore also carries the `hostonly` tag, which is the axis CI
# filters on — `fast` is about duration and does not imply an engine-free
# test (see BUILDING.md, "Tag axes").
#
# None of these tests touch a real config.local.sh: an operator's own
# gitignored file must never be read, written, or deleted by the test
# suite (see docs/designs/sandbox-config-file.md's discussion of why a
# .gitignore entry, not test tooling, is the boundary here). The registry
# tests below (C-7 onward) are no exception: each writes its own
# config.sh/config.local.sh pair into a throwaway REG_TMPDIR, copies the
# real start.sh alongside them, and runs that copy with ENGINE=true — a
# no-op stand-in that makes every "$ENGINE ..." check in start.sh succeed
# trivially and return immediately, with no daemon contacted and nothing
# actually started. This exercises the real @name resolution and
# config.local.sh layering code end to end, still without an engine.

SANDBOX_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

teardown() {
    # See tests/test_runtime_posture.bats for why this is a separate
    # guarded statement rather than chained with &&: the "|| true" must
    # apply to the whole chain so a test that never set REG_TMPDIR doesn't
    # fail its own teardown.
    [ -n "${REG_TMPDIR:-}" ] && [ -d "$REG_TMPDIR" ] && rm -rf "$REG_TMPDIR" || true
}

# Copies the real start.sh into a fresh REG_TMPDIR so registry tests
# exercise production code, not a re-implementation of it.
_reg_fixture_dir() {
    REG_TMPDIR="$(mktemp -d)"
    cp "${SANDBOX_DIR}/start.sh" "${REG_TMPDIR}/start.sh"
}

@test "C-1: env var overrides config.sh's value for the same variable" {
    # bats test_tags=fast, hostonly
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
    # bats test_tags=fast, hostonly
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
    # bats test_tags=fast, hostonly
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
    # bats test_tags=fast, hostonly
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
    # bats test_tags=fast, hostonly
    # No engine daemon required: dispatch to the "Unknown target" branch
    # happens before build.sh ever shells out to $ENGINE.
    run bash "${SANDBOX_DIR}/build.sh" definitely-not-a-real-profile
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown target"* ]]
}

@test "C-6: build.sh and start.sh both source config.sh, not a re-copied literal list" {
    # bats test_tags=fast, hostonly
    # Structural guard for the drift problem this design exists to fix:
    # both scripts must read PROFILES from the same sourced file rather
    # than hardcoding their own copies that could silently diverge again.
    grep -Eq 'source "\$\{?SANDBOX_DIR\}?/config\.sh"' "${SANDBOX_DIR}/build.sh"
    grep -Eq 'source "\$\{?SANDBOX_DIR\}?/config\.sh"' "${SANDBOX_DIR}/start.sh"
}

# C-7 onward: named project registry (docs/designs/named-project-registry.md)

@test "C-7: @name resolves to the registered path and its registry profile" {
    # bats test_tags=fast, hostonly
    _reg_fixture_dir
    mkdir -p "${REG_TMPDIR}/mylib"
    cat > "${REG_TMPDIR}/config.sh" <<EOF
PROJECT_PATH[mylib]="${REG_TMPDIR}/mylib"
PROJECT_PROFILE[mylib]=crypto
EOF

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash start.sh @mylib 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project:  ${REG_TMPDIR}/mylib"* ]]
    [[ "$output" == *"Image:    claude-crypto"* ]]
}

@test "C-8: an explicit second argument overrides the registry's profile" {
    # bats test_tags=fast, hostonly
    _reg_fixture_dir
    mkdir -p "${REG_TMPDIR}/mylib"
    cat > "${REG_TMPDIR}/config.sh" <<EOF
PROJECT_PATH[mylib]="${REG_TMPDIR}/mylib"
PROJECT_PROFILE[mylib]=crypto
EOF

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash start.sh @mylib systems 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Image:    claude-systems"* ]]
}

@test "C-9: an unknown @name exits non-zero and never reaches the engine" {
    # bats test_tags=fast, hostonly
    _reg_fixture_dir
    cat > "${REG_TMPDIR}/config.sh" <<EOF
PROJECT_PATH[mylib]="${REG_TMPDIR}/mylib"
PROJECT_PROFILE[mylib]=crypto
EOF

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash start.sh @doesnotexist 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error: unknown project 'doesnotexist'."* ]]
    [[ "$output" == *"mylib"* ]]                # registered-projects listing
    [[ "$output" != *"Starting Squid proxy"* ]]  # no container was started
}

@test "C-10: a name with a path but no profile is reported, not a 'set -u' crash" {
    # bats test_tags=fast, hostonly
    # Regression guard for the two-array sync problem the design doc calls
    # out: PROJECT_PATH and PROJECT_PROFILE can drift apart, and the ':-'
    # guards at the read site must turn that into the intended error
    # message rather than an unbound-variable abort under set -u.
    _reg_fixture_dir
    mkdir -p "${REG_TMPDIR}/orphan"
    cat > "${REG_TMPDIR}/config.sh" <<EOF
PROJECT_PATH[orphan]="${REG_TMPDIR}/orphan"
EOF

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash start.sh @orphan 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error: project 'orphan' has a path but no profile in config.sh."* ]]
    [[ "$output" != *"unbound variable"* ]]
    [[ "$output" != *"bad array subscript"* ]]
}

@test "C-11: a bare name matching a registry entry is still treated as a path" {
    # bats test_tags=fast, hostonly
    # The sigil boundary: from a directory containing a "mylib" subdirectory,
    # "./start.sh mylib" (no @, no second argument) must resolve as a plain
    # relative path and fall through to the base-profile default — not
    # consult the registry and pick up its crypto profile. IMAGE_TAG is the
    # observable proxy for which branch ran, since the two candidate
    # directories are identical.
    _reg_fixture_dir
    mkdir -p "${REG_TMPDIR}/mylib"
    cat > "${REG_TMPDIR}/config.sh" <<EOF
PROJECT_PATH[mylib]="${REG_TMPDIR}/mylib"
PROJECT_PROFILE[mylib]=crypto
EOF

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash start.sh mylib 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project:  ${REG_TMPDIR}/mylib"* ]]
    [[ "$output" == *"Image:    claude-base"* ]]
}

@test "C-12: a name added only in config.local.sh resolves correctly" {
    # bats test_tags=fast, hostonly
    _reg_fixture_dir
    mkdir -p "${REG_TMPDIR}/localonly"
    : > "${REG_TMPDIR}/config.sh"   # no committed entries
    cat > "${REG_TMPDIR}/config.local.sh" <<EOF
PROJECT_PATH[localonly]="${REG_TMPDIR}/localonly"
PROJECT_PROFILE[localonly]=research
EOF

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash start.sh @localonly 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project:  ${REG_TMPDIR}/localonly"* ]]
    [[ "$output" == *"Image:    claude-research"* ]]
    [[ "$output" != *"Warning:"* ]]
}

@test "C-13: config.local.sh redefining a committed name is reverted and warned, not honored" {
    # bats test_tags=fast, hostonly
    _reg_fixture_dir
    mkdir -p "${REG_TMPDIR}/committed-real" "${REG_TMPDIR}/attempted-override"
    cat > "${REG_TMPDIR}/config.sh" <<EOF
PROJECT_PATH[committed]="${REG_TMPDIR}/committed-real"
PROJECT_PROFILE[committed]=crypto
EOF
    cat > "${REG_TMPDIR}/config.local.sh" <<EOF
PROJECT_PATH[committed]="${REG_TMPDIR}/attempted-override"
PROJECT_PROFILE[committed]=research
EOF

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash start.sh @committed 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: config.local.sh redefines committed project 'committed'; ignoring the local value (config.sh wins)."* ]]
    [[ "$output" == *"Project:  ${REG_TMPDIR}/committed-real"* ]]
    [[ "$output" == *"Image:    claude-crypto"* ]]
    [[ "$output" != *"attempted-override"* ]]
}
