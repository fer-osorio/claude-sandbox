#!/usr/bin/env bats
# test_docs_integrity.bats — Group: Documentation Integrity
#
# Moves four doc-discipline rules from "prose someone is supposed to follow"
# to "a check that fails the build" — the enforcement-ladder jump the rest of
# this repo's conventions have not yet made. Every assertion here was chosen
# because a real instance of the failure already existed in the tree, or
# because the failure is invisible until someone clones fresh.
#
# No engine daemon is required by any test in this file — it reads tracked
# files and nothing else — so setup() does not gate on engine_available and
# lib/engine is not loaded. That is what makes these tests runnable in CI on
# a stock runner with no container tooling; see the "hostonly" tag below.
#
# What this suite deliberately does NOT catch, stated explicitly so nobody
# mistakes its coverage for more than it is:
#   - Backtick-quoted repo paths (`docs/AGENTS.md`, `base/entrypoint.sh`).
#     Six such paths in the tracked docs are illustrative examples rather
#     than real references, so checking them would produce false positives.
#     Only markdown links are checked.
#   - Anchor fragments. A link to a real file with a #heading that no longer
#     exists still passes D-1.
#   - Skill references that are not backtick-quoted, including the ones in
#     a SKILL.md's own frontmatter `description` field.
#   - Skills named anywhere outside the injected global layer. ADR 002
#     names `project-feasibility` as a path owner before that skill exists,
#     which is legitimate — an ADR specifies a target state. A file that is
#     injected into a live session naming a skill that was never committed
#     is a breakage. D-2 scans only the latter.
#   - Absolute or ~-relative paths (the design skill's
#     ~/.claude/templates/... reference resolves only at container runtime).

SANDBOX_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

# Emits one "<file> -> <link>" line per markdown link that does not resolve.
# Silence means every link is good. Runs in a subshell so the test's own
# working directory is left alone.
_unresolved_markdown_links() {
    (
        cd "$SANDBOX_DIR" || exit 1
        git ls-files '*.md' | while IFS= read -r f; do
            dir="$(dirname "$f")"
            # Strip fenced code blocks and inline code spans before looking
            # for links. Documentation about markdown quotes markdown: the
            # auto-memory design doc shows a MEMORY.md index entry inside a
            # ```markdown fence and the `- [Title](file.md) — hook` grammar
            # in a code span, neither of which is a reference to anything.
            # Flagging those is the false-positive class that gets a check
            # switched off, so it has to be excluded at the source.
            awk '/^[[:space:]]*```/ { fence = !fence; next } !fence { print }' "$f" 2>/dev/null \
            | sed 's/`[^`]*`//g' \
            | grep -oE '\]\([^)]+\)' 2>/dev/null \
            | sed -E 's/^\]\(//; s/\)$//' \
            | while IFS= read -r link; do
                case "$link" in
                    http://*|https://*|mailto:*|'#'*) continue ;;
                esac
                # Drop any #anchor and any ` "title"` suffix.
                target="${link%%#*}"
                target="${target%% *}"
                [ -z "$target" ] && continue
                [ -e "${dir}/${target}" ] || echo "${f} -> ${link}"
            done
        done
    )
}

# Tokens that look like a skill name but are not one. Every entry here is a
# deliberate exemption from D-2 and shows up as such in a diff — which is
# the point. An empty list means the rule below is currently unqualified.
_NOT_SKILL_NAMES=""

