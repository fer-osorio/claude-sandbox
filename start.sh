#!/usr/bin/env bash
# Usage: start.sh [<project_directory> | @<name>] [image]
#
# Arguments:
#   project_directory  — path to the project to mount (default: current dir)
#   @name              — a project registered in config.sh's PROJECT_PATH /
#                        PROJECT_PROFILE (and optionally extended by
#                        config.local.sh — see docs/designs/named-project-registry.md)
#   image              — which sandbox image to use (default: base, or the
#                        registered project's default profile for @name);
#                        one of the profiles defined in config.sh
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
#   ./start.sh @mylib                       — registry path + registry profile
#   ./start.sh @mylib systems               — registry path, profile overridden
#
# Before running this for the first time, ensure the network exists:
#   podman network create --driver bridge claude-net
#   (or: docker network create --driver bridge claude-net, under ENGINE=docker)
#
# Profile list, image prefix, engine default, and resource/log-driver
# settings come from config.sh (and optionally config.local.sh, gitignored,
# per-machine). Precedence: hardcoded defaults below < config.sh <
# config.local.sh < env var. See docs/designs/sandbox-config-file.md.
#
# Engine:
#   ENGINE=podman (default) or ENGINE=docker selects which container engine
#   binary is invoked. See docs/designs/podman-migration.md.

set -euo pipefail

SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Layer 4 capture: preserve any pre-set env var overrides before the
# layers below can clobber them.
_ENV_ENGINE="${ENGINE:-}"
_ENV_IMAGE_PREFIX="${IMAGE_PREFIX:-}"
_ENV_MAIN_MEMORY="${MAIN_MEMORY:-}"
_ENV_MAIN_CPUS="${MAIN_CPUS:-}"
_ENV_MAIN_LOG_MAX_SIZE="${MAIN_LOG_MAX_SIZE:-}"
_ENV_MAIN_LOG_MAX_FILE="${MAIN_LOG_MAX_FILE:-}"
_ENV_PROXY_LOG_MAX_SIZE="${PROXY_LOG_MAX_SIZE:-}"
_ENV_PROXY_LOG_MAX_FILE="${PROXY_LOG_MAX_FILE:-}"

# --- Layer 1: hardcoded defaults, so this script still works if config.sh
# is missing.
ENGINE="podman"
IMAGE_PREFIX="claude"
PROFILES=(base crypto systems research)
MAIN_MEMORY="2g"
MAIN_CPUS="2"
MAIN_LOG_MAX_SIZE="50m"
MAIN_LOG_MAX_FILE="5"
PROXY_LOG_MAX_SIZE="10m"
PROXY_LOG_MAX_FILE="3"
declare -A PROJECT_PATH=()
declare -A PROJECT_PROFILE=()

# --- Layer 2: committed, project-wide config.
[ -f "${SANDBOX_DIR}/config.sh" ] && source "${SANDBOX_DIR}/config.sh"

# Snapshot of the committed registry, taken before config.local.sh can see
# or touch it. Used below to detect and revert an attempt to redefine a
# committed name — see "Layering: config.local.sh may add, not override"
# in docs/designs/named-project-registry.md. Adding a name not present in
# config.sh is unrestricted; this only guards names that are.
declare -A COMMITTED_PROJECT_PATH=()
declare -A COMMITTED_PROJECT_PROFILE=()
for _name in "${!PROJECT_PATH[@]}"; do
    COMMITTED_PROJECT_PATH[$_name]="${PROJECT_PATH[$_name]}"
    COMMITTED_PROJECT_PROFILE[$_name]="${PROJECT_PROFILE[$_name]:-}"
done
unset _name

# --- Layer 3: gitignored, per-machine overrides.
[ -f "${SANDBOX_DIR}/config.local.sh" ] && source "${SANDBOX_DIR}/config.local.sh"

