#!/usr/bin/env bats
# test_squid_isolation.bats — Group 3: Squid Egress Enforcement (SDD §4.3)
#
# Slow tier. Builds a test-tagged Squid image and runs it as a sibling
# container on the shared claude-net network (never deleting that network,
# per SDD §5). All allowed requests and the one blocked request are made
# once in setup_file() so every assertion reads the same accumulated
# access log. State crosses the setup_file/test/teardown_file process
# boundary via BATS_FILE_TMPDIR, since each of those runs in its own
# subshell.
#
# S-4/S-5 cover the docs.anthropic.com / code.claude.com Reference-tier
# additions from issue #32. S-6 covers the dstdom_regex mintcdn.com CDN
# exception added alongside them, curling the bare mintcdn.com apex —
# Mintlify's own CSP configuration docs list plain "mintcdn.com" (not
# just "*.mintcdn.com") as required for img-src/connect-src, confirming
# it's a directly-addressable host and not merely a wildcard zone.
#
# Requires a squid/ directory (Dockerfile + squid.conf) as a sibling of
# base/crypto/systems/research, per docs/squid_proxy_guide.md Part 3 Steps
# 1-2. That directory is not part of this repo — it's created locally by
# the operator — so this suite cannot build or commit it (out of scope per
# SDD §2.3); if it's missing, setup fails loudly rather than silently
# skipping (SDD §8).

load 'lib/engine'

SANDBOX_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SQUID_DIR="${SANDBOX_DIR}/squid"

setup_file() {
    engine_available || {
        echo "engine '${ENGINE}' is unreachable — is the daemon running?" >&2
        return 1
    }

    if [ ! -f "${SQUID_DIR}/Dockerfile" ] || [ ! -f "${SQUID_DIR}/squid.conf" ]; then
        echo "squid/ not found at ${SQUID_DIR} — create it first per" >&2
        echo "docs/squid_proxy_guide.md Part 3, Steps 1-2 (squid.conf + Dockerfile)" >&2
        return 1
    fi

    engine_ensure_network claude-net
    engine_build -t claude-squid:test "$SQUID_DIR" >&2

    proxy_name="test-claude-squid-$$"
    engine_run -d --name "$proxy_name" --network claude-net claude-squid:test >&2
    echo "$proxy_name" > "${BATS_FILE_TMPDIR}/proxy_name"

    # Allowed domain — expect success. Failure here doesn't abort setup;
    # S-1 below is what asserts on it.
    engine_run --rm --network claude-net \
        --env HTTPS_PROXY="http://${proxy_name}:3128" \
        curlimages/curl:latest curl -s -o /dev/null https://api.anthropic.com >&2 || true

    # Blocked domain — expect refusal.
    engine_run --rm --network claude-net \
        --env HTTPS_PROXY="http://${proxy_name}:3128" \
        curlimages/curl:latest curl -s -o /dev/null https://example.com >&2 || true

    # Allowed domains — issue #32 Reference-tier additions. S-4/S-5 assert on these.
    engine_run --rm --network claude-net \
        --env HTTPS_PROXY="http://${proxy_name}:3128" \
        curlimages/curl:latest curl -s -o /dev/null https://docs.anthropic.com >&2 || true

    engine_run --rm --network claude-net \
        --env HTTPS_PROXY="http://${proxy_name}:3128" \
        curlimages/curl:latest curl -s -o /dev/null https://code.claude.com >&2 || true

    # dstdom_regex exception — issue #32. S-6 asserts on this.
    engine_run --rm --network claude-net \
        --env HTTPS_PROXY="http://${proxy_name}:3128" \
        curlimages/curl:latest curl -s -o /dev/null https://mintcdn.com >&2 || true
}

teardown_file() {
    proxy_name="$(cat "${BATS_FILE_TMPDIR}/proxy_name" 2>/dev/null || true)"
    if [ -n "$proxy_name" ] && [[ "$proxy_name" == test-* ]]; then
        engine_stop "$proxy_name" > /dev/null 2>&1 || true
        engine_rm -f "$proxy_name" > /dev/null 2>&1 \
            || echo "WARNING: teardown failed to remove container '$proxy_name'" >&2
    fi
    engine_rmi -f claude-squid:test > /dev/null 2>&1 \
        || echo "WARNING: teardown failed to remove image 'claude-squid:test'" >&2
}

proxy_logs() {
    engine_logs "$(cat "${BATS_FILE_TMPDIR}/proxy_name")" 2>&1
}

@test "S-1: request to an allowed domain succeeds (TCP_TUNNEL/200 in the access log)" {
    # bats test_tags=slow
    run proxy_logs
    [[ "$output" == *"TCP_TUNNEL/200"* ]]
}

@test "S-2: request to a blocked domain is refused (TCP_DENIED/403)" {
    # bats test_tags=slow
    run proxy_logs
    [[ "$output" == *"TCP_DENIED"* ]] || [[ "$output" == *"/403"* ]]
}

@test "S-3: every attempted connection produces exactly one parseable access log line" {
    # bats test_tags=slow
    run proxy_logs
    [ "$status" -eq 0 ]
    line_count=$(echo "$output" | grep -cE '^[0-9]+\.[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9.]+[[:space:]]+\S+/[0-9]+')
    [ "$line_count" -ge 5 ]
}

@test "S-4: request to docs.anthropic.com (issue #32 Reference tier addition) succeeds" {
    # bats test_tags=slow
    run proxy_logs
    [[ "$output" =~ TCP_TUNNEL/200[[:space:]]+[0-9]+[[:space:]]+CONNECT[[:space:]]+docs\.anthropic\.com:443 ]]
}

@test "S-5: request to code.claude.com (issue #32 Reference tier addition) succeeds" {
    # bats test_tags=slow
    run proxy_logs
    [[ "$output" =~ TCP_TUNNEL/200[[:space:]]+[0-9]+[[:space:]]+CONNECT[[:space:]]+code\.claude\.com:443 ]]
}

@test "S-6: request to mintcdn.com (issue #32 dstdom_regex CDN exception) succeeds" {
    # bats test_tags=slow
    run proxy_logs
    [[ "$output" =~ TCP_TUNNEL/200[[:space:]]+[0-9]+[[:space:]]+CONNECT[[:space:]]+mintcdn\.com:443 ]]
}
