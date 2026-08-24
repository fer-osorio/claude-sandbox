#!/usr/bin/env bash
# config.sh — profile and runtime defaults for claude-sandbox.
#
# Committed, project-wide, reviewed. Sourced directly by build.sh and
# start.sh — plain Bash variables and arrays, not a data format, so no
# parser dependency is introduced (mirrors tests/lib/engine.bash, this
# project's existing sourced-library pattern).
#
# Precedence (later wins):
#   hardcoded defaults in build.sh/start.sh
#     < config.sh (this file)
#     < config.local.sh (gitignored, per-machine — see config.local.sh.example)
#     < matching env var at call time (e.g. ENGINE=docker ./start.sh ...)
#
# Security-relevant values (resource limits, log options) are
# version-controlled here; treat changes to this file with the same care
# as a Dockerfile change. See docs/designs/sandbox-config-file.md.

# Profiles start.sh accepts and build.sh knows how to build. "base" has no
# entry in PROFILE_BASE below — it builds directly, not on top of anything.
PROFILES=(base crypto systems research)

# Maps a profile to its base-image dependency. A profile absent from this
# map builds directly (currently only "base" itself).
declare -A PROFILE_BASE=(
    [crypto]=base
    [systems]=base
    [research]=base
)

IMAGE_PREFIX="claude"   # image tag = "${IMAGE_PREFIX}-${profile}"
ENGINE="podman"         # container engine binary; ENGINE env var overrides at call time

# Main session container (start.sh).
MAIN_MEMORY="2g"
MAIN_CPUS="2"
MAIN_LOG_MAX_SIZE="50m"
MAIN_LOG_MAX_FILE="5"

# Squid proxy container (start.sh).
PROXY_LOG_MAX_SIZE="10m"
PROXY_LOG_MAX_FILE="3"

# ── Project Registry ─────────────────────────────────────────────
# Maps a project name to its path and its default profile. Addressed
# from start.sh as "@<name>" (e.g. ./start.sh @mylib). See
# docs/designs/named-project-registry.md.
#
# ${PROJECT_BASE} keeps this file portable across machines: it is the
# one machine-specific value, and it is resolved from the environment
# with a sensible default rather than being hardcoded here.
#
# config.local.sh may add entries for names not listed here (a
# machine-local project not worth committing); it may not redefine a
# name already registered below — such an attempt is reverted with a
# warning rather than honored. See the Layering section of the design
# doc above.

PROJECT_BASE="${PROJECT_BASE:-$HOME/projects}"

# Example (commented out — no real project entries ship in this file):
# declare -A PROJECT_PATH=(
#     [mylib]="${PROJECT_BASE}/mylib"
# )
#
# declare -A PROJECT_PROFILE=(
#     [mylib]=crypto
# )

declare -A PROJECT_PATH=()
declare -A PROJECT_PROFILE=()
