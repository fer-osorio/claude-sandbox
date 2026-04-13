#!/usr/bin/env bash
# Usage: start.sh <project_directory> [image]
#
# Arguments:
#   project_directory  — path to the project to mount (default: current dir)
#   image              — which sandbox image to use (default: base)
#                        one of: base, crypto, systems, research
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

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"
IMAGE_TAG="${2:-base}"

VALID_IMAGES="base crypto systems research"

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

echo "Project:  $PROJECT_DIR"
echo "Image:    $IMAGE_NAME"
echo "Network:  claude-net (Anthropic API + package registries only)"
echo ""

docker run \
    --rm \
    -it \
    --name "claude-$(basename "$PROJECT_DIR")-$(date +%s)" \
    --mount type=bind,source="$PROJECT_DIR",target=/workspace \
    --network claude-net \
    --memory="2g" \
    --cpus="2" \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    "$IMAGE_NAME"
