#!/usr/bin/env bash
# check-auto-memory.sh — step-zero diagnostic for Claude Code's Auto Memory
# feature. See docs/designs/auto-memory-seeding-step-zero.md for the research
# pass this supports, and docs/designs/auto-memory-seeding.md §4.2 for the
# verification gate deny-scope exists to close.
#
# Confirms, empirically, whether Auto Memory is actually active rather than
# assuming from the CLI's changelog — base/Dockerfile's unpinned
# `npm install -g @anthropic-ai/claude-code` means the answer can change on
# any rebuild with no Dockerfile diff to signal it.
#
# Four independent checks, run separately since they need different things
# (a built image, a container from a session you already ran, or credentials):
#
#   version     — installed Claude Code CLI version vs. the v2.1.59 gate
#   config      — whether the CLI recognizes autoMemoryDirectory as a key
#   behavior    — whether a live session actually wrote memory content
#   deny-scope  — whether adding a user-scope settings.json weakens the
#                 project-scope permissions.deny rules already in force
#
# Usage:
#   ./check-auto-memory.sh version    [image_tag]    (default: base)
#   ./check-auto-memory.sh config     [image_tag]    (default: base)
#   ./check-auto-memory.sh behavior   <container_name>
#   ./check-auto-memory.sh deny-scope [image_tag]    (default: base)
#
# version/config each start a throwaway --rm container from the built
# image. behavior inspects a container from a session you already started
# — it does not start or stop anything, since Auto Memory content only
# exists once a real session has run. deny-scope starts one throwaway
# container and drives two real non-interactive turns in it, so it needs
# ANTHROPIC_API_KEY in your environment; it is an operator-run diagnostic
# and never part of `bats tests/`, which forbids credentials (SDD §7.2).

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
    sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# Closes the gate in auto-memory-seeding.md §4.2: does introducing a
# user-scope ~/.claude/settings.json — which the seeding design adds, purely
# to carry autoMemoryDirectory — weaken the project-scope permissions.deny
# rules a mounted repository supplies?
#
# Three arms. A and B differ in exactly one thing — whether the user-scope
# file exists — and C is the negative control.
#
# Neither control arm is optional decoration, and they fail differently:
#
#   A (deny rule, no user-scope file) must DENY. If it does not, the rule
#     never fired even without the file under test, so the run exercised
#     nothing and B's result means nothing either.
#   C (no deny rule at all) must NOT DENY. If it denies, something other
#     than the deny rule is stopping the command — a prompt reaching
#     --permission-prompts none, say — and then A and B deny for a reason
#     that has nothing to do with the rule, while looking exactly like a
#     pass.
#
# C exists because the first run of this probe was written with two arms,
# returned "A denied, B denied", and would have licensed the conclusion
# without having established that the probe could produce any other result.
# Reading that as a pass is the false-confidence failure the project's
# mechanism-verification discipline exists to prevent.
#
# The probe asserts on the filesystem, not on prose: the model is asked to
# create a file, and the check is whether that file exists afterwards.
# Parsing a refusal out of natural-language output would conflate "the deny
# rule blocked it" with "the model declined to try".
#
# Two limits, stated here rather than discovered later:
#
#   1. This drives non-interactive turns, and `claude --help` is explicit
#      that the workspace trust dialog is SKIPPED under -p (or whenever
#      stdout is not a TTY), and that settings files failing validation are
#      silently ignored in that mode with no error shown. start.sh runs
#      interactively (-it), so production takes the other path. A pass here
#      transfers to a real session by analogy, not by proof — the same
#      caveat step-zero records for Environment 2.
#   2. --allowedTools pre-allows the probe command so nothing prompts, which
#      makes the deny rule the only thing that can stop it. That is the
#      point of the probe, but it means this tests deny-beats-allow
#      precedence, not the prompt path an operator would see interactively.
cmd_deny_scope() {
    local image_tag="${1:-base}"
    local image_name="${IMAGE_PREFIX}-${image_tag}"

    if ! "$ENGINE" image inspect "$image_name" > /dev/null 2>&1; then
        echo "Error: image '$image_name' does not exist. Build it first: ./build.sh $image_tag"
        exit 1
    fi

    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        echo "Error: ANTHROPIC_API_KEY is not set in your environment."
        echo "This check drives real Claude Code turns and cannot run without it."
        echo "It is passed by name (--env ANTHROPIC_API_KEY), so the value never"
        echo "appears in a command line or in this script's output."
        exit 1
    fi

    echo "Probing settings-scope interaction in ${image_name}..."
    echo "Arm A: project-scope deny only.  Arm B: same, plus user-scope settings.json."
    echo "Arm C: negative control — no deny rule at all."
    echo ""

    # sh -s reads the probe from stdin, so a quoted heredoc keeps every
    # expansion inside the container instead of the host shell.
    "$ENGINE" run --rm -i \
        --env ANTHROPIC_API_KEY \
        --security-opt=no-new-privileges \
        --cap-drop=ALL \
        "$image_name" sh -s <<'PROBE'
set -eu

PROBE_DIR=/tmp/deny-probe
rm -rf "$PROBE_DIR"
mkdir -p "$PROBE_DIR/.claude"

# Mirrors the shape of this repo's own settings.json: a deny rule on a Bash
# command, project scope, nothing else.
cat > "$PROBE_DIR/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "deny": ["Bash(touch *)"]
  }
}
JSON

