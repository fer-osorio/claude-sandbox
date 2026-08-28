#!/usr/bin/env bash
# check-auto-memory.sh — step-zero diagnostic for Claude Code's Auto Memory
# feature. See injecting_memories_into_containers.md for the design
# discussion this supports (curated memory seeding, still informal/
# pre-SDD as of this script).
#
# Confirms, empirically, whether Auto Memory is actually active rather than
# assuming from the CLI's changelog — base/Dockerfile's unpinned
# `npm install -g @anthropic-ai/claude-code` means the answer can change on
# any rebuild with no Dockerfile diff to signal it.
#
# Three independent checks, run separately since they need different
# things (a built image vs. a container from a session you already ran):
#
#   version   — installed Claude Code CLI version vs. the v2.1.59 gate
#   config    — whether the CLI recognizes autoMemoryDirectory as a key
#   behavior  — whether a live session actually wrote memory content
#
# Usage:
#   ./check-auto-memory.sh version  [image_tag]      (default: base)
#   ./check-auto-memory.sh config   [image_tag]      (default: base)
#   ./check-auto-memory.sh behavior <container_name>
#
# version/config each start a throwaway --rm container from the built
# image. behavior inspects a container from a session you already started
# — it does not start or stop anything, since Auto Memory content only
# exists once a real session has run.

set -euo pipefail

SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Same env-var-wins-over-config.sh precedence as build.sh/start.sh, trimmed
# to just the two values this script needs.
_ENV_ENGINE="${ENGINE:-}"
_ENV_IMAGE_PREFIX="${IMAGE_PREFIX:-}"

ENGINE="podman"
IMAGE_PREFIX="claude"

[ -f "${SANDBOX_DIR}/config.sh" ] && source "${SANDBOX_DIR}/config.sh"
[ -f "${SANDBOX_DIR}/config.local.sh" ] && source "${SANDBOX_DIR}/config.local.sh"

ENGINE="${_ENV_ENGINE:-$ENGINE}"
IMAGE_PREFIX="${_ENV_IMAGE_PREFIX:-$IMAGE_PREFIX}"

MEMORY_VERSION_GATE="2.1.59"

usage() {
    sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
}

cmd_version() {
    local image_tag="${1:-base}"
    local image_name="${IMAGE_PREFIX}-${image_tag}"

    echo "Checking Claude Code version in ${image_name}..."
    if ! "$ENGINE" image inspect "$image_name" > /dev/null 2>&1; then
        echo "Error: image '$image_name' does not exist. Build it first: ./build.sh $image_tag"
        exit 1
    fi

    local version
    version="$("$ENGINE" run --rm "$image_name" claude --version 2>&1)"
    echo "Installed: $version"
    echo "Auto Memory shipped in v${MEMORY_VERSION_GATE}. Compare manually —"
    echo "version strings aren't reliably machine-sortable across CLIs."
}

cmd_config() {
    local image_tag="${1:-base}"
    local image_name="${IMAGE_PREFIX}-${image_tag}"

    echo "Checking whether ${image_name}'s CLI recognizes autoMemoryDirectory..."
    if ! "$ENGINE" image inspect "$image_name" > /dev/null 2>&1; then
        echo "Error: image '$image_name' does not exist. Build it first: ./build.sh $image_tag"
        exit 1
    fi

    "$ENGINE" run --rm "$image_name" claude --help | grep -i --context=2 memory 2>&1 || true
    echo ""
    echo "Weak signal only: an unrecognized settings key is typically just"
    echo "ignored, not rejected. Use 'behavior' against a real session for"
    echo "a definitive answer."
}

cmd_behavior() {
    local container_name="${1:?Usage: $(basename "${BASH_SOURCE[0]}") behavior <container_name>}"

    if ! "$ENGINE" ps --format '{{.Names}}' | grep -qx "$container_name"; then
        echo "Error: no running container named '$container_name'."
        echo "This check inspects a session you already started with"
        echo "./start.sh — it does not start one itself."
        exit 1
    fi

    echo "Checking the autoMemoryDirectory override location (if injected)..."
    local override_files
    override_files="$("$ENGINE" exec "$container_name" sh -c \
        'find "$HOME/.claude/memory" -maxdepth 1 -type f 2>/dev/null' || true)"
    if [ -z "$override_files" ]; then
        echo "Not found: ~/.claude/memory (expected until the override is injected)"
    else
        echo "Found:"
        echo "$override_files"
        while IFS= read -r path; do
            case "$path" in
                *.md)
                    echo ""
                    echo "--- $path ---"
                    "$ENGINE" exec "$container_name" cat "$path"
                    ;;
            esac
        done <<< "$override_files"
    fi

    echo ""
    echo "Checking the undocumented default, project-keyed location..."
    local memory_dirs
    memory_dirs="$("$ENGINE" exec "$container_name" sh -c \
        'find "$HOME/.claude/projects" -maxdepth 3 -type d -iname "memory" 2>/dev/null' || true)"
    if [ -z "$memory_dirs" ]; then
        echo "Not found (or ~/.claude/projects does not exist yet in this session)."
    else
        while IFS= read -r dir; do
            echo "Found: $dir"
            local dir_files
            dir_files="$("$ENGINE" exec "$container_name" find "$dir" -maxdepth 1 -type f 2>/dev/null || true)"
            echo "$dir_files"
            while IFS= read -r path; do
                case "$path" in
                    *.md)
                        echo ""
                        echo "--- $path ---"
                        "$ENGINE" exec "$container_name" cat "$path"
                        ;;
                esac
            done <<< "$dir_files"
        done <<< "$memory_dirs"
    fi
}

case "${1:-}" in
    version)  shift; cmd_version "$@" ;;
    config)   shift; cmd_config "$@" ;;
    behavior) shift; cmd_behavior "$@" ;;
    *) usage ;;
esac
