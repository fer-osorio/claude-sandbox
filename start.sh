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

set -euo pipefail

SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"
IMAGE_TAG="${2:-base}"

VALID_IMAGES="base crypto systems research"

if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker daemon is not running."
    echo "Start Docker and try again."
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

if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    echo "Error: image '$IMAGE_NAME' does not exist."
    echo "Build it first with: ./build.sh $IMAGE_TAG"
    exit 1
fi

if ! docker network inspect claude-net > /dev/null 2>&1; then
    echo "Error: network 'claude-net' does not exist."
    echo "Create it with: docker network create --driver bridge claude-net"
    exit 1
fi

GLOBAL_BASE="${SANDBOX_DIR}/global-claude"
GLOBAL_OVERLAY="${SANDBOX_DIR}/global-${IMAGE_TAG}"

echo "Project:  $PROJECT_DIR"
echo "Image:    $IMAGE_NAME"
echo "Network:  claude-net (Anthropic API + package registries only)"

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

docker run \
    --rm \
    -it \
    --name "claude-$(basename "$PROJECT_DIR")-$(date +%s)" \
    "${MOUNT_ARGS[@]}" \
    --network claude-net \
    --memory="2g" \
    --cpus="2" \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    "$IMAGE_NAME"
