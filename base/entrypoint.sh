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

HOOK_DIR="/workspace/.git/hooks"
HOOK_PATH="${HOOK_DIR}/commit-msg"

if [ ! -d "/workspace/.git" ]; then
    echo "[entrypoint] No .git directory found — commit-msg hook installation skipped"
elif [ -f "$HOOK_PATH" ]; then
    echo "[entrypoint] commit-msg hook already present at $HOOK_PATH — skipping"
    echo "[entrypoint] Invoke the commit-hook-setup skill to inspect or update it"
else
    mkdir -p "$HOOK_DIR"
    cp "${HOME}/.claude/hooks/commit-msg" "$HOOK_PATH"
    chmod +x "$HOOK_PATH"
    echo "[entrypoint] commit-msg hook installed at $HOOK_PATH"
fi

echo "[entrypoint] Commit-msg hook check complete"

exec "$@"
