#!/usr/bin/env bash
# creds.sh — manage the per-project encrypted credential store that start.sh
# decrypts at launch. See docs/designs/0129-encrypted-credential-store.md for
# the design, and docs/planning/0129-encrypted-credential-store/scope.md for
# what the store is for.
#
# One age identity protects the whole store. Its private half lives
# passphrase-wrapped in identity.age and is never written to disk unwrapped.
# Each credentialed project has one file, named for the SHA-256 of its
# resolved path, encrypted to the identity's public key.
#
# Usage:
#   ./creds.sh init [--recover]     — create the store, or rebuild the public
#                                     key from an identity you have restored
#   ./creds.sh add <project> <KEY>  — add or replace one credential
#   ./creds.sh list [<project>]     — list credentialed projects, or the key
#                                     names held for one project
#   ./creds.sh rm <project> [<KEY>] — remove one credential, or a project's
#                                     whole file when no KEY is given
#   ./creds.sh rotate               — re-encrypt every file to a new identity
#   ./creds.sh migrate <old> <new>  — re-key a project directory that moved
#
# <project> is a directory path, resolved with realpath so it matches what
# start.sh resolves at launch — including a path reached through an @name
# registry entry, which start.sh resolves before it calls realpath.
#
# The passphrase is needed to read the store, never to create it. Adding the
# first credential for a project encrypts to the public key alone and prompts
# for nothing; adding a second one has to read the first, and prompts.
#
# Values are read from the terminal with echo disabled. They are never passed
# as arguments, so they reach neither the shell history nor ps.
#
# The store lives outside this repository by default, because a store inside
# it would be bind-mounted into any session opened on claude-sandbox itself.
# See docs/designs/0129-encrypted-credential-store.md §Store location, and
# config.sh for how to move it.

set -euo pipefail

# Everything this script writes is either a secret or a record of which
# projects hold one. Nothing here is group- or world-readable.
umask 077

SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Same env-wins-over-config.sh precedence as build.sh/start.sh, trimmed to the
# one value this script needs. See docs/designs/0028-sandbox-config-file.md.
_ENV_CREDENTIALS_DIR="${CREDENTIALS_DIR:-}"

CREDENTIALS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-sandbox/credentials"

[ -f "${SANDBOX_DIR}/config.sh" ] && source "${SANDBOX_DIR}/config.sh"
[ -f "${SANDBOX_DIR}/config.local.sh" ] && source "${SANDBOX_DIR}/config.local.sh"

CREDENTIALS_DIR="${_ENV_CREDENTIALS_DIR:-$CREDENTIALS_DIR}"

IDENTITY_FILE="${CREDENTIALS_DIR}/identity.age"
RECIPIENT_FILE="${CREDENTIALS_DIR}/recipient.pub"
INDEX_FILE="${CREDENTIALS_DIR}/index"

# Key names that would change how start.sh or its shell behaves, rather than
# being handed to the container as a credential. Duplicated verbatim in
# start.sh, which is the enforcement point — this copy only buys a better
# error message at add time. C-18 fails if the two drift apart.
DENIED_KEYS=(
    PATH LD_PRELOAD LD_LIBRARY_PATH IFS BASH_ENV ENV SHELLOPTS BASHOPTS
    HOME HTTP_PROXY HTTPS_PROXY NO_PROXY
    ENGINE IMAGE_PREFIX CREDENTIALS_DIR PROFILES
    MAIN_MEMORY MAIN_CPUS MAIN_LOG_MAX_SIZE MAIN_LOG_MAX_FILE
    PROXY_LOG_MAX_SIZE PROXY_LOG_MAX_FILE
)

usage() {
    sed -n '2,37p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
}

# --- helpers

require_age() {
    if ! command -v age > /dev/null 2>&1; then
        echo "Error: 'age' is not installed."
        echo "See BUILDING.md §Prerequisites; the store cannot be read without it."
        exit 1
    fi
}

require_store() {
    if [ ! -f "$IDENTITY_FILE" ] || [ ! -f "$RECIPIENT_FILE" ]; then
        echo "Error: no credential store at $CREDENTIALS_DIR."
        echo "Create one with: ./creds.sh init"
        exit 1
    fi
}

# SHA-256 of the resolved project path. start.sh computes this identically;
# the two must agree or a stored credential becomes unreachable at launch.
hash_path() {
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
}

resolve_project() {
    local arg="$1"
    if [ ! -d "$arg" ]; then
        echo "Error: '$arg' is not a directory." >&2
        exit 1
    fi
    realpath "$arg"
}

