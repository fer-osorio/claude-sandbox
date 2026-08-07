#!/usr/bin/env bash
# build.sh — Build the claude-sandbox image hierarchy.
#
# Usage:
#   ./build.sh                  — build all images
#   ./build.sh base             — build only claude-base
#   ./build.sh crypto           — build claude-base then claude-crypto
#   ./build.sh systems          — build claude-base then claude-systems
#   ./build.sh research         — build claude-base then claude-research
#   ./build.sh squid            — build only claude-squid (no base dependency)
#   ./build.sh --no-cache       — build all images, bypassing Docker layer cache
#   ./build.sh base --no-cache  — build only claude-base, bypassing cache
#
# The base image must always be built before any child image. This script
# enforces that: building a child always rebuilds base first (it will be a
# no-op if nothing has changed, thanks to Docker layer caching).
#
# Place this file in the same directory as base/, crypto/, systems/, research/.
#
# Engine:
#   ENGINE=docker (default) or ENGINE=podman selects which container engine
#   binary is invoked. See docs/designs/podman-migration.md. HOST_UID is only
#   passed as a build-arg under Docker — the Podman path relies on the
#   Dockerfiles' baked default (1000) plus --userns=keep-id at run time
#   instead (see start.sh).

set -euo pipefail

ENGINE="${ENGINE:-docker}"

UID_ARG=""
if [ "$ENGINE" = "docker" ]; then
    UID_ARG="--build-arg HOST_UID=$(id -u)"
fi
NO_CACHE=""
TARGET="all"

for arg in "$@"; do
  case "$arg" in
    --no-cache) NO_CACHE="--no-cache" ;;
    *) TARGET="$arg" ;;
  esac
done

build_base() {
    echo "→ Building claude-base..."
    "$ENGINE" build $UID_ARG $NO_CACHE -t claude-base ./base/
}

build_crypto() {
    echo "→ Building claude-crypto..."
    "$ENGINE" build $UID_ARG $NO_CACHE -t claude-crypto ./crypto/
}

build_systems() {
    echo "→ Building claude-systems..."
    "$ENGINE" build $UID_ARG $NO_CACHE -t claude-systems ./systems/
}

build_research() {
    echo "→ Building claude-research..."
    "$ENGINE" build $UID_ARG $NO_CACHE -t claude-research ./research/
}

# No $UID_ARG — the Squid image creates no claude-agent-equivalent user tied
# to the host UID; it has no bind-mounted /workspace and nothing that needs
# host-UID alignment.
build_squid() {
    echo "→ Building claude-squid..."
    "$ENGINE" build $NO_CACHE -t claude-squid ./squid/
}

case "$TARGET" in
    all)
        build_base
        build_crypto
        build_systems
        build_research
        build_squid
        echo ""
        echo "All images built:"
        "$ENGINE" images | grep -E "^claude-(base|crypto|systems|research|squid)\s"
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
    squid)
        build_squid
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: $0 [all|base|crypto|systems|research|squid]"
        exit 1
        ;;
esac
