#!/usr/bin/env bash
# build.sh — Build the claude-sandbox image hierarchy.
#
# Usage:
#   ./build.sh            — build all images
#   ./build.sh base       — build only claude-base
#   ./build.sh crypto     — build claude-base then claude-crypto
#   ./build.sh systems    — build claude-base then claude-systems
#   ./build.sh research   — build claude-base then claude-research
#
# The base image must always be built before any child image. This script
# enforces that: building a child always rebuilds base first (it will be a
# no-op if nothing has changed, thanks to Docker layer caching).
#
# Place this file in the same directory as base/, crypto/, systems/, research/.

set -euo pipefail

UID_ARG="--build-arg HOST_UID=$(id -u)"
TARGET="${1:-all}"

build_base() {
    echo "→ Building claude-base..."
    docker build $UID_ARG -t claude-base ./base/
}

build_crypto() {
    echo "→ Building claude-crypto..."
    docker build $UID_ARG -t claude-crypto ./crypto/
}

build_systems() {
    echo "→ Building claude-systems..."
    docker build $UID_ARG -t claude-systems ./systems/
}

build_research() {
    echo "→ Building claude-research..."
    docker build $UID_ARG -t claude-research ./research/
}

case "$TARGET" in
    all)
        build_base
        build_crypto
        build_systems
        build_research
        echo ""
        echo "All images built:"
        docker images | grep -E "^claude-(base|crypto|systems|research)\s"
        ;;
    base)
        build_base
        ;;
    crypto)
        build_base
        build_crypto
        ;;
    systems)
        build_base
        build_systems
        ;;
    research)
        build_base
        build_research
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: $0 [all|base|crypto|systems|research]"
        exit 1
        ;;
esac
