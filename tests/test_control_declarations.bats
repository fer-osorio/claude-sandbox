#!/usr/bin/env bats
# test_control_declarations.bats — Group 9: Control Declarations (SDD §4.9)
#
# Groups 1-8 are each organised around a subject. This one is organised around
# a requirement: every assertion here reads tracked files and nothing else, so
# this file gates on nothing, lib/engine is not loaded, and CI — which filters
# on `hostonly` — selects it. Adding a test that starts a container would gate
# the whole file in setup() and silently remove the rest from CI, which is the
# trap SDD §6.2 describes. The placement rule is there: a test that asserts
# what a tracked file declares belongs in an ungated file; a test that asserts
# what a running container does does not.
#
# What this group can and cannot show. It asserts that a control is *declared*
# at the path that reads it. It cannot assert that the control is *in force*.
# That distinction is the whole subject of issue #64: G-6's ancestor asserted
# the deny list's content against a path Claude Code never loaded, and passed,
# because "is the rule written down" is a question an unread path cannot fail.
# Each test below therefore names the behavioural check that covers its other
# half. Neither half is sufficient alone.
#
# The IDs are historical and deliberately not renumbered — G-6 and B-4 are
# cited from docs/claude_code_security_plan.md Changes 22 and 23, from SDD
# §7.3, and from the commit messages of the #64 fix. Renumbering would make
# every one of those wrong in exchange for a prefix matching a filename. So
# this file holds two prefixes, matching neither its name nor each other; that
# is the recorded cost, not an oversight. G-6 came from Group 4
# (test_global_layer.bats), B-4 from Group 1 (test_build.bats).

SANDBOX_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

# bats test_tags=fast, hostonly
@test "G-6: the app-layer deny list is at the path Claude Code loads" {
    # Project scope is <project>/.claude/settings.json. Until issue #64 this
    # file sat at the repository root, and the declaration-only assertion
    # below — pointed at SANDBOX_DIR — passed anyway, because "is the rule
    # written down" is a question an unread path cannot fail. Hence the
    # first two assertions: the location is now part of what is checked,
    # and a reintroduced root-level copy fails rather than shadowing.
    [ -f "${SANDBOX_DIR}/.claude/settings.json" ]
    [ ! -e "${SANDBOX_DIR}/settings.json" ]

    # Enforcement still needs a live turn, and therefore credentials that
    # SDD §7.2 forbids here. `./check-auto-memory.sh deny-path` covers that
    # half — it establishes which path is enforced, this establishes that
    # the repository uses it. Neither is sufficient on its own; the defect
    # survived because only the weaker half of the pair existed.
    run grep -q '"Write(/run/\*)"' "${SANDBOX_DIR}/.claude/settings.json"
    [ "$status" -eq 0 ]
}

# bats test_tags=fast, hostonly
@test "B-4: build.sh does not pin any image reference to :latest" {
    # The behavioural half is B-1 and B-3 in test_build.bats: they build
    # against the explicit tags and would fail if reference resolution
    # actually changed. This asserts only that the scripts still say so.
    ! grep -q ":latest" "${SANDBOX_DIR}/build.sh"
    ! grep -q ":latest" "${SANDBOX_DIR}/start.sh"
}
