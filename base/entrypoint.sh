#!/usr/bin/env bash
# entrypoint.sh — Global layer injection for claude-sandbox containers.
#
# Runs as claude-agent (non-root) at container startup.
# Merges the base global layer and any per-image overlay into ~/.claude/
# before handing control to the CMD (claude).
#
# Mount points (both readonly):
#   /run/claude-global   — base global layer (always present if start.sh passes it)
#   /run/claude-overlay  — per-image overlay (present only when an overlay dir exists)
#
# The copy-on-start pattern gives Claude Code a writable ~/.claude/ without
# exposing the host source directories to writes.

set -euo pipefail

GLOBAL_SRC="/run/claude-global"
OVERLAY_SRC="/run/claude-overlay"
DEST="${HOME}/.claude"

echo "[entrypoint] Starting global layer injection"

mkdir -p "$DEST"

if [ -d "$GLOBAL_SRC" ] && [ "$(ls -A "$GLOBAL_SRC" 2>/dev/null)" ]; then
    cp -r "$GLOBAL_SRC/." "$DEST/"
    echo "[entrypoint] Base global layer applied from $GLOBAL_SRC"
else
    echo "[entrypoint] WARNING: $GLOBAL_SRC is absent or empty — no base layer applied"
fi

if [ -d "$OVERLAY_SRC" ] && [ "$(ls -A "$OVERLAY_SRC" 2>/dev/null)" ]; then
    cp -r "$OVERLAY_SRC/." "$DEST/"
    echo "[entrypoint] Overlay layer applied from $OVERLAY_SRC"
else
    echo "[entrypoint] No overlay present at $OVERLAY_SRC — skipping"
fi

echo "[entrypoint] ~/.claude contents:"
find "$DEST" -type f | sort | sed "s|^|[entrypoint]   |"

echo "[entrypoint] Injection complete. Starting: $*"

echo "[entrypoint] Checking /workspace for interpreter-path mismatches"

check_venv_interpreter() {
    local venv_python="$1"
    if "$venv_python" -c "" 2>/dev/null; then
        echo "[entrypoint] OK: $venv_python"
    else
        echo "[entrypoint] WARNING: broken interpreter reference detected"
        echo "[entrypoint]   $venv_python -> $(readlink -f "$venv_python" 2>/dev/null || echo unresolvable)"
        echo "[entrypoint]   Likely cause: venv built against a Strategy B (ephemeral)"
        echo "[entrypoint]   interpreter that was never promoted to the Dockerfile."
        echo "[entrypoint]   Fix: rm -rf $(dirname "$(dirname "$venv_python")") && rebuild the venv"
    fi
}

while IFS= read -r -d '' venv_dir; do
    # Use nullglob locally so an empty match produces no iterations rather than
    # passing the literal glob string to check_venv_interpreter.
    ( shopt -s nullglob; for py in "$venv_dir"/bin/python3*; do
        check_venv_interpreter "$py"
    done )
done < <(find /workspace -maxdepth 3 -type d -name '.venv' -print0 2>/dev/null)

echo "[entrypoint] Interpreter check complete"

echo "[entrypoint] Checking /workspace for stale CMake build directories"

while IFS= read -r -d '' cache; do
    while IFS= read -r entry; do
        path="${entry#*=}"
        if [ -n "$path" ] && [ ! -x "$path" ]; then
            echo "[entrypoint] WARNING: stale CMake toolchain path detected"
            echo "[entrypoint]   Cache:  $cache"
            echo "[entrypoint]   Entry:  $entry"
            echo "[entrypoint]   Missing or non-executable: $path"
            echo "[entrypoint]   Likely cause: compiler installed ephemerally (Strategy B)"
            echo "[entrypoint]   and not promoted to the Dockerfile before this path was"
            echo "[entrypoint]   captured at cmake configure time."
            echo "[entrypoint]   Fix: rm -rf $(dirname "$cache") && re-run cmake"
        else
            echo "[entrypoint] OK: CMake toolchain path $path"
        fi
    done < <(grep -E "^CMAKE_(C|CXX)_COMPILER:FILEPATH=" "$cache" 2>/dev/null)
done < <(find /workspace -maxdepth 4 -name "CMakeCache.txt" -print0 2>/dev/null)

echo "[entrypoint] CMake check complete"