run_arm() {
    arm="$1"
    rm -f "$PROBE_DIR/RAN"
    cd "$PROBE_DIR"

    # --permission-prompts none: under -p the default target is an SDK host
    # that is not present here, and anything that would prompt would other-
    # wise hang. "none" denies whatever would prompt, which is why the probe
    # command is pre-allowed below — otherwise every arm would "pass" for
    # the wrong reason.
    timeout 180 claude -p \
        'Run exactly this command, then stop: touch /tmp/deny-probe/RAN' \
        --allowedTools 'Bash(touch *)' \
        --permission-prompts none \
        > "/tmp/arm-${arm}.out" 2>&1 || true

    if [ -e "$PROBE_DIR/RAN" ]; then
        echo "ARM ${arm}: NOT DENIED — the command executed"
    else
        echo "ARM ${arm}: no file created — denied, or never attempted"
    fi
}

# Arm A — control. No user-scope settings file at all.
rm -f "$HOME/.claude/settings.json"
run_arm A

# Arm B — the seeding design's addition: user scope, autoMemoryDirectory only,
# no permissions key of its own.
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "autoMemoryDirectory": "~/.claude/memory"
}
JSON
run_arm B

# Arm C — negative control. User-scope file stays; the project-scope deny
# rule is removed, so the only thing that could block the command is gone.
rm -f "$PROBE_DIR/.claude/settings.json"
run_arm C

echo ""
echo "--- arm A transcript ---"
cat /tmp/arm-A.out || true
echo ""
echo "--- arm B transcript ---"
cat /tmp/arm-B.out || true
echo ""
echo "--- arm C transcript ---"
cat /tmp/arm-C.out || true
PROBE

    echo ""
    echo "How to read this — check C first, then A, then B:"
    echo "  C DENIED           → INCONCLUSIVE. Something other than the deny rule"
    echo "                       is blocking the command, so A and B tell you"
    echo "                       nothing. Read the arm C transcript."
    echo "  A NOT DENIED       → INCONCLUSIVE. The rule never fired even without"
    echo "                       the user-scope file; this run tested nothing."
    echo "  C not denied,"
    echo "  A denied, B denied → PASS. The deny rule fires, and still fires with"
    echo "                       the user-scope file present."
    echo "  C not denied,"
    echo "  A denied,"
    echo "  B NOT DENIED       → REGRESSION. The user-scope file weakened"
    echo "                       project-scope deny. Stop; SDD §4.2 reopens."
    echo ""
    echo "Read the transcripts either way: 'no file created' also covers a model"
    echo "that simply declined to try, which is not the same result."
}

case "${1:-}" in
    version)    shift; cmd_version "$@" ;;
    config)     shift; cmd_config "$@" ;;
    behavior)   shift; cmd_behavior "$@" ;;
    deny-scope) shift; cmd_deny_scope "$@" ;;
    *) usage ;;
esac