validate_key() {
    local key="$1" denied
    if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "Error: '$key' is not a usable environment variable name."
        exit 1
    fi
    for denied in "${DENIED_KEYS[@]}"; do
        if [ "$key" = "$denied" ]; then
            echo "Error: '$key' changes how start.sh itself runs and cannot be a credential."
            echo "See docs/designs/0129-encrypted-credential-store.md §File format."
            exit 1
        fi
    done
}

# Unwraps the identity into a pipe and decrypts one file through it. The
# unwrapped identity exists only as a file descriptor: never a variable,
# never a file, never an argument.
decrypt_file() {
    age -d -i <(age -d "$IDENTITY_FILE") "$1"
}

# Encrypts stdin to the project's file, via a temporary in the same directory
# so an interrupted write cannot truncate a good store.
encrypt_to() {
    local dest="$1"
    age -R "$RECIPIENT_FILE" -o "${dest}.tmp"
    mv "${dest}.tmp" "$dest"
}

index_record() {
    local hash="$1" dir="$2"
    touch "$INDEX_FILE"
    grep -v "^${hash}	" "$INDEX_FILE" > "${INDEX_FILE}.tmp" || true
    printf '%s\t%s\n' "$hash" "$dir" >> "${INDEX_FILE}.tmp"
    sort -k2 "${INDEX_FILE}.tmp" -o "${INDEX_FILE}.tmp"
    mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
}

index_forget() {
    local hash="$1"
    [ -f "$INDEX_FILE" ] || return 0
    grep -v "^${hash}	" "$INDEX_FILE" > "${INDEX_FILE}.tmp" || true
    mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
}

# --- commands

cmd_init() {
    require_age

    if [ "${1:-}" = "--recover" ]; then
        if [ ! -f "$IDENTITY_FILE" ]; then
            echo "Error: --recover needs a restored $IDENTITY_FILE."
            echo "Put the backed-up identity there first."
            exit 1
        fi
        age-keygen -y <(age -d "$IDENTITY_FILE") > "$RECIPIENT_FILE"
        echo "Public key rebuilt from the restored identity."
        echo "Restore the <hash>.age files and index alongside it, then: ./creds.sh list"
        return
    fi

    if [ -e "$IDENTITY_FILE" ]; then
        echo "Error: a store already exists at $CREDENTIALS_DIR."
        echo "Use './creds.sh rotate' to change the identity, or remove it by hand."
        exit 1
    fi

    mkdir -p "$CREDENTIALS_DIR"

    local identity
    identity="$(age-keygen 2> /dev/null)"
    printf '%s\n' "$identity" | age -p -o "$IDENTITY_FILE"
    printf '%s\n' "$identity" | age-keygen -y > "$RECIPIENT_FILE"
    unset identity

    echo ""
    echo "Store created at $CREDENTIALS_DIR."
    echo ""
    echo "Back up $IDENTITY_FILE now, before it is worth anything."
    echo "It is passphrase-wrapped, so it is safe to copy anywhere the"
    echo "passphrase is not — another machine, removable media, a password"
    echo "manager attachment. Keep the passphrase somewhere else again."
    echo ""
    echo "Losing both means every credential in the store must be revoked at"
    echo "its issuer and reissued. There is no other recovery."
}

cmd_add() {
    require_age
    require_store

    local project="${1:-}" key="${2:-}"
    if [ -z "$project" ] || [ -z "$key" ]; then
        usage
    fi
    validate_key "$key"

    local dir hash file value existing
    dir="$(resolve_project "$project")"
    hash="$(hash_path "$dir")"
    file="${CREDENTIALS_DIR}/${hash}.age"

    read -rsp "Value for ${key}: " value
    echo ""
    if [ -z "$value" ]; then
        echo "Error: empty value; nothing stored."
        exit 1
    fi

    if [ -f "$file" ]; then
        echo "Reading the existing credentials for this project."
        if ! existing="$(decrypt_file "$file")"; then
            echo "Error: could not read $file."
            echo "Wrong passphrase, or the file does not belong to this identity."
            exit 1
        fi
        { printf '%s\n' "$existing" | grep -v "^${key}=" || true
          printf '%s=%s\n' "$key" "$value"
        } | grep -v '^[[:space:]]*$' | encrypt_to "$file"
        unset existing
    else
        printf '%s=%s\n' "$key" "$value" | encrypt_to "$file"
    fi
    unset value

    index_record "$hash" "$dir"
    echo "Stored ${key} for ${dir}."
}

