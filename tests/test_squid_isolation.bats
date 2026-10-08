#!/usr/bin/env bats
# test_squid_isolation.bats — Group 3: Squid Egress Enforcement (SDD §4.3)
#
# Slow tier. Builds a test-tagged Squid image and runs it as a sibling
# container on the shared claude-net network (never deleting that network,
# per SDD §5). All allowed requests and the one blocked request are made
# in setup_file() so every assertion reads the same accumulated access
# log. State crosses the setup_file/test/teardown_file process boundary
# via BATS_FILE_TMPDIR, since each of those runs in its own subshell.
#
# Requests are retried until the log carries a terminal status for the
# host — see proxy_request() and issue #160.
#
# What is verified, stated precisely because the retry does not fire on the
# operator's host at all (0 of 64 requests failed over 8 runs, recorded on
# #160): proxy_request's control flow was exercised against a stubbed
# engine — terminal on attempt 1 (0 retries), terminal on attempt 3 (2
# retries), and never terminal (returns non-zero after exactly
# _S_MAX_ATTEMPTS requests) — along with _s_terminal's treatment of
# NONE_NONE/500, an unknown status and a host with no line as non-terminal.
#
# What is not verified: any of it against a real proxy under the failure
# this exists to absorb. That needs a hosted runner, and it is the
# container tier's step 7 (#101). Until then the attempt bound of three is
# a guess with no sample behind it, which is why it is overridable and why
# the retry count is reported.
#
# S-4/S-5 cover the docs.anthropic.com / code.claude.com Reference-tier
# additions from issue #32. S-6 covers the dstdom_regex mintcdn.com CDN
# exception added alongside them, curling the bare mintcdn.com apex —
# Mintlify's own CSP configuration docs list plain "mintcdn.com" (not
# just "*.mintcdn.com") as required for img-src/connect-src, confirming
# it's a directly-addressable host and not merely a wildcard zone.
#
# S-7/S-8/S-9 cover the planning-research tier from issue #91 —
# arxiv.org, datatracker.ietf.org and www.rfc-editor.org, the
# primary/technical sources swe-prior-art-research retrieves from. They
# assert reachability only. Nothing here asserts that the deliberately
# excluded UGC and paywalled domains stay excluded; S-2 covers that
# generically via the default-deny policy, so a future entry added to
# squid.conf by mistake would not fail this suite.
#
# Requires a squid/ directory (Dockerfile + squid.conf) as a sibling of
# base/crypto/systems/research. That directory is committed: it landed in
# 9269ddb, the commit Change 15 of docs/claude-code-security-plan.md
# records as closing the gap where Layer 4 of the five-layer defense was
# documentation only. So this suite builds claude-squid:test from the
# tracked config — the same file a real session's proxy runs on, which is
# what makes S-1..S-9 assertions about the shipped policy rather than
# about a local copy of it.
#
# The existence check in setup_file() stays, and its job is narrower than
# it looks: if squid/ is missing or incomplete, setup fails loudly instead
# of letting the whole group skip and report green. SDD §8 step 6 records
# the transition — before squid/ was committed, failing at setup_file()
# was the designed behaviour rather than a defect.
#
# The curl helper image is pinned to docker.io/curlimages/curl:latest,
# fully qualified — an unqualified curlimages/curl:latest depends on
# the operator's podman unqualified-search-registries order and can
# silently resolve to a registry that doesn't carry the image (e.g.
# registry.fedoraproject.org), failing every request in setup_file()
# before any of them reach the proxy at all.

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
        echo "docs/squid-proxy-guide.md Part 3, Steps 1-2 (squid.conf + Dockerfile)" >&2
        return 1
    fi

    engine_ensure_network claude-net
    engine_build -t claude-squid:test "$SQUID_DIR" >&2

    proxy_name="test-claude-squid-$$"
    engine_run -d --name "$proxy_name" --network claude-net claude-squid:test >&2
    echo "$proxy_name" > "${BATS_FILE_TMPDIR}/proxy_name"

    # Issued in a fixed order, which is also the order the assertions read
    # them in: api.anthropic.com (S-1), the deliberately blocked example.com
    # (S-2), issue #32's Reference-tier additions and dstdom_regex exception
    # (S-4/S-5/S-6), then issue #91's planning-research tier (S-7/S-8/S-9).
    #
    # Every host is attempted even after an earlier one fails, so the
    # diagnostic below can name all of them instead of only the first.
    local unanswered=""
    for host in api.anthropic.com example.com docs.anthropic.com \
                code.claude.com mintcdn.com arxiv.org \
                datatracker.ietf.org www.rfc-editor.org; do
        proxy_request "$host" || unanswered="${unanswered} ${host}"
    done

    if [ -n "$unanswered" ]; then
        # Loud, and specific about which of two very different things went
        # wrong. The proxy never reaching a decision is the harness failing
        # to obtain an answer; the policy refusing a host would appear as
        # TCP_DENIED/403, which is a terminal status and would have ended
        # the retry loop. Conflating those is what made the #101 spike's
        # first run undiagnosable.
        echo "setup: no terminal access-log status after ${_S_MAX_ATTEMPTS}" >&2
        echo "attempts each for:${unanswered}" >&2
        echo "This is the harness failing to get an answer from the proxy," >&2
        echo "not the policy refusing a host. See #160. Access log follows." >&2
        proxy_logs >&2
        return 1
    fi

    # Reported even when zero: a retry count that only appears on failure
    # cannot distinguish a dormant retry path from a load-bearing one.
    echo "setup: ${_s_retries} retry attempt(s) consumed" >&2
    if [ -n "${SQUID_RETRY_REPORT:-}" ]; then
        echo "$_s_retries" > "$SQUID_RETRY_REPORT"
    fi
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