echo "[entrypoint] Checking /workspace for Node.js native addons"

ADDON_COUNT=0
while IFS= read -r -d '' addon; do
    ADDON_COUNT=$((ADDON_COUNT + 1))
    echo "[entrypoint] WARNING: native Node.js addon present"
    echo "[entrypoint]   $addon"
    echo "[entrypoint]   Native addons are ABI-version-dependent. If the Node.js version"
    echo "[entrypoint]   in this image differs from the one used to compile this addon,"
    echo "[entrypoint]   it will fail to load at runtime with a NODE_MODULE_VERSION error."
    echo "[entrypoint]   Fix: rm -rf $(dirname "$(dirname "$addon")") && npm install"
done < <(find /workspace -maxdepth 5 -path "*/node_modules/*.node" -print0 2>/dev/null)

if [ "$ADDON_COUNT" -eq 0 ]; then
    echo "[entrypoint] OK: no native Node.js addons found"
fi

echo "[entrypoint] Node.js addon check complete"

echo "[entrypoint] Checking /workspace for commit-msg hook"

HOOK_SRC="${HOME}/.claude/hooks/commit-msg"

# Resolve the hooks directory git will actually use, rather than assuming
# /workspace/.git/hooks. That literal missed two shapes, both silently:
#
#   - core.hooksPath redirects hooks elsewhere, so the file inspected here
#     is not the file git runs — the check reports on the wrong artifact
#     while looking healthy.
#   - In a linked worktree or a submodule, .git is a FILE holding a
#     "gitdir:" pointer, not a directory. A [ -d ] test therefore concluded
#     "not a repository" and skipped the entire check, telling the operator
#     there was no git repo while they stood in one.
#
# rev-parse --git-path resolves all three shapes. It returns a relative path
# in the default case and an absolute one when redirected, so it has to be
# resolved against /workspace rather than used raw.
HOOK_DIR="$(cd /workspace 2>/dev/null && git rev-parse --git-path hooks 2>/dev/null)" || HOOK_DIR=""
case "$HOOK_DIR" in
    "") ;;
    /*) ;;
    *)  HOOK_DIR="/workspace/${HOOK_DIR}" ;;
esac
HOOK_PATH="${HOOK_DIR}/commit-msg"

# Installing only when absent meant a hook change reached repositories that
# had never had one and nowhere else. Every project already using it kept
# whatever version it was given, with no signal that a later fix existed —
# rung 2 for a mechanism that is otherwise rung 5.
#
# This compares contents rather than a version marker: there is nothing to
# remember to bump, and a marker that was not bumped is indistinguishable
# from a hook that is current. It deliberately does not judge what the
# difference means. A drifted hook may be stale or may be a local
# customisation, and telling those apart requires running it, which is what
# the commit-hook-setup skill's probes do.
if [ -z "$HOOK_DIR" ]; then
    echo "[entrypoint] /workspace is not a git repository — commit-msg hook installation skipped"
elif [ ! -f "$HOOK_SRC" ]; then
    echo "[entrypoint] WARNING: no commit-msg hook in the global layer"
    echo "[entrypoint]   expected at $HOOK_SRC"
    echo "[entrypoint]   Nothing to install or compare against; commits are unchecked."
elif [ ! -f "$HOOK_PATH" ]; then
    mkdir -p "$HOOK_DIR"
    cp "$HOOK_SRC" "$HOOK_PATH"
    chmod +x "$HOOK_PATH"
    echo "[entrypoint] commit-msg hook installed at $HOOK_PATH"
elif cmp -s "$HOOK_PATH" "$HOOK_SRC"; then
    echo "[entrypoint] OK: commit-msg hook matches the shipped version"
    [ "$HOOK_DIR" = "/workspace/.git/hooks" ] \
        || echo "[entrypoint]   (hooks directory is $HOOK_DIR, not the default)"
else
    echo "[entrypoint] WARNING: installed commit-msg hook differs from the shipped one"
    echo "[entrypoint]   $HOOK_PATH"
    echo "[entrypoint]   It may predate a fix, or be a deliberate local customisation."
    echo "[entrypoint]   Reading it will not tell you which — only running it will."
    echo "[entrypoint]   Fix: invoke the commit-hook-setup skill to probe what it enforces"
fi

echo "[entrypoint] Commit-msg hook check complete"

exec "$@"
