#!/usr/bin/env bats
# test_global_layer.bats — Group 4: Global Layer Injection (SDD §4.4)
#
# Exercises entrypoint.sh's injection logic directly via engine_run with the
# same --mount flags start.sh derives, substituting a non-interactive command
# for the CMD ["claude"] default (which needs a TTY and would hang here).
# This tests the injection mechanism itself (SDD §3.4: assert on outcomes,
# not implementation details) rather than any specific per-image overlay's
# content — no global-crypto/ overlay exists in the repo yet, so G-2 uses a
# synthetic fixture overlay instead of assuming one.

load 'lib/engine'
load 'lib/teardown'

SANDBOX_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
GLOBAL_BASE="${SANDBOX_DIR}/global-claude"
OVERLAY_FIXTURE="${BATS_TEST_DIRNAME}/fixtures/global-overlay-fixture"

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

# bats test_tags=fast
@test "G-1: base global layer is applied to a new base-image session" {
    register_container "$CONTAINER_NAME"
    run engine_run --rm --name "$CONTAINER_NAME" \
        --mount "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly" \
        claude-base cat /home/claude-agent/.claude/CLAUDE.md
    [ "$status" -eq 0 ]

    # entrypoint.sh always runs first and logs "[entrypoint] ..." lines to
    # stdout before exec-ing the overridden CMD — filter those out rather
    # than diffing the raw combined output.
    cat_output=$(echo "$output" | grep -v '^\[entrypoint\]')
    diff <(echo "$cat_output") "${GLOBAL_BASE}/CLAUDE.md"
}

# bats test_tags=fast
@test "G-2: overlay layer is applied alongside the base layer" {
    register_container "$CONTAINER_NAME"
    run engine_run --rm --name "$CONTAINER_NAME" \
        --mount "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly" \
        --mount "type=bind,source=${OVERLAY_FIXTURE},target=/run/claude-overlay,readonly" \
        claude-base sh -c 'test -f /home/claude-agent/.claude/CLAUDE.md && test -f /home/claude-agent/.claude/overlay-marker.md && echo both-present'
    [ "$status" -eq 0 ]
    [[ "$output" == *"both-present"* ]]
}

# bats test_tags=fast
@test "G-3: /run/claude-global is not writable (OS-level readonly mount)" {
    register_container "$CONTAINER_NAME"
    run engine_run --rm --name "$CONTAINER_NAME" \
        --mount "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly" \
        claude-base touch /run/claude-global/should-fail
    [ "$status" -ne 0 ]
    [[ "$output" == *"Read-only file system"* ]]
}

# bats test_tags=fast
@test "G-4: a file written to ~/.claude/memory/ does not leak to the host source dir" {
    register_container "$CONTAINER_NAME"
    engine_run --rm --name "$CONTAINER_NAME" \
        --mount "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly" \
        claude-base sh -c 'mkdir -p /home/claude-agent/.claude/memory && echo leaked > /home/claude-agent/.claude/memory/leak-test.txt'

    [ ! -e "${GLOBAL_BASE}/memory/leak-test.txt" ]
}

# bats test_tags=fast
@test "G-5: a file written in one session is not visible from a second, concurrent session" {
    name_a="test-claude-base-a-$$"
    name_b="test-claude-base-b-$$"
    register_container "$name_a"
    register_container "$name_b"

    engine_run -d --rm --name "$name_a" \
        --mount "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly" \
        claude-base sleep 30
    engine_run -d --rm --name "$name_b" \
        --mount "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly" \
        claude-base sleep 30

    engine_exec "$name_a" sh -c 'echo session-a-only > /home/claude-agent/.claude/session-marker.txt'

    run engine_exec "$name_b" test -e /home/claude-agent/.claude/session-marker.txt
    [ "$status" -ne 0 ]
}

# bats test_tags=fast
@test "G-6: settings.json declares Write(/run/*) as an app-layer deny rule" {
    # Full dynamic enforcement (an actual Claude Code turn attempting the
    # write and getting denied) would require driving a live agent turn,
    # which needs ANTHROPIC_API_KEY — forbidden by SDD §7.2. This test
    # verifies the control is declared and present; end-to-end enforcement
    # is a documented residual gap, not silently assumed to be covered.
    run grep -q '"Write(/run/\*)"' "${SANDBOX_DIR}/settings.json"
    [ "$status" -eq 0 ]
}

# Entrypoint commit-msg hook checks (issue #54).
#
# These are the first tests in the suite to assert on entrypoint stdout —
# G-1 here, B-1 in test_build.bats and R-1 in test_runtime_posture.bats all
# filter those lines out because they are noise for what those tests assert.
# Here the log line is the assertion: the entrypoint's only output for a
# drifted hook is what it prints.
#
# Tagged `fast` and not `hostonly`: this file's setup() requires a reachable
# engine and a built claude-base, so CI (--filter-tags hostonly) does not run
# them. The documented pre-merge gate `bats tests/` is what exercises these.

# bats test_tags=fast
@test "G-7: a commit-msg hook differing from the shipped one is reported as drift" {
    register_container "$CONTAINER_NAME"

    G7_TMPDIR="$(mktemp -d)"
    mkdir -p "${G7_TMPDIR}/.git/hooks"
    printf '#!/usr/bin/env bash\n# a hook predating the trailer widening\nexit 0\n' \
        > "${G7_TMPDIR}/.git/hooks/commit-msg"
    chmod +x "${G7_TMPDIR}/.git/hooks/commit-msg"

    relabel_arg=""
    userns_args=()
    if [ "$ENGINE" = "podman" ]; then
        relabel_arg=",relabel=shared"
        userns_args=(--userns=keep-id:uid=1000,gid=1000)
    fi

    run engine_run --rm --name "$CONTAINER_NAME" \
        --mount "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly${relabel_arg}" \
        --mount "type=bind,source=${G7_TMPDIR},target=/workspace${relabel_arg}" \
        "${userns_args[@]}" \
        claude-base true

    # Container must still start: the check is warn-only, never fatal.
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: installed commit-msg hook differs from the shipped one"* ]]

    # And the drifted hook must be left exactly as it was — the entrypoint
    # reports, it does not resolve.
    [ "$(sed -n '2p' "${G7_TMPDIR}/.git/hooks/commit-msg")" = "# a hook predating the trailer widening" ]

    rm -rf "$G7_TMPDIR"
}

# bats test_tags=fast
@test "G-8: a commit-msg hook matching the shipped one is reported as current" {
    register_container "$CONTAINER_NAME"

    G8_TMPDIR="$(mktemp -d)"
    mkdir -p "${G8_TMPDIR}/.git/hooks"
    cp "${GLOBAL_BASE}/hooks/commit-msg" "${G8_TMPDIR}/.git/hooks/commit-msg"
    chmod +x "${G8_TMPDIR}/.git/hooks/commit-msg"

    relabel_arg=""
    userns_args=()
    if [ "$ENGINE" = "podman" ]; then
        relabel_arg=",relabel=shared"
        userns_args=(--userns=keep-id:uid=1000,gid=1000)
    fi

    run engine_run --rm --name "$CONTAINER_NAME" \
        --mount "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly${relabel_arg}" \
        --mount "type=bind,source=${G8_TMPDIR},target=/workspace${relabel_arg}" \
        "${userns_args[@]}" \
        claude-base true

    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: commit-msg hook matches the shipped version"* ]]
    [[ "$output" != *"WARNING: installed commit-msg hook differs"* ]]

    rm -rf "$G8_TMPDIR"
}
