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

load 'lib/profiles'

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
    cp -r "${SANDBOX_DIR}/lib" "${REG_TMPDIR}/lib"
    mkdir "${REG_TMPDIR}/config"
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
        source "./config/config.sh"
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
        source "./config/config.sh"
        echo "$ENGINE"
    '
    [ "$status" -eq 0 ]
    [ "$output" != "sentinel-default-value" ]
}

# bats test_tags=fast, hostonly
@test "C-3: config.sh's PROFILES matches the profile directories actually present" {
    run declared_profiles
    [ "$status" -eq 0 ]
    [ -n "$output" ]

    # Every declared profile has a build context...
    local p dir
    for p in $output; do
        [ -f "${SANDBOX_DIR}/profiles/${p}/Dockerfile" ] || { echo "declared, no Dockerfile: $p" >&2; return 1; }
    done

    # ...and every build context under profiles/ is declared.
    for dir in "${SANDBOX_DIR}"/profiles/*/Dockerfile; do
        p="$(basename "$(dirname "$dir")")"
        echo "$output" | grep -qx "$p" || { echo "Dockerfile, not declared: $p" >&2; return 1; }
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
        source "./config/config.sh"
        for key in "${!PROFILE_BASE[@]}"; do
            printf "%s\n" "${PROFILE_BASE[$key]}"
        done
    '
    [ "$status" -eq 0 ]

    profiles_list=$(bash -c '
        set -euo pipefail
        cd "'"${SANDBOX_DIR}"'"
        source "./config/config.sh"
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
@test "C-6: every script reaches config.sh through lib/config.sh, not a re-copied literal list" {
    # Structural guard for the drift problem this design exists to fix:
    # every script must read PROFILES from the same sourced file rather
    # than hardcoding its own copy that could silently diverge again. Each
    # reaches config/config.sh through lib/config.sh, which also refuses a
    # config.local.sh left at the pre-#189 root path
    # (docs/designs/0147-cli-credential-input-and-ergonomics.md,
    # docs/designs/0189-profile-realignment-and-layout.md).
    grep -Eq 'source "\$\{?SANDBOX_DIR\}?/config/config\.sh"' "${SANDBOX_DIR}/lib/config.sh"
    local script
    for script in build.sh start.sh creds.sh check-auto-memory.sh; do
        grep -Eq 'source "\$\{?SANDBOX_DIR\}?/lib/config\.sh"' "${SANDBOX_DIR}/${script}" \
            || { echo "${script} does not source lib/config.sh" >&2; return 1; }
        ! grep -Eq 'source "\$\{?SANDBOX_DIR\}?/config(/config)?(\.local)?\.sh"' "${SANDBOX_DIR}/${script}" \
            || { echo "${script} sources a config layer directly" >&2; return 1; }
    done
}

# C-7 onward: named project registry (docs/designs/0030-named-project-registry.md)

# bats test_tags=fast, hostonly
@test "C-7: @name resolves to the registered path and its registry profile" {
    _reg_fixture_dir
    mkdir -p "${REG_TMPDIR}/mylib"
    cat > "${REG_TMPDIR}/config/config.sh" <<EOF
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
    cat > "${REG_TMPDIR}/config/config.sh" <<EOF
PROJECT_PATH[mylib]="${REG_TMPDIR}/mylib"
PROJECT_PROFILE[mylib]=crypto
EOF

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash start.sh @mylib base 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Image:    claude-base"* ]]
}

# bats test_tags=fast, hostonly
@test "C-9: an unknown @name exits non-zero and never reaches the engine" {
    _reg_fixture_dir
    cat > "${REG_TMPDIR}/config/config.sh" <<EOF
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
    cat > "${REG_TMPDIR}/config/config.sh" <<EOF
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
    cat > "${REG_TMPDIR}/config/config.sh" <<EOF
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
    : > "${REG_TMPDIR}/config/config.sh"   # no committed entries
    cat > "${REG_TMPDIR}/config/config.local.sh" <<EOF
PROJECT_PATH[localonly]="${REG_TMPDIR}/localonly"
PROJECT_PROFILE[localonly]=crypto
EOF

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash start.sh @localonly 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project:  ${REG_TMPDIR}/localonly"* ]]
    [[ "$output" == *"Image:    claude-crypto"* ]]
    [[ "$output" != *"Warning:"* ]]
}

# bats test_tags=fast, hostonly
@test "C-13: config.local.sh redefining a committed name is reverted and warned, not honored" {
    _reg_fixture_dir
    mkdir -p "${REG_TMPDIR}/committed-real" "${REG_TMPDIR}/attempted-override"
    cat > "${REG_TMPDIR}/config/config.sh" <<EOF
PROJECT_PATH[committed]="${REG_TMPDIR}/committed-real"
PROJECT_PROFILE[committed]=crypto
EOF
    cat > "${REG_TMPDIR}/config/config.local.sh" <<EOF
PROJECT_PATH[committed]="${REG_TMPDIR}/attempted-override"
PROJECT_PROFILE[committed]=base
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
        # PARENT_IMAGE goes to its own log, so C-21's exact comparison of
        # the build order is unaffected by it.
        # The build context is the last argument; its directory name is the
        # profile built.
        parent="" tag="" context="${!#}"
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --build-arg) [[ "$2" == PARENT_IMAGE=* ]] && parent="${2#PARENT_IMAGE=}" ;;
                -t) tag="$2"; echo "build $2" >> "${STUB_LOG}" ;;
            esac
            shift
        done
        echo "${tag} ${parent:-none} $(basename "$context")" >> "${STUB_LOG}.parents"
        exit 0
        ;;
    images)
        echo "REPOSITORY              TAG     IMAGE ID      CREATED      SIZE"
        for name in claude-base claude-crypto claude-squid; do
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
    cp "${SANDBOX_DIR}/build.sh" "${REG_TMPDIR}/"
    cp -r "${SANDBOX_DIR}/lib" "${REG_TMPDIR}/lib"
    mkdir "${REG_TMPDIR}/config"
    cp "${SANDBOX_DIR}/config/config.sh" "${REG_TMPDIR}/config/"
    _stub_build_engine
    export STUB_LOG="${REG_TMPDIR}/engine.log"

    run env -u IMAGE_PREFIX ENGINE="${REG_TMPDIR}/engine" bash "${REG_TMPDIR}/build.sh"
    [ "$status" -eq 0 ]

    # Base first, then every other declared profile, then Squid.
    local expected profiles
    profiles="$(bash -c 'source "$1/config/config.sh"; printf "%s\n" "${PROFILES[@]}"' _ "${REG_TMPDIR}")"
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
    printf 'GLOBAL_SKILLS="alpha"\n' > "${REG_TMPDIR}/config/config.local.sh"

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

# C-29 onward: creds.sh's command line
# (docs/designs/0147-cli-credential-input-and-ergonomics.md). The store is a
# stand-in: its 'age' writes stdin to -o in the clear and decrypts by cat, so
# a test reads what creds.sh stored straight from the file. A file starting
# with CORRUPT fails to decrypt.
#
# Negative controls, each run against the test named: skipping @name
# resolution (C-29, C-30); ${!NAME} for printenv (C-33); dropping the
# line-break check (C-35); ignoring an extra argument (C-34); reading stdin
# without stripping (C-31); letting a non-tty stdin override a flag (C-32,
# C-33); a fixed --list origin, no missing marker, or --list after an engine
# call (C-36; the last also C-37); --all printing whole lines, stopping at
# the first unreadable file, or not dispatched (C-38); an error on stdout,
# age checked before arguments, or no hint for an @name as migrate's <old>
# (C-39).

# Copies creds.sh and lib/ into REG_TMPDIR, registers 'mylib' at
# REG_TMPDIR/proj in config.sh, and creates an initialised store.
_creds_fixture() {
    _reg_fixture_dir
    _cred_fixture
    cp "${SANDBOX_DIR}/creds.sh" "${REG_TMPDIR}/creds.sh"
    cat > "${REG_TMPDIR}/config/config.sh" <<CONF
declare -A PROJECT_PATH=( [mylib]="${REG_TMPDIR}/proj" )
declare -A PROJECT_PROFILE=( [mylib]="base" )
CONF
    printf 'wrapped\n' > "${REG_TMPDIR}/store/identity.age"
    printf 'age1stub\n' > "${REG_TMPDIR}/store/recipient.pub"
    _stub_age '
out=""; dec=0; last=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -d) dec=1; shift ;;
        -i|-R|-r) shift 2 ;;
        *) last="$1"; shift ;;
    esac
done
if [ -n "$out" ]; then cat > "$out"; exit; fi
if [ "$dec" = 1 ]; then grep -q "^CORRUPT" "$last" && exit 1; cat "$last"; fi'
}

# Runs the fixture's creds.sh with the stand-in age and store. Arguments go
# to creds.sh; stdin is the caller's, and bats' run captures stderr too. A
# call whose value does not come from stdin still redirects it from
# /dev/null, so a regression that reads stdin fails instead of hanging.
_creds() {
    PATH="${REG_TMPDIR}/bin:$PATH" CREDENTIALS_DIR="${REG_TMPDIR}/store" \
        bash "${REG_TMPDIR}/creds.sh" "$@"
}

# The stored file for a project path, named as start.sh names it.
_store_file() {
    printf '%s/store/%s.age' "$REG_TMPDIR" \
        "$(printf '%s' "$(realpath "$1")" | sha256sum | cut -d' ' -f1)"
}

# bats test_tags=fast, hostonly
@test "C-29: creds.sh resolves @name to the same file start.sh decrypts" {
    _creds_fixture

    run _creds add @mylib API_KEY <<< 'v1'
    [ "$status" -eq 0 ]
    [ "$(cat "$(_store_file "${REG_TMPDIR}/proj")")" = "API_KEY=v1" ]

    run _creds list @mylib < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"API_KEY"* ]]
}

# bats test_tags=fast, hostonly
@test "C-30: an unknown @name in creds.sh is refused by name, and nothing is stored" {
    _creds_fixture

    run _creds add @nosuch API_KEY <<< 'v1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown project 'nosuch'"* ]]
    [[ "$output" == *"mylib"* ]]
    [ -z "$(ls "${REG_TMPDIR}/store" | grep -vx 'identity.age' | grep '\.age$')" ]
}

# bats test_tags=fast, hostonly
@test "C-31: a piped value is stored, with its trailing newline stripped" {
    _creds_fixture

    run _creds add "${REG_TMPDIR}/proj" API_KEY < <(printf 'from-pipe\n\n')
    [ "$status" -eq 0 ]
    [ "$(cat "$(_store_file "${REG_TMPDIR}/proj")")" = "API_KEY=from-pipe" ]
}

# bats test_tags=fast, hostonly
@test "C-32: --value-file is read, wins over stdin, and a missing file is refused" {
    _creds_fixture
    printf 'from-file\n' > "${REG_TMPDIR}/value"

    run _creds add "${REG_TMPDIR}/proj" API_KEY --value-file "${REG_TMPDIR}/value" <<< 'from-pipe'
    [ "$status" -eq 0 ]
    [ "$(cat "$(_store_file "${REG_TMPDIR}/proj")")" = "API_KEY=from-file" ]

    run _creds add "${REG_TMPDIR}/proj" OTHER --value-file "${REG_TMPDIR}/absent" < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a readable file"* ]]
}

# bats test_tags=fast, hostonly
@test "C-33: --from-env reads the environment, never creds.sh's own variables" {
    _creds_fixture

    SECRET_SRC=from-env run _creds add "${REG_TMPDIR}/proj" API_KEY --from-env SECRET_SRC < /dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$(_store_file "${REG_TMPDIR}/proj")")" = "API_KEY=from-env" ]

    # 'key' is a local of cmd_add holding "OTHER": ${!NAME} would store it.
    run _creds add "${REG_TMPDIR}/proj" OTHER --from-env key < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"empty value"* ]]
    [[ "$(cat "$(_store_file "${REG_TMPDIR}/proj")")" != *OTHER* ]]
}

# bats test_tags=fast, hostonly
@test "C-34: a value given as an argument is refused, not echoed, and not stored" {
    _creds_fixture

    run _creds add "${REG_TMPDIR}/proj" API_KEY s3cret-literal < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"visible in ps"* ]]
    [[ "$output" != *"s3cret-literal"* ]]
    [ ! -e "$(_store_file "${REG_TMPDIR}/proj")" ]
}

# bats test_tags=fast, hostonly
@test "C-35: a value with a line break is refused rather than splitting the store" {
    _creds_fixture

    run _creds add "${REG_TMPDIR}/proj" API_KEY < <(printf 'line1\nINJECTED=1\n')
    [ "$status" -ne 0 ]
    [[ "$output" == *"line break"* ]]
    [ ! -e "$(_store_file "${REG_TMPDIR}/proj")" ]
}

# bats test_tags=fast, hostonly
@test "C-36: start.sh --list shows each name's path, profile and layer, with no engine" {
    _reg_fixture_dir
    mkdir -p "${REG_TMPDIR}/proj"
    cat > "${REG_TMPDIR}/config/config.sh" <<EOF2
declare -A PROJECT_PATH=( [mylib]="${REG_TMPDIR}/proj" [gone]="${REG_TMPDIR}/absent" )
declare -A PROJECT_PROFILE=( [mylib]=crypto [gone]=base )
EOF2
    cat > "${REG_TMPDIR}/config/config.local.sh" <<EOF2
PROJECT_PATH[extra]="${REG_TMPDIR}/proj"; PROJECT_PROFILE[extra]=base
PROJECT_PATH[mylib]=/etc
EOF2

    # ENGINE=false: any engine call would fail, so exit 0 proves none ran.
    run env ENGINE=false bash "${REG_TMPDIR}/start.sh" --list
    [ "$status" -eq 0 ]
    echo "$output" | grep -Eq "^@mylib +crypto +config\.sh +${REG_TMPDIR}/proj\$"
    echo "$output" | grep -Eq "^@extra +base +config\.local\.sh +${REG_TMPDIR}/proj\$"
    echo "$output" | grep -Eq "^@gone .*${REG_TMPDIR}/absent +\(missing\)\$"
    [[ "$output" == *"redefines committed project 'mylib'"* ]]
}

# bats test_tags=fast, hostonly
@test "C-37: start.sh --list with an empty registry says so and exits 0" {
    _reg_fixture_dir
    printf 'declare -A PROJECT_PATH=()\ndeclare -A PROJECT_PROFILE=()\n' > "${REG_TMPDIR}/config/config.sh"

    run env ENGINE=false bash "${REG_TMPDIR}/start.sh" --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No projects registered"* ]]
}

# bats test_tags=fast, hostonly
@test "C-38: creds.sh list --all shows every project's key names, never a value, and reports a bad file" {
    _creds_fixture
    mkdir -p "${REG_TMPDIR}/proj2" "${REG_TMPDIR}/proj3"
    _creds add "${REG_TMPDIR}/proj" API_KEY <<< 'value-one'
    _creds add "${REG_TMPDIR}/proj2" PYPI_TOKEN <<< 'value-two'
    printf 'CORRUPT\n' > "$(_store_file "${REG_TMPDIR}/proj3")"
    printf '%s\t%s\n' "$(basename "$(_store_file "${REG_TMPDIR}/proj3")" .age)" \
        "$(realpath "${REG_TMPDIR}/proj3")" >> "${REG_TMPDIR}/store/index"

    run _creds list --all < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"$(realpath "${REG_TMPDIR}/proj")"$'\n'"  API_KEY"* ]]
    [[ "$output" == *"$(realpath "${REG_TMPDIR}/proj2")"$'\n'"  PYPI_TOKEN"* ]]
    [[ "$output" == *"could not decrypt"* ]]
    [[ "$output" == *"1 of 3"* ]]
    [[ "$output" != *value-one* ]]
    [[ "$output" != *value-two* ]]
}

# bats test_tags=fast, hostonly
@test "C-39: argument errors go to stderr and name the command that fixes them" {
    bats_require_minimum_version 1.5.0
    _creds_fixture

    run --separate-stderr env ENGINE=true bash "${REG_TMPDIR}/start.sh" @nosuch
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"unknown project 'nosuch'"* ]]
    [[ "$stderr" == *"./start.sh --list"* ]]

    # Arguments are checked before the store or age: a PATH without age, and
    # an empty store, prove it. The PATH keeps dirname, without which
    # creds.sh would take the caller's directory for its own and source the
    # config there.
    run --separate-stderr env PATH="$(_path_without_age)" \
        CREDENTIALS_DIR="${REG_TMPDIR}/nostore" bash "${REG_TMPDIR}/creds.sh" add "${REG_TMPDIR}/proj"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"Usage: ./creds.sh add <project> <KEY>"* ]]

    run --separate-stderr _creds frob
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"unknown command 'frob'"* ]]

    run --separate-stderr _creds migrate @mylib "${REG_TMPDIR}/proj"
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"not an @name"* ]]
}

# bats test_tags=fast, hostonly
@test "C-40: a config.local.sh left at the pre-#189 root path aborts every launcher" {
    # Ignoring it would run the session on defaults the operator had
    # overridden, with nothing to say so. lib/config.sh refuses it instead,
    # and every script that loads config goes through lib/config.sh (C-6).
    _reg_fixture_dir
    mkdir -p "${REG_TMPDIR}/mylib"
    cat > "${REG_TMPDIR}/config/config.sh" <<EOF
PROJECT_PATH[mylib]="${REG_TMPDIR}/mylib"
PROJECT_PROFILE[mylib]=crypto
EOF
    printf 'MAIN_MEMORY="8g"\n' > "${REG_TMPDIR}/config.local.sh"
    cp "${SANDBOX_DIR}/build.sh" "${REG_TMPDIR}/build.sh"

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash start.sh @mylib 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"config.local.sh is no longer read."* ]]
    [[ "$output" == *"${REG_TMPDIR}/config/config.local.sh"* ]]
    [[ "$output" != *"Project:"* ]]

    run bash -c 'cd "'"${REG_TMPDIR}"'" && ENGINE=true bash build.sh crypto 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"config.local.sh is no longer read."* ]]
    [[ "$output" != *"Building"* ]]
}

# C-41 onward: profile composition (docs/designs/0194-profile-composition.md)

# bats test_tags=fast, hostonly
@test "C-41: every child Dockerfile follows the profile contract" {
    # Composition builds one member on top of another, so each child must
    # take its parent as an argument and leave the image as it found it:
    # Decision 1 of the design. Instructions are matched case-insensitively,
    # as the engine reads them. B-5's fixture profiles are held to it too,
    # since B-5 is what shows the contract is enough.
    local p f first_user last_user first_run line
    local -a files=()
    for p in $(declared_child_profiles); do
        files+=("${SANDBOX_DIR}/profiles/${p}/Dockerfile")
    done
    [ "${#files[@]}" -gt 0 ]
    files+=("${SANDBOX_DIR}"/tests/fixtures/profiles/*/Dockerfile)
    for f in "${files[@]}"; do
        p="${f#"${SANDBOX_DIR}/"}"

        [ "$(grep -ciE '^[[:space:]]*FROM[[:space:]]' "$f")" -eq 1 ] \
            || { echo "${p}: not exactly one FROM" >&2; return 1; }
        grep -qiE '^[[:space:]]*FROM[[:space:]]+\$\{PARENT_IMAGE\}[[:space:]]*$' "$f" \
            || { echo "${p}: FROM is not \${PARENT_IMAGE}" >&2; return 1; }
        grep -qiE '^[[:space:]]*ARG[[:space:]]+PARENT_IMAGE=claude-base[[:space:]]*$' "$f" \
            || { echo "${p}: no ARG PARENT_IMAGE=claude-base default" >&2; return 1; }

        ! grep -qiE '^[[:space:]]*(ENTRYPOINT|CMD)([[:space:]]|\[)' "$f" \
            || { echo "${p}: sets ENTRYPOINT or CMD, which claude-base owns" >&2; return 1; }

        first_user="$(grep -niE '^[[:space:]]*USER[[:space:]]' "$f" | head -1)"
        last_user="$(grep -iE '^[[:space:]]*USER[[:space:]]' "$f" | tail -1 | awk '{print $2}')"
        first_run="$(grep -niE '^[[:space:]]*(RUN|COPY|ADD)[[:space:]]' "$f" | head -1 | cut -d: -f1)"
        if [ -n "$first_run" ]; then
            [ -n "$first_user" ] && [ "${first_user%%:*}" -lt "$first_run" ] \
                && [ "$(echo "${first_user#*:}" | awk '{print $2}')" = "root" ] \
                || { echo "${p}: work starts before an explicit USER root" >&2; return 1; }
        fi
        [ "$last_user" = "claude-agent" ] \
            || { echo "${p}: does not end as USER claude-agent" >&2; return 1; }

        while IFS= read -r line; do
            [[ "$line" == *'${PATH}'* || "$line" == *'$PATH'* ]] \
                || { echo "${p}: ENV PATH replaces PATH: ${line}" >&2; return 1; }
        done < <(grep -iE '^[[:space:]]*ENV[[:space:]]+PATH[=[:space:]]' "$f")
    done
}

# bats test_tags=fast, hostonly
@test "C-42: build.sh builds each child on its parent under the configured IMAGE_PREFIX" {
    # Before #194 the child named claude-base literally, so a non-default
    # IMAGE_PREFIX built it on a stale or missing image. Base and Squid have
    # no parent and are given none.
    REG_TMPDIR="$(mktemp -d)"
    cp "${SANDBOX_DIR}/build.sh" "${REG_TMPDIR}/"
    cp -r "${SANDBOX_DIR}/lib" "${REG_TMPDIR}/lib"
    mkdir "${REG_TMPDIR}/config"
    cp "${SANDBOX_DIR}/config/config.sh" "${REG_TMPDIR}/config/"
    _stub_build_engine
    export STUB_LOG="${REG_TMPDIR}/engine.log"

    run env IMAGE_PREFIX=sbx ENGINE="${REG_TMPDIR}/engine" bash "${REG_TMPDIR}/build.sh"
    [ "$status" -eq 0 ]

    local p expected
    expected="sbx-base none base"
    for p in $(declared_child_profiles); do
        expected+=$'\n'"sbx-${p} sbx-base ${p}"
    done
    expected+=$'\n'"sbx-squid none squid"
    [ "$(cat "${STUB_LOG}.parents")" = "$expected" ]
}

# A build.sh fixture with four fixture profiles beside base: alpha, beta and
# delta build on base, gamma builds on alpha. The committed config.sh is not
# copied, so these tests do not move when real profiles do. $1, if given, is
# appended to config.sh.
_combo_fixture() {
    REG_TMPDIR="$(mktemp -d)"
    cp "${SANDBOX_DIR}/build.sh" "${SANDBOX_DIR}/start.sh" "${REG_TMPDIR}/"
    cp -r "${SANDBOX_DIR}/lib" "${REG_TMPDIR}/lib"
    mkdir "${REG_TMPDIR}/config"
    cat > "${REG_TMPDIR}/config/config.sh" <<CONF
PROFILES=(base alpha beta gamma delta)
declare -A PROFILE_BASE=( [alpha]=base [beta]=base [gamma]=alpha [delta]=base )
declare -A COMBOS=()
${1:-}
CONF
    _stub_build_engine
    export STUB_LOG="${REG_TMPDIR}/engine.log"
}

# bats test_tags=fast, hostonly
@test "C-43: every invalid combination aborts build.sh, naming it and the rule, before any build" {
    bats_require_minimum_version 1.5.0
    local def expect
    while IFS='|' read -r def expect; do
        _combo_fixture "$def"
        run --separate-stderr env -u IMAGE_PREFIX ENGINE="${REG_TMPDIR}/engine" \
            bash "${REG_TMPDIR}/build.sh" squid
        [ "$status" -ne 0 ] || { echo "accepted: $def" >&2; return 1; }
        [[ "$stderr" == *"invalid combination"*"$expect"* ]] \
            || { echo "for $def, stderr was: $stderr" >&2; return 1; }
        [ ! -s "$STUB_LOG" ] || { echo "built despite: $def" >&2; return 1; }
        rm -rf "$REG_TMPDIR"
    done <<'CASES'
COMBOS[Bad_Name]="alpha beta"|must match
COMBOS[all]="alpha beta"|reserved build target
COMBOS[squid]="alpha beta"|reserved build target
COMBOS[alpha]="alpha beta"|already a profile
COMBOS[solo]="alpha"|at least two members
COMBOS[twice]="alpha alpha"|'alpha' is repeated
COMBOS[ghost]="alpha nope"|'nope' is not a profile
COMBOS[withbase]="base alpha"|'base' is not a member
COMBOS[nested]="beta gamma"|'gamma' does not build on base
CASES
}

# bats test_tags=fast, hostonly
@test "C-44: config.local.sh may add a combination but not redefine a committed one" {
    bats_require_minimum_version 1.5.0
    _combo_fixture 'COMBOS[shared]="alpha beta"'
    cat > "${REG_TMPDIR}/config/config.local.sh" <<'LOCAL'
COMBOS[shared]="beta alpha"
COMBOS[mine]="beta alpha"
LOCAL

    run --separate-stderr bash -c '
        set -euo pipefail
        SANDBOX_DIR="$1"
        source "$1/lib/config.sh"
        validate_combos
        for n in $(printf "%s\n" "${!COMBOS[@]}" | sort); do echo "$n=${COMBOS[$n]}"; done
    ' _ "$REG_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = $'mine=beta alpha\nshared=alpha beta' ]
    [[ "$stderr" == *"Warning: config.local.sh redefines committed combination 'shared'; ignoring the local value (config.sh wins)."* ]]
}

# bats test_tags=fast, hostonly
@test "C-45: an invalid combination does not block creds.sh or start.sh --list" {
    # Credential management and the registry listing read no combination,
    # so a typo in one must not lock the operator out of them.
    _combo_fixture 'COMBOS[solo]="alpha"'
    cp "${SANDBOX_DIR}/creds.sh" "${REG_TMPDIR}/"
    mkdir -p "${REG_TMPDIR}/store"

    run env ENGINE=true bash "${REG_TMPDIR}/start.sh" --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No projects registered"* ]]

    run env CREDENTIALS_DIR="${REG_TMPDIR}/store" bash "${REG_TMPDIR}/creds.sh" list --all
    [[ "$output" != *"invalid combination"* ]]

    run env ENGINE=true bash "${REG_TMPDIR}/start.sh" "${REG_TMPDIR}" base
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid combination 'solo'"* ]]
}

# bats test_tags=fast, hostonly
@test "C-46: build.sh <combination> builds base, then each member on the previous result" {
    _combo_fixture 'COMBOS[trio]="beta alpha delta"
COMBOS[pair]="delta alpha"'

    run env IMAGE_PREFIX=sbx ENGINE="${REG_TMPDIR}/engine" bash "${REG_TMPDIR}/build.sh" trio
    [ "$status" -eq 0 ]
    [ "$(cat "${STUB_LOG}.parents")" = "sbx-base none base
sbx-beta sbx-base beta
sbx-trio:part-2 sbx-beta alpha
sbx-trio sbx-trio:part-2 delta" ]

    # Two members leave no intermediate tag.
    rm "${STUB_LOG}.parents"
    run env IMAGE_PREFIX=sbx ENGINE="${REG_TMPDIR}/engine" bash "${REG_TMPDIR}/build.sh" pair
    [ "$status" -eq 0 ]
    [ "$(cat "${STUB_LOG}.parents")" = "sbx-base none base
sbx-delta sbx-base delta
sbx-pair sbx-delta alpha" ]
}

# bats test_tags=fast, hostonly
@test "C-47: bare build.sh builds combinations after profiles, in name order, and names them" {
    # Bash lists these two keys as "mm bb", so the order asserted is the
    # sort, not the hash table's.
    _combo_fixture 'COMBOS[mm]="alpha beta"
COMBOS[bb]="beta alpha"'

    run env IMAGE_PREFIX=sbx ENGINE="${REG_TMPDIR}/engine" bash "${REG_TMPDIR}/build.sh"
    [ "$status" -eq 0 ]
    # Profiles, then bb's chain, then mm's, then Squid. The repeated base and
    # first-member builds are layer-cache no-ops on a real engine.
    [ "$(grep -E '^sbx-(bb|mm|squid)' "${STUB_LOG}.parents")" = "sbx-bb sbx-beta alpha
sbx-mm sbx-alpha beta
sbx-squid none squid" ]
    [ "$(sed -n '1,5p' "${STUB_LOG}.parents" | cut -d' ' -f1 | tr '\n' ' ')" = "sbx-base sbx-alpha sbx-beta sbx-gamma sbx-delta " ]
    [[ "$output" == *"  sbx-bb"*"  sbx-mm"*"  sbx-squid"* ]]

    run env ENGINE="${REG_TMPDIR}/engine" bash "${REG_TMPDIR}/build.sh" nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"Combinations: bb mm"* ]]
}
