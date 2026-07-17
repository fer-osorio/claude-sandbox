# lib/engine.bash — $ENGINE abstraction for the claude-sandbox test harness.
#
# Test bodies call these functions instead of invoking docker/podman
# literally, so `ENGINE=podman bats tests/` validates the Podman migration
# without rewriting test logic (design rationale: SDD §3.4).

ENGINE="${ENGINE:-docker}"

engine_run()      { "${ENGINE}" run "$@"; }
engine_build()    { "${ENGINE}" build "$@"; }
engine_ps()       { "${ENGINE}" ps "$@"; }
engine_exec()     { "${ENGINE}" exec "$@"; }
engine_inspect()  { "${ENGINE}" inspect "$@"; }
engine_rm()       { "${ENGINE}" rm "$@"; }
engine_rmi()      { "${ENGINE}" rmi "$@"; }
engine_stop()     { "${ENGINE}" stop "$@"; }
engine_logs()     { "${ENGINE}" logs "$@"; }
engine_images()   { "${ENGINE}" images "$@"; }
engine_network()  { "${ENGINE}" network "$@"; }

# Fails loudly (per SDD §8) if the engine daemon is unreachable, instead of
# letting individual tests fail with a confusing low-level error each.
engine_available() {
    "${ENGINE}" info > /dev/null 2>&1
}

# Creates claude-net if absent, reuses it otherwise. Never deletes it —
# it is shared with real developer sessions (SDD §5).
engine_ensure_network() {
    local name="${1:-claude-net}"
    if ! "${ENGINE}" network inspect "$name" > /dev/null 2>&1; then
        "${ENGINE}" network create --driver bridge "$name" > /dev/null
    fi
}