# Revert (and warn about) any committed project name config.local.sh
# redefined. An operator who wants to repoint a committed name edits
# config.sh instead — a one-line, reviewed change.
for _name in "${!COMMITTED_PROJECT_PATH[@]}"; do
    if [[ "${PROJECT_PATH[$_name]:-}" != "${COMMITTED_PROJECT_PATH[$_name]}" ]] \
    || [[ "${PROJECT_PROFILE[$_name]:-}" != "${COMMITTED_PROJECT_PROFILE[$_name]}" ]]; then
        echo "Warning: config.local.sh redefines committed project '$_name';" \
             "ignoring the local value (config.sh wins)." >&2
        PROJECT_PATH[$_name]="${COMMITTED_PROJECT_PATH[$_name]}"
        PROJECT_PROFILE[$_name]="${COMMITTED_PROJECT_PROFILE[$_name]}"
    fi
done
unset _name

# --- Layer 4: env var wins over everything sourced above.
ENGINE="${_ENV_ENGINE:-$ENGINE}"
IMAGE_PREFIX="${_ENV_IMAGE_PREFIX:-$IMAGE_PREFIX}"
MAIN_MEMORY="${_ENV_MAIN_MEMORY:-$MAIN_MEMORY}"
MAIN_CPUS="${_ENV_MAIN_CPUS:-$MAIN_CPUS}"
MAIN_LOG_MAX_SIZE="${_ENV_MAIN_LOG_MAX_SIZE:-$MAIN_LOG_MAX_SIZE}"
MAIN_LOG_MAX_FILE="${_ENV_MAIN_LOG_MAX_FILE:-$MAIN_LOG_MAX_FILE}"
PROXY_LOG_MAX_SIZE="${_ENV_PROXY_LOG_MAX_SIZE:-$PROXY_LOG_MAX_SIZE}"
PROXY_LOG_MAX_FILE="${_ENV_PROXY_LOG_MAX_FILE:-$PROXY_LOG_MAX_FILE}"

PROJECT_ARG="${1:-$(pwd)}"
IMAGE_TAG="${2:-}"

# @name resolution — see docs/designs/named-project-registry.md. Runs
# after both config layers are sourced, before the existing directory
# check below, so a resolved registry path receives exactly the
# validation an explicit path receives.
if [[ "$PROJECT_ARG" == @* ]]; then
    PROJECT_NAME="${PROJECT_ARG#@}"

    if [ -z "$PROJECT_NAME" ]; then
        echo "Error: '@' is not a project name."
        exit 1
    fi

    # ':-' is required: under 'set -u' a lookup on a missing associative
    # array key aborts the script with a bash error instead of reaching
    # the message below.
    RESOLVED_PATH="${PROJECT_PATH[$PROJECT_NAME]:-}"
    if [ -z "$RESOLVED_PATH" ]; then
        echo "Error: unknown project '$PROJECT_NAME'."
        echo "Registered projects: ${!PROJECT_PATH[*]}"
        echo "Add it to config.sh, or pass a path instead."
        exit 1
    fi

    RESOLVED_PROFILE="${PROJECT_PROFILE[$PROJECT_NAME]:-}"
    if [ -z "$RESOLVED_PROFILE" ]; then
        echo "Error: project '$PROJECT_NAME' has a path but no profile in config.sh."
        exit 1
    fi

    PROJECT_ARG="$RESOLVED_PATH"
    IMAGE_TAG="${IMAGE_TAG:-$RESOLVED_PROFILE}"
fi

PROJECT_DIR="$(realpath "$PROJECT_ARG")"
IMAGE_TAG="${IMAGE_TAG:-base}"

if ! "$ENGINE" info > /dev/null 2>&1; then
    echo "Error: $ENGINE is not reachable."
    echo "Start $ENGINE and try again."
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: '$PROJECT_DIR' is not a directory."
    exit 1
fi

if ! printf '%s\n' "${PROFILES[@]}" | grep -qx "$IMAGE_TAG"; then
    echo "Error: unknown image '$IMAGE_TAG'."
    echo "Valid options: ${PROFILES[*]}"
    exit 1
fi

IMAGE_NAME="${IMAGE_PREFIX}-${IMAGE_TAG}"

if ! "$ENGINE" image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    echo "Error: image '$IMAGE_NAME' does not exist."
    echo "Build it first with: ./build.sh $IMAGE_TAG"
    exit 1
fi

