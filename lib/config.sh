# lib/config.sh — config layers 2 and 3, and the project registry. Sourced by
# start.sh and creds.sh; see docs/designs/0147-cli-credential-input-and-ergonomics.md.
#
# The caller sets SANDBOX_DIR and its own layer-1 defaults first, and applies
# its own layer-4 env overrides after. Sourcing runs the layers at the
# caller's top level rather than inside a function: config.sh uses
# 'declare -A', which inside a function would declare a local.

declare -A PROJECT_PATH=()
declare -A PROJECT_PROFILE=()

# --- Layer 2: committed, project-wide config.
[ -f "${SANDBOX_DIR}/config.sh" ] && source "${SANDBOX_DIR}/config.sh"

# Snapshot of the committed registry, taken before config.local.sh can see
# or touch it. Used below to detect and revert an attempt to redefine a
# committed name — see "Layering: config.local.sh may add, not override"
# in docs/designs/0030-named-project-registry.md. Adding a name not present in
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

# Which layer each registered name came from, for 'start.sh --list'.
declare -A PROJECT_ORIGIN=()
for _name in "${!PROJECT_PATH[@]}"; do
    if [[ -n "${COMMITTED_PROJECT_PATH[$_name]+set}" ]]; then
        PROJECT_ORIGIN[$_name]="config.sh"
    else
        PROJECT_ORIGIN[$_name]="config.local.sh"
    fi
done
unset _name

# Sets RESOLVED_PATH and RESOLVED_PROFILE for a registry name given without
# its '@', or exits with the reason. ':-' on every lookup is required: under
# 'set -u' a missing associative-array key aborts with a bash error instead
# of reaching the message.
resolve_project_name() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "Error: '@' is not a project name."
        exit 1
    fi

    RESOLVED_PATH="${PROJECT_PATH[$name]:-}"
    if [ -z "$RESOLVED_PATH" ]; then
        echo "Error: unknown project '$name'."
        echo "Registered projects: ${!PROJECT_PATH[*]}"
        echo "Add it to config.sh, or pass a path instead."
        exit 1
    fi

    RESOLVED_PROFILE="${PROJECT_PROFILE[$name]:-}"
    if [ -z "$RESOLVED_PROFILE" ]; then
        echo "Error: project '$name' has a path but no profile in config.sh."
        exit 1
    fi
}