# The global layer (global-claude/) is bind-mounted into every session and
# copied into ~/.claude by base/entrypoint.sh. A skill it names that was
# never committed exists on the author's machine and nowhere else — the
# failure this check exists to make impossible.
#
# Convention enforced: any backtick-quoted kebab-case token in the global
# layer is a skill reference. An earlier, narrower version of this rule
# required the word "skill" adjacent to the name — it matched the single
# reference that existed at the time and missed every real one that arrived
# later, because skills cite each other as "Pairs with `other-skill`" and
# "Mutual exclusion with `other-skill`", not as "`other-skill` skill". A
# rule that matches only the example it was written against is not a rule.
#
# Scope is every *.md in global-claude/, not only the SKILL.md manifests:
# skills may ship a references/ subdirectory, and a name that dangles there
# is exactly as broken as one that dangles in the manifest.
#
# The broad form is viable because kebab-case in backticks is, empirically,
# how skills are named and not how anything else in these files is written.
# When that stops being true, add the token to _NOT_SKILL_NAMES above
# rather than narrowing the pattern back.
_unresolved_skill_refs() {
    (
        cd "$SANDBOX_DIR" || exit 1
        # Every Markdown file in the global layer, not just the SKILL.md
        # manifests: skills may ship a references/ subdirectory, and a
        # dangling skill name is exactly as broken there as in the manifest.
        find global-claude -name '*.md' | sort | while IFS= read -r f; do
            [ -f "$f" ] || continue
            grep -ohE '`[a-z0-9]+(-[a-z0-9]+)+`' "$f" 2>/dev/null \
            | tr -d '`' \
            | sort -u \
            | while IFS= read -r name; do
                case " ${_NOT_SKILL_NAMES} " in *" ${name} "*) continue ;; esac
                [ -f "global-claude/skills/${name}/SKILL.md" ] \
                    || echo "${f}: names skill '${name}', but global-claude/skills/${name}/SKILL.md is not committed"
            done
        done
    )
}

# ADRs are never rewritten (docs-as-code-workflow.md §3 Case D), so a
# missing or invalid Status is not a cosmetic problem — it is the field a
# reader uses to tell a live decision from a superseded one.
_malformed_adrs() {
    (
        cd "$SANDBOX_DIR" || exit 1
        for f in docs/adr/*.md; do
            [ -e "$f" ] || continue
            grep -qE '^# ADR [0-9]{3} — .' "$f" \
                || echo "${f}: first heading is not '# ADR NNN — <title>'"
            status_line="$(awk '/^## Status/{seen=1; next} seen && NF {print; exit}' "$f")"
            case "$status_line" in
                Proposed|Accepted|Deprecated|"Supersedes ADR "[0-9][0-9][0-9]) ;;
                *) echo "${f}: '## Status' is missing or invalid (got: '${status_line}') — expected Proposed, Accepted, Deprecated, or 'Supersedes ADR NNN'" ;;
            esac
        done
    )
}

# Regression guard for a bug that silently disabled one test in every file
# in this suite for its entire history.
#
# bats associates a "# bats test_tags=" comment with the NEXT @test it
# sees. Every file here originally placed that comment as the first line
# *inside* the test body, so each test was tagged with the previous test's
# comment and the first test of every file ended up with no tags at all —
# invisible to any --filter-tags run. That silently excluded D-1 (link
# resolution), S-1 (the core Squid allowlist assertion) and R-1 (container
# runs as non-root) from both CI and the documented fast-tier loop, while
# every run still reported green. Confirmed by counting: --filter-tags
# hostonly selected 15 of 17 tests on main.
#
# The tag comment must sit on the line above @test, which is the form
# bats-core documents.
_untagged_tests() {
    (
        cd "$SANDBOX_DIR" || exit 1
        for f in tests/*.bats; do
            [ -f "$f" ] || continue
            grep -q '^#[[:space:]]*bats[[:space:]]*file_tags=' "$f" && continue
            awk -v file="$f" '
                /^@test / {
                    if (prev !~ /^#[[:space:]]*bats[[:space:]]+test_tags=/) {
                        line = $0; sub(/[[:space:]]*\{[[:space:]]*$/, "", line)
                        print file ": " line " -- no tag comment on the line above"
                    }
                }
                $0 !~ /^[[:space:]]*$/ { prev = $0 }
            ' "$f"
        done
    )
}

_skill_dirs_without_manifest() {
    (
        cd "$SANDBOX_DIR" || exit 1
        for d in global-claude/skills/*/; do
            [ -d "$d" ] || continue
            [ -f "${d}SKILL.md" ] || echo "${d}: directory has no SKILL.md"
        done
    )
}

# bats test_tags=fast, hostonly
@test "D-1: every relative markdown link in a tracked document resolves" {
    run _unresolved_markdown_links
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- unresolved markdown links ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "D-2: every skill named in the global layer is committed to global-claude/skills/" {
    run _unresolved_skill_refs
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- skills referenced but not committed ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "D-3: every ADR has a conforming heading and a valid Status" {
    run _malformed_adrs
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- malformed ADRs ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "D-4: every directory under global-claude/skills/ contains a SKILL.md" {
    run _skill_dirs_without_manifest
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- skill directories missing a manifest ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "D-5: every @test carries a tag comment on the line above it" {
    run _untagged_tests
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- tests invisible to --filter-tags ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}