cmd_list() {
    require_store

    if [ -z "${1:-}" ]; then
        if [ ! -s "${INDEX_FILE:-/nonexistent}" ]; then
            echo "No credentials stored."
            return
        fi
        printf '%s\n' "Projects with credentials:"
        while IFS=$'\t' read -r hash dir; do
            [ -f "${CREDENTIALS_DIR}/${hash}.age" ] || continue
            printf '  %s\n' "$dir"
        done < "$INDEX_FILE"
        return
    fi

    require_age
    local dir hash file
    dir="$(resolve_project "$1")"
    hash="$(hash_path "$dir")"
    file="${CREDENTIALS_DIR}/${hash}.age"

    if [ ! -f "$file" ]; then
        echo "No credentials stored for ${dir}."
        return
    fi
    echo "Credentials for ${dir}:"
    decrypt_file "$file" | cut -d= -f1 | sed 's/^/  /'
}

cmd_rm() {
    require_store

    local project="${1:-}" key="${2:-}"
    [ -n "$project" ] || usage

    local dir hash file remaining
    dir="$(resolve_project "$project")"
    hash="$(hash_path "$dir")"
    file="${CREDENTIALS_DIR}/${hash}.age"

    if [ ! -f "$file" ]; then
        echo "No credentials stored for ${dir}."
        return
    fi

    if [ -z "$key" ]; then
        rm -f "$file"
        index_forget "$hash"
        echo "Removed every credential for ${dir}."
        return
    fi

    require_age
    if ! remaining="$(decrypt_file "$file" | grep -v "^${key}=")"; then
        remaining=""
    fi
    if [ -z "$remaining" ]; then
        rm -f "$file"
        index_forget "$hash"
        echo "Removed ${key}; no credentials remain for ${dir}."
        return
    fi
    printf '%s\n' "$remaining" | encrypt_to "$file"
    echo "Removed ${key} from ${dir}."
}

# Leaves the old identity as identity.age.prev until the operator removes it,
# so an interrupted rotation is recoverable rather than a destroyed store.
cmd_rotate() {
    require_age
    require_store

    local new_identity file
    echo "Unlocking the current identity."
    new_identity="$(age-keygen 2> /dev/null)"

    local staged=()
    for file in "${CREDENTIALS_DIR}"/*.age; do
        [ -e "$file" ] || continue
        [ "$file" = "$IDENTITY_FILE" ] && continue
        if ! decrypt_file "$file" \
            | age -r "$(printf '%s\n' "$new_identity" | age-keygen -y)" -o "${file}.new"; then
            echo "Error: could not re-encrypt $file."
            echo "Nothing has been replaced; the store is unchanged."
            rm -f "${CREDENTIALS_DIR}"/*.age.new
            unset new_identity
            exit 1
        fi
        staged+=("$file")
    done

    mv "$IDENTITY_FILE" "${IDENTITY_FILE}.prev"
    echo "Set the passphrase for the new identity."
    printf '%s\n' "$new_identity" | age -p -o "$IDENTITY_FILE"
    printf '%s\n' "$new_identity" | age-keygen -y > "$RECIPIENT_FILE"
    unset new_identity

    for file in "${staged[@]}"; do
        mv "${file}.new" "$file"
    done

    echo "Rotated ${#staged[@]} credential file(s)."
    echo "The previous identity is at ${IDENTITY_FILE}.prev — remove it once"
    echo "you have backed the new one up."
}

cmd_migrate() {
    require_store

    local old="${1:-}" new="${2:-}"
    if [ -z "$old" ] || [ -z "$new" ]; then
        usage
    fi

    # The old path is deliberately not resolved with realpath: a directory
    # that moved no longer exists there, which is the whole reason to migrate.
    local old_hash new_dir new_hash
    old_hash="$(hash_path "$old")"
    new_dir="$(resolve_project "$new")"
    new_hash="$(hash_path "$new_dir")"

    if [ ! -f "${CREDENTIALS_DIR}/${old_hash}.age" ]; then
        echo "Error: no credentials stored under '$old'."
        echo "Paths are matched exactly as start.sh resolves them; './creds.sh list' shows them."
        exit 1
    fi
    if [ -e "${CREDENTIALS_DIR}/${new_hash}.age" ]; then
        echo "Error: ${new_dir} already has credentials."
        echo "Remove them first with: ./creds.sh rm '$new_dir'"
        exit 1
    fi

    mv "${CREDENTIALS_DIR}/${old_hash}.age" "${CREDENTIALS_DIR}/${new_hash}.age"
    index_forget "$old_hash"
    index_record "$new_hash" "$new_dir"
    echo "Migrated credentials from ${old} to ${new_dir}."
}

case "${1:-}" in
    init)    shift; cmd_init "$@" ;;
    add)     shift; cmd_add "$@" ;;
    list)    shift; cmd_list "$@" ;;
    rm)      shift; cmd_rm "$@" ;;
    rotate)  shift; cmd_rotate "$@" ;;
    migrate) shift; cmd_migrate "$@" ;;
    *) usage ;;
esac
