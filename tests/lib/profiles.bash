# lib/profiles.bash — the profile list as the committed config declares it.
#
# Tests that enumerate profiles read them from here rather than from a
# literal, so a profile added to or retired from config/config.sh is covered,
# or dropped, without editing each test (#189). Only the committed file is
# sourced: an operator's config.local.sh must never change what the suite
# asserts on. Engine-free, so a hostonly caller stays in its selection.

# Every declared profile, one per line, in declaration order.
declared_profiles() {
    bash -c 'set -eu; source "$1/config/config.sh"; printf "%s\n" "${PROFILES[@]}"' \
        _ "${SANDBOX_DIR:?declared_profiles needs SANDBOX_DIR}"
}

# Every declared profile except base, which the others build on.
declared_child_profiles() {
    declared_profiles | grep -vx base
}

# Every declared combination as "<name> <member> <member>...", one per line,
# in name order.
declared_combos() {
    bash -c 'set -eu; declare -A COMBOS=(); source "$1/config/config.sh"
             for n in "${!COMBOS[@]}"; do echo "$n ${COMBOS[$n]}"; done | sort' \
        _ "${SANDBOX_DIR:?declared_combos needs SANDBOX_DIR}"
}

# The command that shows a child profile's toolchain works, run inside its
# image by T-1 and, for every member, inside each combination by T-4.
# Fails for a profile with none, so T-4 cannot pass a member it never ran.
profile_smoke_command() {
    case "$1" in
        crypto) echo 'softhsm2-util --show-slots && p11-kit list-modules' ;;
        *) return 1 ;;
    esac
}
