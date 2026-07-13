# lib/teardown.bash — trap-based cleanup helpers for the test harness.
#
# bats-core invokes a function literally named `teardown()` after every
# test in a file; each test file's own `teardown()` should call
# `teardown_registered` so cleanup runs even when a test fails or is
# interrupted. Scoped strictly to the "test-" container name prefix and
# ":test" image tag (SDD §5) — this refuses to touch anything else,
# including the shared claude-net network, so a stuck test can never take
# out a real developer session.

TEARDOWN_CONTAINERS=()
TEARDOWN_IMAGES=()

register_container() { TEARDOWN_CONTAINERS+=("$1"); }
register_image()     { TEARDOWN_IMAGES+=("$1"); }

teardown_registered() {
    local name

    for name in "${TEARDOWN_CONTAINERS[@]:-}"; do
        [ -z "$name" ] && continue
        if [[ "$name" != test-* ]]; then
            echo "WARNING: refusing to tear down non-test container '$name'" >&2
            continue
        fi
        engine_stop "$name" > /dev/null 2>&1 || true
        engine_rm -f "$name" > /dev/null 2>&1 \
            || echo "WARNING: teardown failed to remove container '$name'" >&2
    done

    for name in "${TEARDOWN_IMAGES[@]:-}"; do
        [ -z "$name" ] && continue
        if [[ "$name" != *:test ]]; then
            echo "WARNING: refusing to remove non-test-tagged image '$name'" >&2
            continue
        fi
        engine_rmi -f "$name" > /dev/null 2>&1 \
            || echo "WARNING: teardown failed to remove image '$name'" >&2
    done

    TEARDOWN_CONTAINERS=()
    TEARDOWN_IMAGES=()
}
