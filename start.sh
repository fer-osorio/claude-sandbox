#!/usr/bin/env bash
# Usage: start.sh <project_directory> [image]
#
# Arguments:
#   project_directory  — path to the project to mount (default: current dir)
#   image              — which sandbox image to use (default: base)
#                        one of: base, crypto, systems, research
#
# Global layer directories (relative to this script's location):
#   global-claude/        — base layer, injected into every session
#   global-<image>/       — per-image overlay, injected when present
#
# Examples:
#   ./start.sh ~/projects/mylib crypto      — HSM / cryptography work
#   ./start.sh ~/projects/myapp systems     — C++ / CMake projects
#   ./start.sh ~/projects/paper research    — LaTeX documents
#   ./start.sh ~/projects/webapp            — web / Python (uses base)
#
# Before running this for the first time, ensure the network exists:
#   docker network create --driver bridge claude-net
#   (or: podman network create --driver bridge claude-net, under ENGINE=podman)
#
# Engine:
#   ENGINE=docker (default) or ENGINE=podman selects which container engine
#   binary is invoked. See docs/designs/podman-migration.md.

set -euo pipefail

ENGINE="${ENGINE:-docker}"

SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"
IMAGE_TAG="${2:-base}"

VALID_IMAGES="base crypto systems research"

if ! "$ENGINE" info > /dev/null 2>&1; then
    echo "Error: $ENGINE is not reachable."
    echo "Start $ENGINE and try again."
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: '$PROJECT_DIR' is not a directory."
    exit 1
fi

if ! echo "$VALID_IMAGES" | grep -qw "$IMAGE_TAG"; then
    echo "Error: unknown image '$IMAGE_TAG'."
    echo "Valid options: $VALID_IMAGES"
    exit 1
fi

IMAGE_NAME="claude-${IMAGE_TAG}"

if ! "$ENGINE" image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    echo "Error: image '$IMAGE_NAME' does not exist."
    echo "Build it first with: ENGINE=$ENGINE ./build.sh $IMAGE_TAG"
    exit 1
fi

if ! "$ENGINE" network inspect claude-net > /dev/null 2>&1; then
    echo "Error: network 'claude-net' does not exist."
    echo "Create it with: $ENGINE network create --driver bridge claude-net"
    exit 1
fi

if ! "$ENGINE" image inspect claude-squid > /dev/null 2>&1; then
    echo "Error: image 'claude-squid' does not exist."
    echo "Build it first with: ENGINE=$ENGINE ./build.sh squid"
    exit 1
fi

GLOBAL_BASE="${SANDBOX_DIR}/global-claude"
GLOBAL_OVERLAY="${SANDBOX_DIR}/global-${IMAGE_TAG}"

echo "Project:  $PROJECT_DIR"
echo "Image:    $IMAGE_NAME"
echo "Network:  claude-net via claude-squid proxy (see squid/squid.conf for allowlist)"

if [ -d "$GLOBAL_BASE" ]; then
    echo "Global:   $GLOBAL_BASE"
else
    echo "Global:   WARNING — $GLOBAL_BASE not found; session will have no global layer"
fi

if [ -d "$GLOBAL_OVERLAY" ] && [ "$IMAGE_TAG" != "base" ]; then
    echo "Overlay:  $GLOBAL_OVERLAY"
else
    echo "Overlay:  none for image '$IMAGE_TAG'"
fi

echo ""

MOUNT_ARGS=(
    "--mount" "type=bind,source=${PROJECT_DIR},target=/workspace"
)

ENV_ARGS=()
if [ -n "${GH_TOKEN:-}" ]; then
    ENV_ARGS+=("-e" "GH_TOKEN")
fi

if [ -d "$GLOBAL_BASE" ]; then
    MOUNT_ARGS+=(
        "--mount" "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly"
    )
fi

if [ -d "$GLOBAL_OVERLAY" ] && [ "$IMAGE_TAG" != "base" ]; then
    MOUNT_ARGS+=(
        "--mount" "type=bind,source=${GLOBAL_OVERLAY},target=/run/claude-overlay,readonly"
    )
fi

PROXY_NAME="claude-proxy-$$"

# Guaranteed teardown regardless of how the script exits (normal completion,
# main-container failure, or Ctrl+C) — a plain "stop after" line only runs
# on the clean-exit path and would leak the proxy container otherwise.
cleanup() {
    local exit_code=$?
    if "$ENGINE" ps -a --format '{{.Names}}' | grep -qx "$PROXY_NAME"; then
        "$ENGINE" stop "$PROXY_NAME" > /dev/null 2>&1 || true
        "$ENGINE" rm "$PROXY_NAME" > /dev/null 2>&1 || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT

# --userns=keep-id remaps the main container's baked UID 1000 (claude-agent)
# onto whatever UID is actually invoking $ENGINE, at run time — only needed
# (and only supported) under Podman. The Docker path keeps matching the host
# UID at build time via HOST_UID (see build.sh). The proxy container has no
# bind mounts, so it never needs this. See docs/designs/podman-migration.md §3.A.
USERNS_ARGS=()
if [ "$ENGINE" = "podman" ]; then
    USERNS_ARGS=(--userns=keep-id:uid=1000,gid=1000)
fi

# Explicit, size-capped log drivers on both containers, pinned to the same
# driver regardless of engine rather than relying on differing defaults
# (Podman's default varies by configuration). Closes the proxy hygiene gap
# noted in squid-proxy-integration.md §6.2-R and the main-container gap noted
# in claude_code_security_plan.md Phase 5. See podman-migration.md §3.B.
PROXY_LOG_ARGS=(--log-driver json-file --log-opt max-size=10m --log-opt max-file=3)
MAIN_LOG_ARGS=(--log-driver json-file --log-opt max-size=50m --log-opt max-file=5)

echo "Starting Squid proxy ($PROXY_NAME)..."
if ! "$ENGINE" run -d \
    --name "$PROXY_NAME" \
    --network claude-net \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    "${PROXY_LOG_ARGS[@]}" \
    claude-squid > /dev/null; then
    echo "Error: Squid proxy failed to start."
    echo "Fail-closed per docs/designs/squid-proxy-integration.md §6.3 — aborting session."
    exit 1
fi

"$ENGINE" run \
    --rm \
    -it \
    --name "claude-$(basename "$PROJECT_DIR")-$(date +%s)" \
    "${MOUNT_ARGS[@]}" \
    "${ENV_ARGS[@]}" \
    --network claude-net \
    --env HTTP_PROXY="http://$PROXY_NAME:3128" \
    --env HTTPS_PROXY="http://$PROXY_NAME:3128" \
    --env NO_PROXY="localhost,127.0.0.1" \
    --memory="2g" \
    --cpus="2" \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    "${USERNS_ARGS[@]}" \
    "${MAIN_LOG_ARGS[@]}" \
    "$IMAGE_NAME"