# Issue #160. Overridable so the attempt bound can be raised in CI without a
# code edit: there are zero samples of a retry succeeding, so three is a
# starting guess, not a measurement, and the reported count is what will say
# whether it sufficed.
_S_MAX_ATTEMPTS="${SQUID_MAX_ATTEMPTS:-3}"
# Seconds to wait for a log line that may still be in flight before calling an
# attempt failed. Squid flushes per request — buffered_logs defaults to off and
# squid.conf:110 logs to stdio:/dev/stdout — but the engine's own log pipeline
# adds latency on top of that. Without this wait the retry would sometimes be
# counting lines that had simply not arrived yet, which would inflate exactly
# the number this change exists to report.
_S_LOG_SETTLE=3
_s_retries=0

# Terminal means the policy answered: TCP_TUNNEL/200 for an allowed host,
# TCP_DENIED/403 for a refused one. Anything else — NONE_NONE/500, or no line
# for the host at all — is Squid never having reached a decision.
#
# Written as an allowlist of the two terminal statuses rather than as "not
# NONE_NONE" so that an unseen status causes a retry instead of being mistaken
# for an answer. The cost of being wrong in that direction is a slower setup;
# in the other direction it is an assertion read off a log line that records
# no decision.
_s_terminal() {
    local host_re="${1//./\\.}"
    proxy_logs | grep -qE \
        "(TCP_TUNNEL/200|TCP_DENIED/403)[[:space:]]+[0-9]+[[:space:]]+CONNECT[[:space:]]+${host_re}:443"
}

# The same predicate, allowing a line _S_LOG_SETTLE seconds to show up. On a
# healthy host the first check succeeds and nothing sleeps, so this is free
# where it does not apply.
_s_terminal_settled() {
    local waited=0
    while :; do
        _s_terminal "$1" && return 0
        [ "$waited" -ge "$_S_LOG_SETTLE" ] && return 1
        sleep 1
        waited=$((waited + 1))
    done
}