if ! "$ENGINE" network inspect claude-net > /dev/null 2>&1; then
    echo "Error: network 'claude-net' does not exist."
    echo "Create it with: $ENGINE network create --driver bridge claude-net"
    exit 1
fi

SQUID_IMAGE_NAME="${IMAGE_PREFIX}-squid"
if ! "$ENGINE" image inspect "$SQUID_IMAGE_NAME" > /dev/null 2>&1; then
    echo "Error: image '$SQUID_IMAGE_NAME' does not exist."
    echo "Build it first with: ./build.sh squid"
    exit 1
fi

GLOBAL_BASE="${SANDBOX_DIR}/global-claude"
GLOBAL_OVERLAY="${SANDBOX_DIR}/global-${IMAGE_TAG}"

echo "Project:  $PROJECT_DIR"
echo "Image:    $IMAGE_NAME"
echo "Network:  claude-net via ${SQUID_IMAGE_NAME} proxy (see squid/squid.conf for allowlist)"

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

# SELinux relabel suboption for bind mounts, Podman path only. Without it, a
# bind-mounted host directory keeps its original SELinux context on an
# SELinux-enforcing host, and the confined container process gets EACCES on
# it regardless of correct POSIX bits (a MAC layer above standard Unix
# permissions) — see docs/claude_code_security_plan.md Change 19. "shared"
# (not "private"/:Z) because GLOBAL_BASE/GLOBAL_OVERLAY are mounted by every
# concurrent session and /workspace itself can be mounted by two sessions
# against the same project dir; "private" relabeling is exclusive per
# container and invalidates a prior container's access to the same host
# path. Trade-off: "shared" drops these paths to the generic, non-exclusive
# container_file_t context, removing SELinux MCS-based isolation from other
# shared-context containers on the host — accepted because --cap-drop=ALL,
# non-root execution, no-new-privileges, and per-session mount namespacing
# are the primary isolation boundary here, not SELinux. Docker's --mount has
# no relabel suboption (only the legacy -v ...:z syntax does), so the
# Docker fallback path is unchanged; the same underlying bug is presumed to
# still be present there on SELinux-enforcing hosts (e.g. Fedora) — tracked
# in podman-migration.md §9, not fixed here.
RELABEL_ARG=""
if [ "$ENGINE" = "podman" ]; then
    RELABEL_ARG=",relabel=shared"
fi

MOUNT_ARGS=(
    "--mount" "type=bind,source=${PROJECT_DIR},target=/workspace${RELABEL_ARG}"
)

ENV_ARGS=()
if [ -n "${GH_TOKEN:-}" ]; then
    ENV_ARGS+=("-e" "GH_TOKEN")
fi

if [ -d "$GLOBAL_BASE" ]; then
    MOUNT_ARGS+=(
        "--mount" "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly${RELABEL_ARG}"
    )
fi

if [ -d "$GLOBAL_OVERLAY" ] && [ "$IMAGE_TAG" != "base" ]; then
    MOUNT_ARGS+=(
        "--mount" "type=bind,source=${GLOBAL_OVERLAY},target=/run/claude-overlay,readonly${RELABEL_ARG}"
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
# Size/count values come from config.sh (see header) — same defaults as
# before this became config-driven.
PROXY_LOG_ARGS=(--log-driver json-file --log-opt "max-size=${PROXY_LOG_MAX_SIZE}" --log-opt "max-file=${PROXY_LOG_MAX_FILE}")
MAIN_LOG_ARGS=(--log-driver json-file --log-opt "max-size=${MAIN_LOG_MAX_SIZE}" --log-opt "max-file=${MAIN_LOG_MAX_FILE}")

echo "Starting Squid proxy ($PROXY_NAME)..."
if ! "$ENGINE" run -d \
    --name "$PROXY_NAME" \
    --network claude-net \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    "${PROXY_LOG_ARGS[@]}" \
    "$SQUID_IMAGE_NAME" > /dev/null; then
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
    --memory="${MAIN_MEMORY}" \
    --cpus="${MAIN_CPUS}" \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    "${USERNS_ARGS[@]}" \
    "${MAIN_LOG_ARGS[@]}" \
    "$IMAGE_NAME"
