#!/usr/bin/env bats
# test_config.bats — Group: Layered Config (docs/designs/0028-sandbox-config-file.md)
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
# suite (see docs/designs/0028-sandbox-config-file.md's discussion of why a
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

# A project directory plus an empty credential store, both inside REG_TMPDIR
# so no test can reach an operator's real store at CREDENTIALS_DIR's default.
_cred_fixture() {
    mkdir -p "${REG_TMPDIR}/proj" "${REG_TMPDIR}/store"
}

# Plants a credential file under the name start.sh will look for. The hash is
# recomputed here rather than read from start.sh: if the two formulas ever
# diverge, C-16 and C-17 stop finding the file and fail, which is the signal
# wanted.
_cred_file_for() {
    printf 'ciphertext\n' \
        > "${REG_TMPDIR}/store/$(printf '%s' "$1" | sha256sum | cut -d' ' -f1).age"
    printf 'wrapped\n' > "${REG_TMPDIR}/store/identity.age"
}

# An 'age' on PATH whose body is the argument. Used to drive the decrypt
# branches without the real binary, which is a host dependency the CI runner
# does not have.
_stub_age() {
    mkdir -p "${REG_TMPDIR}/bin"
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s\n' "$1"
    } > "${REG_TMPDIR}/bin/age"
    chmod +x "${REG_TMPDIR}/bin/age"
}

# A PATH holding everything start.sh needs before its 'age' check and nothing
# named age, so the missing-binary branch stays reachable on a host that has
# age installed. Echoes the directory.
_path_without_age() {
    local tool
    mkdir -p "${REG_TMPDIR}/nobin"
    for tool in bash sh realpath sha256sum cut grep sed sort tr basename \
                dirname date mv rm cat head tail printf env; do
        if command -v "$tool" > /dev/null 2>&1; then
            ln -sf "$(command -v "$tool")" "${REG_TMPDIR}/nobin/${tool}"
        fi
    done
    printf '%s' "${REG_TMPDIR}/nobin"
}

