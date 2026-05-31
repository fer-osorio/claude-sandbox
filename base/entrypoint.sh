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
exec "$@"
