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
#     D-1 checks only markdown links; D-11 checks docs/*.md tokens, with
#     the illustrative ones exempted by name. Other directories are not
#     covered.
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
#     That reference is not unchecked, only uncheckable from here: G-10 in
#     tests/test_global_layer.bats asserts every file under global-claude/
#     arrives at the matching ~/.claude/ path, which is what makes the
#     citation resolve in a live session. The split is engine access, not
#     coverage — G-10 needs a running container, so it cannot live in this
#     file (see the SDD §6.2 note on engine-gated setup()).

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

# The global layer is copied into ~/.claude in every session, so its size is
# a permanent context-window cost paid by every task. docs/designs/
# 0003-global-layer-injection.md §5.2 names "Global layer size discipline" as the
# Denial of Service control and puts a 200-line CLAUDE.md at "significant but
# acceptable" — but named the control without giving it a mechanism, so
# nothing has ever observed it fail. D-6 and D-7 are that mechanism.
#
# Ceilings are lines, not bytes. The same directory measures 66K, 123K or
# 160K depending on whether you sum file contents, count directory entries,
# or count allocated blocks; a ceiling whose unit is ambiguous either never
# fires or fires when a subdirectory is added. docs/planning/README.md made
# the same call for the artifact templates and for the same reason.
#
# The §5.2 illustration (a 200-line CLAUDE.md plus five skills of similar
# size, so roughly 1200 lines) is already exceeded at 1566. D-7 is therefore
# set above current usage deliberately: it is a bound on unnoticed growth,
# not a target to shrink toward.
_CLAUDE_MD_MAX_LINES=200
_GLOBAL_LAYER_MAX_LINES=3000

_claude_md_over_ceiling() {
    (
        cd "$SANDBOX_DIR" || exit 1
        n=$(wc -l < global-claude/CLAUDE.md)
        [ "$n" -le "$_CLAUDE_MD_MAX_LINES" ] \
            || echo "global-claude/CLAUDE.md: ${n} lines exceeds the ${_CLAUDE_MD_MAX_LINES}-line ceiling"
    )
}

_global_layer_over_ceiling() {
    (
        cd "$SANDBOX_DIR" || exit 1
        n=$(find global-claude -type f -exec cat {} + | wc -l)
        [ "$n" -le "$_GLOBAL_LAYER_MAX_LINES" ] \
            || echo "global-claude/: ${n} lines across all files exceeds the ${_GLOBAL_LAYER_MAX_LINES}-line ceiling"
    )
}

