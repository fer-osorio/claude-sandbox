# lib/profiles.bash — the profile list as the committed config declares it.
#
# Tests that enumerate profiles read them from here rather than from a
# literal, so a profile added to or retired from config.sh is covered, or
# dropped, without editing each test (#189). Only the committed file is
# sourced: an operator's config.local.sh must never change what the suite
# asserts on. Engine-free, so a hostonly caller stays in its selection.

# Every declared profile, one per line, in declaration order.
declared_profiles() {
    bash -c 'set -eu; source "$1/config.sh"; printf "%s\n" "${PROFILES[@]}"' \
        _ "${SANDBOX_DIR:?declared_profiles needs SANDBOX_DIR}"
}

# Every declared profile except base, which the others build on.
declared_child_profiles() {
    declared_profiles | grep -vx base
}