# Issue the CONNECT and retry until the access log carries a terminal status
# for the host. A request that needed three attempts is still a request the
# policy allowed; an assertion about the policy should not turn on whether the
# first attempt resolved.
#
# Failed attempts leave their own NONE_NONE/500 lines in the accumulated log.
# That is deliberate — the log stays a complete record of what was attempted,
# and S-3's line count is a floor, so extra lines do not break it.
proxy_request() {
    local host="$1" attempt=1
    while :; do
        engine_run --rm --network claude-net \
            --env HTTPS_PROXY="http://${proxy_name}:3128" \
            docker.io/curlimages/curl:latest \
            curl -s -o /dev/null "https://${host}" >&2 || true

        _s_terminal_settled "$host" && return 0
        [ "$attempt" -ge "$_S_MAX_ATTEMPTS" ] && return 1

        attempt=$((attempt + 1))
        _s_retries=$((_s_retries + 1))
        sleep "$attempt"
    done
}

# bats test_tags=slow
@test "S-1: request to an allowed domain succeeds (TCP_TUNNEL/200 in the access log)" {
    run proxy_logs
    [[ "$output" == *"TCP_TUNNEL/200"* ]]
}

# bats test_tags=slow
@test "S-2: request to a blocked domain is refused (TCP_DENIED/403)" {
    run proxy_logs
    [[ "$output" == *"TCP_DENIED"* ]] || [[ "$output" == *"/403"* ]]
}

# bats test_tags=slow
@test "S-3: every attempted connection produces exactly one parseable access log line" {
    run proxy_logs
    [ "$status" -eq 0 ]
    line_count=$(echo "$output" | grep -cE '^[0-9]+\.[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9.]+[[:space:]]+\S+/[0-9]+')
    # One line per request issued in setup_file: 5 from issue #32's era plus
    # the 3 planning-research hosts from issue #91. The bound is set at the
    # number of requests, not below it — a floor below the real count stops
    # detecting a request that silently produced no log line at all, which is
    # the failure this test exists to catch.
    #
    # It is a floor rather than an equality because a retried request (#160)
    # leaves the failed attempt's NONE_NONE/500 line in the log as well. Those
    # extra lines are a record of what was attempted; what must never happen
    # is fewer than one line per host.
    [ "$line_count" -ge 8 ]
}

# bats test_tags=slow
@test "S-4: request to docs.anthropic.com (issue #32 Reference tier addition) succeeds" {
    run proxy_logs
    [[ "$output" =~ TCP_TUNNEL/200[[:space:]]+[0-9]+[[:space:]]+CONNECT[[:space:]]+docs\.anthropic\.com:443 ]]
}

# bats test_tags=slow
@test "S-5: request to code.claude.com (issue #32 Reference tier addition) succeeds" {
    run proxy_logs
    [[ "$output" =~ TCP_TUNNEL/200[[:space:]]+[0-9]+[[:space:]]+CONNECT[[:space:]]+code\.claude\.com:443 ]]
}

# bats test_tags=slow
@test "S-6: request to mintcdn.com (issue #32 dstdom_regex CDN exception) succeeds" {
    run proxy_logs
    [[ "$output" =~ TCP_TUNNEL/200[[:space:]]+[0-9]+[[:space:]]+CONNECT[[:space:]]+mintcdn\.com:443 ]]
}

# bats test_tags=slow
@test "S-7: request to arxiv.org (issue #91 planning-research tier) succeeds" {
    run proxy_logs
    [[ "$output" =~ TCP_TUNNEL/200[[:space:]]+[0-9]+[[:space:]]+CONNECT[[:space:]]+arxiv\.org:443 ]]
}

# bats test_tags=slow
@test "S-8: request to datatracker.ietf.org (issue #91 planning-research tier) succeeds" {
    run proxy_logs
    [[ "$output" =~ TCP_TUNNEL/200[[:space:]]+[0-9]+[[:space:]]+CONNECT[[:space:]]+datatracker\.ietf\.org:443 ]]
}

# bats test_tags=slow
@test "S-9: request to www.rfc-editor.org (issue #91 planning-research tier) succeeds" {
    run proxy_logs
    [[ "$output" =~ TCP_TUNNEL/200[[:space:]]+[0-9]+[[:space:]]+CONNECT[[:space:]]+www\.rfc-editor\.org:443 ]]
}