# D-2 checks that a named skill is committed and D-4 that a skill directory
# carries a manifest. Neither reads the frontmatter, so a manifest whose
# description does not parse passed both while being, in the only sense that
# matters, absent: a skill's description is the half loaded into every
# session, and the body is deferred until something invokes it. A description
# that does not resolve is a skill that never fires.
#
# This existed. global-claude/skills/design/SKILL.md carried
#
#     description:
#     > Invoke at the beginning of any significant change ...
#
# with the block indicator unindented at column 0, so the key's value was
# empty and the trigger the Design Workflow rule in CLAUDE.md depends on was
# never in context. Fixed in #56; this is the guard.
#
# Two forms are accepted, matching what the committed skills actually use:
# text on the same line as the key, or a `>`/`|` indicator followed by at
# least one indented continuation line.
_skills_without_loadable_description() {
    (
        cd "$SANDBOX_DIR" || exit 1
        for f in global-claude/skills/*/SKILL.md; do
            [ -f "$f" ] || continue
            resolved="$(awk '
                NR == 1                            { if ($0 != "---") exit; next }
                $0 == "---"                        { exit }
                /^description:[ \t]*[|>][ \t]*$/  { block = 1; next }
                /^description:[ \t]*[^ \t]/       { print "ok"; exit }
                block && /^[ \t]+[^ \t]/          { print "ok"; exit }
                block                              { block = 0 }
            ' "$f")"
            [ "$resolved" = "ok" ] \
                || echo "${f}: description does not resolve to text — absent, empty, or an unindented block indicator"
        done
    )
}

# The global layer is authored here and read inside a different repository,
# so a repo-relative path written there resolves against the reader's tree.
# It dangles, or — worse, for an ADR number, since numbering restarts at 001
# everywhere — it resolves to a different document that happens to sit at
# the same path. ADR 005 qualifies ADR 003 decision 4 for these files and is
# what this check enforces.
#
# The discriminator is direction, and it cannot be inferred from the path.
# `docs/designs/docs-as-code-workflow.md` is correct in the design skill,
# which tells the reader to look for it in its own repository, and wrong in
# CLAUDE.md:71, which cites it as though it were always present. So the
# exemptions below are per file and path, not per path — an exemption is a
# judgment, and it shows up as one in a diff.
#
# Paths that are target-relative by construction: everything the Planning
# contract writes into the reader's own docs/planning/, and the bare
# directory names the workflow template uses to describe a layout.
_D9_ALLOWED_PREFIXES="docs/planning/"
_D9_ALLOWED_EXACT="docs/adr/ docs/designs/ docs/plans/"
# Conditional citations: the sentence around them already states that the
# reader's repository may not carry the thing being named.
_D9_ALLOWED_PAIRS="global-claude/skills/design/SKILL.md:docs/designs/docs-as-code-workflow.md
global-claude/skills/swe-prior-art-research/SKILL.md:tests/test_planning_artifacts.bats"
_D9_QUALIFIER="of the claude-sandbox project"

_cross_boundary_citations() {
    (
        cd "$SANDBOX_DIR" || exit 1
        find global-claude -name '*.md' | sort | while IFS= read -r f; do
            [ -f "$f" ] || continue

            # A path token this repository can resolve. The leading capture
            # keeps ~/.claude/... and /absolute/... from matching, so the
            # injected layer's own paths are not reported; strip that
            # character before testing the path.
            grep -noE '(^|[^~/A-Za-z0-9_.-])(docs|tests|base|squid|global-claude|templates)/[A-Za-z0-9_./-]*[A-Za-z0-9_/-]' "$f" \
            | while IFS=: read -r ln tok; do
                case "$tok" in
                    docs/*|tests/*|base/*|squid/*|global-claude/*|templates/*) path="$tok" ;;
                    *) path="${tok#?}" ;;
                esac
                [ -e "$path" ] || continue
                skip=""
                for pre in $_D9_ALLOWED_PREFIXES; do
                    case "$path" in "${pre}"*) skip=yes ;; esac
                done
                for ex in $_D9_ALLOWED_EXACT; do
                    [ "$path" = "$ex" ] && skip=yes
                done
                while IFS= read -r pair; do
                    [ "${f}:${path}" = "$pair" ] && skip=yes
                done <<EOF
$_D9_ALLOWED_PAIRS
EOF
                [ -n "$skip" ] && continue
                echo "${f}:${ln}: cites '${path}', which exists here and need not exist where this file is read — name the document and project instead (ADR 005)"
            done

            # An ADR number with no project qualifier names this repository's
            # ADR to a reader who has their own.
            #
            # Matched against each line joined with the one after it. A
            # line-by-line match reported "ADR 001 of the / claude-sandbox
            # project" as unqualified, because these documents are wrapped
            # at about 76 columns and the qualifier straddles the break.
            # That form is correct prose, so a check that rejects it would
            # push authors to fight the wrapping convention to satisfy the
            # tool. Found by the negative control, not by review.
            awk -v q="$_D9_QUALIFIER" '
                { line[NR] = $0 }
                END {
                    for (i = 1; i <= NR; i++) {
                        base = line[i]
                        gsub(/[ \t]+/, " ", base)
                        n = length(base)
                        joined = base " " line[i + 1]
                        gsub(/[ \t]+/, " ", joined)
                        rest = joined
                        off = 0
                        while (match(rest, /ADR [0-9][0-9][0-9]/)) {
                            start = off + RSTART
                            num = substr(rest, RSTART, RLENGTH)
                            after = substr(rest, RSTART + RLENGTH, length(q) + 1)
                            if (start <= n && after != " " q)
                                printf "%s:%d: \047%s\047 is unqualified — write \047%s %s\047 (ADR 005)\n", FILENAME, i, num, num, q
                            off = start + RLENGTH - 1
                            rest = substr(rest, RSTART + RLENGTH)
                        }
                    }
                }
            ' "$f"
        done
    )
}

# base/Dockerfile and .github/workflows/ci.yml each pin the bats commit they
# install. CI is the authoritative run and the image is what a session runs
# against, so the two disagreeing means a check can pass in one place and fail
# in the other for a reason neither reports — the drift #118 was filed about,
# one layer up. Nothing else compares them, and a version bump touches two
# files in different languages, which is exactly the edit that gets made once.
#
# Both literals are read out of their own file rather than from a shared
# source: a shared source neither file reads would prove nothing about what is
# actually installed.
_bats_pin_mismatch() {
    (
        cd "$SANDBOX_DIR" || exit 1
        d_commit=$(awk -F= '/^ARG BATS_COMMIT=/ {print $2; exit}' base/Dockerfile)
        d_version=$(awk -F= '/^ARG BATS_VERSION=/ {print $2; exit}' base/Dockerfile)
        c_commit=$(awk -F: '/^ *BATS_COMMIT:/ {gsub(/ /, "", $2); print $2; exit}' .github/workflows/ci.yml)
        c_version=$(awk -F: '/^ *BATS_VERSION:/ {gsub(/ /, "", $2); print $2; exit}' .github/workflows/ci.yml)

        [ -n "$d_commit" ] || echo "base/Dockerfile: no 'ARG BATS_COMMIT=' found"
        [ -n "$c_commit" ] || echo ".github/workflows/ci.yml: no 'BATS_COMMIT:' found"
        [ -n "$d_version" ] || echo "base/Dockerfile: no 'ARG BATS_VERSION=' found"
        [ -n "$c_version" ] || echo ".github/workflows/ci.yml: no 'BATS_VERSION:' found"

        [ -z "$d_commit" ] || [ -z "$c_commit" ] || [ "$d_commit" = "$c_commit" ] \
            || echo "bats commit differs: base/Dockerfile pins ${d_commit}, ci.yml pins ${c_commit}"
        [ -z "$d_version" ] || [ -z "$c_version" ] || [ "$d_version" = "$c_version" ] \
            || echo "bats version differs: base/Dockerfile pins ${d_version}, ci.yml pins ${c_version}"
    )
}

# D-1 checks markdown links only, but most citations of a document in this
# repository are bare paths: start.sh comments, bats file headers, prose in
# backticks. Renaming a document (#105) breaks every one of them silently.
# This check closes that gap for docs/*.md tokens in every tracked file
# outside the global layer — D-9 governs that, and its planning paths are
# target-relative by design — and outside the untracked docs/tmp/.
#
# Some unresolved tokens are deliberate: illustrative examples, or paths a
# design proposed and never created. They are exempt per file and path, as
# in D-9, so each exemption is a judgment that shows up in a diff. A rename
# that moves one of these files must move its entry too. This file is not
# scanned: the list above would report itself.
_D11_ALLOWED_PAIRS="docs/adr/003-where-a-behavioural-rule-goes.md:docs/planning/templates/scope.md
docs/designs/0006-interpreter-presence-health-check.md:docs/AGENTS.md
docs/designs/0006-interpreter-presence-health-check.md:docs/security_plan_changelog.md
docs/designs/0069-planning-skill-output-routing.md:docs/planning/templates/prior-art.md
docs/designs/0069-planning-skill-output-routing.md:docs/planning/templates/scope.md
docs/designs/0069-project-planning-skill.md:docs/plans/2026-09-planning-phase-handoff.md
docs/designs/0012-squid-proxy-integration.md:docs/claude-sandbox-memory.md
docs/designs/0047-user-guide-session-start-check.md:docs/USER_GUIDE.md
docs/designs/0007-workspace-artifact-staleness.md:docs/AGENTS.md
docs/engineering-principles-by-lifecycle-phase.md:docs/angular_commit_convention.md"

_unresolved_doc_paths() {
    (
        cd "$SANDBOX_DIR" || exit 1
        git ls-files | grep -vE '^(global-claude|docs/tmp)/|^tests/test_docs_integrity\.bats$' | while IFS= read -r f; do
            [ -f "$f" ] || continue
            # Same leading-character capture as D-9: keeps ~/... and /abs/...
            # from matching, and is stripped before the path is tested.
            grep -noE '(^|[^~/A-Za-z0-9_.-])docs/[A-Za-z0-9_./-]*\.md' "$f" \
            | while IFS=: read -r ln tok; do
                case "$tok" in
                    docs/*) path="$tok" ;;
                    *) path="${tok#?}" ;;
                esac
                [ -e "$path" ] && continue
                printf '%s\n' "$_D11_ALLOWED_PAIRS" | grep -qxF "${f}:${path}" && continue
                echo "${f}:${ln}: cites '${path}', which does not exist"
            done
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

# bats test_tags=fast, hostonly
@test "D-6: global-claude/CLAUDE.md stays within its line ceiling" {
    run _claude_md_over_ceiling
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- injected into every session; see docs/adr/003 for what earns a line ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "D-7: the global layer as a whole stays within its line ceiling" {
    run _global_layer_over_ceiling
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- every line here is context cost in every session ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "D-8: every skill's description resolves to text" {
    run _skills_without_loadable_description
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- skills whose trigger never reaches context ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "D-9: the global layer cites nothing that exists only in this repository" {
    run _cross_boundary_citations
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- read inside other repositories; see docs/adr/005 ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "D-10: the image and CI pin the same bats commit" {
    run _bats_pin_mismatch
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- a session and the authoritative gate would run different bats ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "D-11: every docs/ path cited outside the global layer resolves" {
    run _unresolved_doc_paths
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        echo "--- a bare path D-1 cannot see; renamed or never created ---" >&2
        echo "$output" >&2
    fi
    [ -z "$output" ]
}