# bats test_tags=fast, hostonly
@test "C-1: env var overrides config.sh's value for the same variable" {
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

# bats test_tags=fast, hostonly
@test "C-2: config.sh overrides the hardcoded layer-1 default when no env var is set" {
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

# bats test_tags=fast, hostonly
@test "C-3: config.sh's PROFILES matches the profile directories actually present" {
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

# bats test_tags=fast, hostonly
@test "C-4: config.sh's PROFILE_BASE only references profiles PROFILES actually declares" {
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

# bats test_tags=fast, hostonly
@test "C-5: build.sh rejects a target not present in config.sh's PROFILES, without touching an engine" {
    # No engine daemon required: dispatch to the "Unknown target" branch
    # happens before build.sh ever shells out to $ENGINE.
    run bash "${SANDBOX_DIR}/build.sh" definitely-not-a-real-profile
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown target"* ]]
}

# bats test_tags=fast, hostonly
@test "C-6: build.sh and start.sh both source config.sh, not a re-copied literal list" {
    # Structural guard for the drift problem this design exists to fix:
    # both scripts must read PROFILES from the same sourced file rather
    # than hardcoding their own copies that could silently diverge again.
    grep -Eq 'source "\$\{?SANDBOX_DIR\}?/config\.sh"' "${SANDBOX_DIR}/build.sh"
    grep -Eq 'source "\$\{?SANDBOX_DIR\}?/config\.sh"' "${SANDBOX_DIR}/start.sh"
}

# C-7 onward: named project registry (docs/designs/0030-named-project-registry.md)

# bats test_tags=fast, hostonly
@test "C-7: @name resolves to the registered path and its registry profile" {
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

# bats test_tags=fast, hostonly
@test "C-8: an explicit second argument overrides the registry's profile" {
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

# bats test_tags=fast, hostonly
@test "C-9: an unknown @name exits non-zero and never reaches the engine" {
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

# bats test_tags=fast, hostonly
@test "C-10: a name with a path but no profile is reported, not a 'set -u' crash" {
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

# bats test_tags=fast, hostonly
@test "C-11: a bare name matching a registry entry is still treated as a path" {
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

# bats test_tags=fast, hostonly
@test "C-12: a name added only in config.local.sh resolves correctly" {
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

# bats test_tags=fast, hostonly
@test "C-13: config.local.sh redefining a committed name is reverted and warned, not honored" {
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

# Credential store (docs/designs/0129-encrypted-credential-store.md). None of
# these needs the real 'age': the store is a host dependency and CI's runner
# has none, so the decrypt branches are driven through a stub on PATH.

# bats test_tags=fast, hostonly
@test "C-14: a project with no credential file starts silently, as it always has" {
    _reg_fixture_dir
    _cred_fixture

    run bash -c 'cd "'"${REG_TMPDIR}"'" && env -u GH_TOKEN ENGINE=true \
        CREDENTIALS_DIR="'"${REG_TMPDIR}"'/store" \
        bash start.sh "'"${REG_TMPDIR}"'/proj" 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project:  ${REG_TMPDIR}/proj"* ]]
    [[ "$output" != *"Creds:"* ]]
    [[ "$output" == *"Starting Squid proxy"* ]]
}

# bats test_tags=fast, hostonly
@test "C-15: the banner reports the names in ENV_ARGS, covering the ambient GH_TOKEN path" {
    _reg_fixture_dir
    _cred_fixture

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true GH_TOKEN=unused-by-this-test \
        CREDENTIALS_DIR="'"${REG_TMPDIR}"'/store" \
        bash start.sh "'"${REG_TMPDIR}"'/proj" 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Creds:    1 injected (GH_TOKEN)"* ]]
    [[ "$output" != *"unused-by-this-test"* ]]
}

# bats test_tags=fast, hostonly
@test "C-16: a credential file with no age binary aborts, distinguishably from having none" {
    _reg_fixture_dir
    _cred_fixture
    _cred_file_for "${REG_TMPDIR}/proj"
    local nobin
    nobin="$(_path_without_age)"

    run bash -c 'cd "'"${REG_TMPDIR}"'" && env -u GH_TOKEN PATH="'"${nobin}"'" ENGINE=true \
        CREDENTIALS_DIR="'"${REG_TMPDIR}"'/store" \
        bash start.sh "'"${REG_TMPDIR}"'/proj" 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"has stored credentials but 'age' is not installed"* ]]
    # The point of this guard is that the abort happens *here*, not three
    # lines later as a decrypt failure. Without this assertion the test passes
    # with the guard removed, because the decrypt branch catches the missing
    # binary too and reports something an operator cannot act on.
    [[ "$output" != *"failed to decrypt"* ]]
    [[ "$output" != *"Starting Squid proxy"* ]]
}

# bats test_tags=fast, hostonly
@test "C-17: a credential file that fails to decrypt aborts before the proxy starts" {
    _reg_fixture_dir
    _cred_fixture
    _cred_file_for "${REG_TMPDIR}/proj"
    _stub_age 'exit 1'

    run bash -c 'cd "'"${REG_TMPDIR}"'" && env -u GH_TOKEN PATH="'"${REG_TMPDIR}"'/bin:$PATH" \
        ENGINE=true CREDENTIALS_DIR="'"${REG_TMPDIR}"'/store" \
        bash start.sh "'"${REG_TMPDIR}"'/proj" 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed to decrypt"* ]]
    [[ "$output" == *"Fail-closed per docs/designs/0129-encrypted-credential-store.md"* ]]
    [[ "$output" != *"Starting Squid proxy"* ]]
}

# bats test_tags=fast, hostonly
@test "C-18: a decrypted credential is injected by name, and its value is never printed" {
    _reg_fixture_dir
    _cred_fixture
    _cred_file_for "${REG_TMPDIR}/proj"
    _stub_age 'printf "GH_TOKEN=must-not-appear\nPYPI_TOKEN=also-secret\n"'

    run bash -c 'cd "'"${REG_TMPDIR}"'" && env -u GH_TOKEN PATH="'"${REG_TMPDIR}"'/bin:$PATH" \
        ENGINE=true CREDENTIALS_DIR="'"${REG_TMPDIR}"'/store" \
        bash start.sh "'"${REG_TMPDIR}"'/proj" 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Creds:    2 injected (GH_TOKEN, PYPI_TOKEN)"* ]]
    [[ "$output" != *"must-not-appear"* ]]
    [[ "$output" != *"also-secret"* ]]
}

# bats test_tags=fast, hostonly
@test "C-19: a store inside the project directory aborts rather than being mounted" {
    _reg_fixture_dir
    _cred_fixture
    mkdir -p "${REG_TMPDIR}/proj/credentials"
    printf 'ciphertext\n' > "${REG_TMPDIR}/proj/credentials/$(printf '%s' "${REG_TMPDIR}/proj" | sha256sum | cut -d' ' -f1).age"
    _stub_age 'printf "GH_TOKEN=leaked\n"'

    run bash -c 'cd "'"${REG_TMPDIR}"'" && env -u GH_TOKEN PATH="'"${REG_TMPDIR}"'/bin:$PATH" \
        ENGINE=true CREDENTIALS_DIR="'"${REG_TMPDIR}"'/proj/credentials" \
        bash start.sh "'"${REG_TMPDIR}"'/proj" 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"is inside the project directory"* ]]
    [[ "$output" != *"Starting Squid proxy"* ]]
}

# bats test_tags=fast, hostonly
@test "C-20: start.sh and creds.sh deny the same credential names" {
    local in_start in_creds
    in_start="$(sed -n '/^    DENIED_CRED_KEYS=(/,/^    )$/p' "${SANDBOX_DIR}/start.sh" \
        | sed '1d;$d' | tr -s ' \n' ' ')"
    in_creds="$(sed -n '/^DENIED_KEYS=(/,/^)$/p' "${SANDBOX_DIR}/creds.sh" \
        | sed '1d;$d' | tr -s ' \n' ' ')"

    [ -n "$in_start" ]
    [ -n "$in_creds" ]
    [ "$in_start" = "$in_creds" ]
}

# An engine stand-in for C-21. `build` succeeds and is logged; `images` prints
# what Podman prints, repositories qualified as localhost/<name>; anything
# else exits 2 so an unexpected call fails the test rather than passing it.
_stub_build_engine() {
    cat > "${REG_TMPDIR}/engine" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    build)
        while [ "$#" -gt 0 ]; do
            [ "$1" = "-t" ] && { echo "build $2" >> "${STUB_LOG}"; break; }
            shift
        done
        exit 0
        ;;
    images)
        echo "REPOSITORY              TAG     IMAGE ID      CREATED      SIZE"
        for name in claude-base claude-crypto claude-systems claude-research claude-squid; do
            echo "localhost/${name}  latest  0123456789ab  1 hour ago  1 GB"
        done
        exit 0
        ;;
    *)
        echo "UNEXPECTED $*" >> "${STUB_LOG}"
        exit 2
        ;;
esac
STUB
    chmod +x "${REG_TMPDIR}/engine"
}

# bats test_tags=fast, hostonly
@test "C-21: bare build.sh exits 0 once every image builds, under Podman's image naming" {
    # The `all` path is the one no other test reaches: B-1 builds a single
    # target through build_with_deps. It exited 1 after a fully successful
    # build because its closing listing grepped `^claude-` while Podman names
    # local images localhost/claude-*, and pipefail plus set -e turned the
    # non-match into the script's status. That went unseen locally and turned
    # PR #169's container job red. A copy of build.sh is run beside the
    # committed config.sh only, so an operator's config.local.sh is never
    # sourced.
    REG_TMPDIR="$(mktemp -d)"
    cp "${SANDBOX_DIR}/build.sh" "${SANDBOX_DIR}/config.sh" "${REG_TMPDIR}/"
    _stub_build_engine
    export STUB_LOG="${REG_TMPDIR}/engine.log"

    run env -u IMAGE_PREFIX ENGINE="${REG_TMPDIR}/engine" bash "${REG_TMPDIR}/build.sh"
    [ "$status" -eq 0 ]

    # Base first, then every other declared profile, then Squid.
    local expected profiles
    profiles="$(bash -c 'source "$1/config.sh"; printf "%s\n" "${PROFILES[@]}"' _ "${REG_TMPDIR}")"
    expected="build claude-base"
    while IFS= read -r p; do
        [ "$p" = "base" ] && continue
        expected+=$'\n'"build claude-${p}"
    done <<< "$profiles"
    expected+=$'\n'"build claude-squid"
    [ "$(cat "$STUB_LOG")" = "$expected" ]
}

# --- Skill selection (docs/adr/013-skill-selection-and-external-skills.md) ---
#
# Run against a fixture global layer inside REG_TMPDIR, never the committed
# one, so a new skill does not change what these assert. The engine stand-in
# records start.sh's own /run/claude-global mount argument and lists the
# directory it names while start.sh is still running: the observation #173
# found missing, since every other global-layer test passes its own flags.
#
# Negative-controlled on 2026-10-28, one probe at a time against start.sh,
# each reverted before the next:
#   - every skill copied regardless of selection -> C-23, C-24
#   - the unknown-name check removed -> C-25, C-26. With only its `exit 1`
#     removed, nothing failed: the cp of the missing skill aborts under
#     set -e anyway, so C-25 also asserts the message.
#   - `readonly` dropped from the mount -> C-28
#   - cleanup() not removing the staging directory -> C-28
#   - the env capture collapsing empty into unset -> C-24, C-27
#   - the overlay hint removed -> C-26
#   - the mount sourcing global-claude/ instead of the copy -> C-23, C-24,
#     C-28

_skills_fixture() {
    _reg_fixture_dir
    _cred_fixture
    mkdir -p "${REG_TMPDIR}/global-claude/skills/alpha" \
             "${REG_TMPDIR}/global-claude/skills/beta" \
             "${REG_TMPDIR}/global-claude/templates" \
             "${REG_TMPDIR}/global-crypto/skills/gamma"
    printf 'claude\n' > "${REG_TMPDIR}/global-claude/CLAUDE.md"
    printf 'template\n' > "${REG_TMPDIR}/global-claude/templates/t.md"
    printf 'a\n' > "${REG_TMPDIR}/global-claude/skills/alpha/SKILL.md"
    printf 'b\n' > "${REG_TMPDIR}/global-claude/skills/beta/SKILL.md"
    printf 'g\n' > "${REG_TMPDIR}/global-crypto/skills/gamma/SKILL.md"

    export STUB_LOG="${REG_TMPDIR}/engine.log"
    : > "$STUB_LOG"
    cat > "${REG_TMPDIR}/engine" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "run" ] || exit 0
echo "run" >> "$STUB_LOG"
for arg in "$@"; do
    case "$arg" in
        *target=/run/claude-global*)
            src="${arg#*source=}"
            src="${src%%,*}"
            echo "mount ${arg}" >> "$STUB_LOG"
            (cd "$src" && find . -mindepth 1 | sort | sed 's|^|staged |') >> "$STUB_LOG"
            ;;
    esac
done
STUB
    chmod +x "${REG_TMPDIR}/engine"
}

# Runs the fixture's start.sh. The first argument is the profile; the rest
# are env assignments, so a test can set GLOBAL_SKILLS, set it empty, or
# leave it out. GLOBAL_SKILLS is always cleared from the inherited
# environment first.
_skills_start() {
    local profile="$1"; shift
    run env -u GLOBAL_SKILLS -u GH_TOKEN "$@" ENGINE="${REG_TMPDIR}/engine" \
        CREDENTIALS_DIR="${REG_TMPDIR}/store" \
        bash "${REG_TMPDIR}/start.sh" "${REG_TMPDIR}/proj" "$profile"
}

_staged() { sed -n 's/^staged //p' "$STUB_LOG"; }

# bats test_tags=fast, hostonly
@test "C-22: GLOBAL_SKILLS unset stages every skill and every top-level file" {
    _skills_fixture
    _skills_start base
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skills:   all (2)"* ]]
    [ "$(_staged)" = "$(printf '%s\n' ./CLAUDE.md ./skills ./skills/alpha \
        ./skills/alpha/SKILL.md ./skills/beta ./skills/beta/SKILL.md \
        ./templates ./templates/t.md)" ]
}

# bats test_tags=fast, hostonly
@test "C-23: GLOBAL_SKILLS names a subset, and only that subset is staged" {
    _skills_fixture
    _skills_start base GLOBAL_SKILLS=beta
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skills:   1 selected (beta)"* ]]
    _staged | grep -qx './skills/beta/SKILL.md'
    [ -z "$(_staged | grep alpha)" ]
    _staged | grep -qx './templates/t.md'
}

# bats test_tags=fast, hostonly
@test "C-24: GLOBAL_SKILLS set but empty stages no skill, unlike unset" {
    _skills_fixture
    _skills_start base GLOBAL_SKILLS=
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skills:   none selected"* ]]
    _staged | grep -qx './skills'
    [ -z "$(_staged | grep '^./skills/')" ]
    _staged | grep -qx './CLAUDE.md'
}

# bats test_tags=fast, hostonly
@test "C-25: an unknown skill name aborts before any container runs" {
    _skills_fixture
    _skills_start base GLOBAL_SKILLS="alpha nope"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GLOBAL_SKILLS names 'nope'"* ]]
    [ ! -s "$STUB_LOG" ]
}

# bats test_tags=fast, hostonly
@test "C-26: an overlay-only skill name aborts and says the overlay is not selectable" {
    _skills_fixture
    _skills_start crypto GLOBAL_SKILLS=gamma
    [ "$status" -eq 1 ]
    [[ "$output" == *"GLOBAL_SKILLS names 'gamma'"* ]]
    [[ "$output" == *"overlay skill"* ]]
    [ ! -s "$STUB_LOG" ]
}

# bats test_tags=fast, hostonly
@test "C-27: config.local.sh sets GLOBAL_SKILLS, and an empty env value still overrides it" {
    _skills_fixture
    printf 'GLOBAL_SKILLS="alpha"\n' > "${REG_TMPDIR}/config.local.sh"

    _skills_start base
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skills:   1 selected (alpha)"* ]]

    : > "$STUB_LOG"
    _skills_start base GLOBAL_SKILLS=
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skills:   none selected"* ]]
}

# bats test_tags=fast, hostonly
@test "C-28: the global mount is read-only and sources a staged copy that is removed on exit" {
    _skills_fixture
    _skills_start base
    [ "$status" -eq 0 ]
    local mount src
    mount="$(sed -n 's/^mount //p' "$STUB_LOG")"
    [[ "$mount" == *",readonly"* ]]
    src="${mount#*source=}"
    src="${src%%,*}"
    [ "$src" != "${REG_TMPDIR}/global-claude" ]
    [ ! -e "$src" ]
}
