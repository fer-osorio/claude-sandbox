#!/usr/bin/env bats
# test_planning_artifacts.bats — Group: Planning Artifact Contract
#
# The enforcement named in docs/adr/002-planning-artifact-contract.md
# decision 7. That ADR's rules 1-6 are prose, which is rung 2 of the
# enforcement ladder — a rule nothing can fail is a rule that stops holding
# the first time it is inconvenient. These checks are what stop that from
# being the default outcome.
#
# No engine daemon is required, so every test here is tagged hostonly and
# runs in CI (see BUILDING.md, "Tag axes").
#
# Vacuity, stated plainly because it matters for how much these results
# mean: P-2 and P-4 had nothing to iterate over until the first real
# Planning run landed four artifacts under docs/planning/ on 2026-09-11.
# They bound automatically at that moment, with no edit to this file, which
# is the property worth having. Both now carry weight, as P-1, P-3, P-5 and
# P-6 already did against the committed templates.
#
# What binding revealed about P-4 is recorded in #106 finding 1. It counted
# physical lines, and lines are a property of how the author wrapped the
# prose: the run's artifacts were unwrapped, so all twenty sections passed
# while thirteen breached once wrapped at this repository's 76 columns. A
# check can bind and still measure the wrong thing. The unit is now words —
# see _section_words below, and docs/planning/README.md for the conversion.
#
# All six were negative-controlled on 2026-09-04, each observed reporting
# against a deliberately broken fixture, before the templates moved to the
# global layer. P-2 and P-4 are the two that had never been seen to fail
# before that date; naming them rather than counting them is the point,
# since a count does not tell a later reader which results rest on the
# thinnest evidence.
#
# P-7 was negative-controlled separately, after the move: emptying
# _UNBUILT_OWNERS makes it report exactly the two project-planning
# templates. That is what shows the exemption list is load-bearing rather
# than decorative — the check widens to all four owners the moment the list
# empties, so it has to be the list doing the work and not the absence of a
# skill. Repeat that control when Phase 4 empties it for real.
#
# P-0b, P-4, P-6 and P-8 were negative-controlled on 2026-09-14, when the
# ceiling unit changed and P-8 was added:
#   - P-4 reported "section 'open-questions' is 179 words, ceiling is 108"
#     against a padded charter, and went silent on revert.
#   - P-6 reported a ceiling-nosuchsection-words key naming no section, and
#     went silent on revert. Its parser changed with the rename, so the
#     control is against the new pattern, not the old result.
#   - P-0b's key set went to zero against an empty template directory —
#     the same shape as a template the parser no longer matches, which is
#     the failure it exists for.
#   - P-8 reported the committed charter with its date stripped, went
#     silent on revert, and read the template's comment-only Decision as
#     unfilled. That last one is the control that matters: it is the
#     difference between keying on a filled section and keying on status.
#
# What that verification proves is bounded by how it was performed. bats is
# not in the sandbox image (BUILDING.md, "Running the test suite"), so from
# inside a session the helper functions below can be extracted and called
# directly. That exercises the awk and sed logic and nothing else — not the
# bats wiring, not the tags, not the reporting. Any claim that a check
# actually fires comes from a host run or from CI on a pushed branch, never
# from a session alone.
#
# P-0 exists because every check that reads the template set — P-1, P-3,
# P-5, P-6 and P-7 — degrades to silence rather than to failure. Every one
# of them iterates over that set, and an empty set is reported as a pass —
# so a mistyped TEMPLATE_DIR turns the whole group green while asserting
# nothing. This was not hypothetical: moving the templates without moving
# the pointer produced exactly that, six passes over zero templates.
# ci.yml guards --filter-tags the same way and for the same reason.
#
# P-0b is the same guard one level down, and the rename from ceiling-* to
# ceiling-*-words is why it exists. P-4 iterates over the ceiling keys it
# parses out of each template; a template the parser no longer matches
# yields none, and P-4 then passes over nothing. P-0 would not catch it,
# because the template set is still non-empty.
#
# What this suite deliberately does NOT catch:
#   - Whether an owner that does exist is the skill that actually fires.
#     P-7 resolves a path; nothing asserts that a feasibility question
#     routes to project-feasibility rather than to
#     swe-prior-art-research. That exclusion is prose in two
#     descriptions, and its failure mode is silent.
#   - Whether a skill honours path ownership at write time. P-5 checks
#     that the ownership table is unambiguous, not that anyone obeys it.
#   - Whether a citation points at a section that exists. D-1 in
#     test_docs_integrity.bats resolves the file; nothing resolves the
#     "§Section" part.
#   - Sentence counts. ADR 002 asks for a three-sentence TL;DR; the
#     ceiling is counted in lines instead. Sentence splitting breaks on
#     abbreviations and decimals, and a check that misfires gets switched
#     off, which is worse than a cruder check that holds. See
#     docs/planning/README.md.

SANDBOX_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
PLANNING_DIR="${SANDBOX_DIR}/docs/planning"
# Templates live in the injected global layer, not beside the artifacts they
# govern: the skills that follow them are global and reach every project,
# while docs/planning/ is per-project. See
# docs/designs/planning-skill-output-routing.md §Decision 1. This path is
# load-bearing — an empty TEMPLATE_DIR makes P-1, P-3, P-5 and P-6 pass over
# nothing rather than fail, so P-0 asserts the set is non-empty.
TEMPLATE_DIR="${SANDBOX_DIR}/global-claude/templates/planning"

# Heading text to ceiling-key slug: lowercase, drop anything that is not a
# letter, digit or space, then spaces to hyphens. "TL;DR" -> tldr,
# "Risk inventory" -> risk-inventory.
_slug() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9 -]//g; s/  */-/g; s/^-//; s/-$//'
}

# Frontmatter is the block between the first two --- lines.
_frontmatter() {
    awk 'NR==1 && $0=="---" {inb=1; next} inb && $0=="---" {exit} inb {print}' "$1"
}

_fm_value() {
    _frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1
}

# Artifacts are docs/planning/*.md excluding the index. Templates live in
# the global layer (see TEMPLATE_DIR above) and are never artifacts.
_artifacts() {
    find "$PLANNING_DIR" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | sort
}

_templates() {
    find "$TEMPLATE_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | sort
}

# Non-blank, non-comment body lines under a "## <heading>" whose slug
# matches $2, up to the next "## " or end of file. The heading itself is
# not emitted. Authoring comments are skipped, so a section carrying only
# the template's instructions comes back empty — which is what lets P-8
# tell an unfilled Decision from a filled one.
_section_body() {
    awk -v want="$2" '
        /^## / {
            body = tolower(substr($0, 4))
            gsub(/[^a-z0-9 -]/, "", body)
            gsub(/ +/, "-", body)
            sub(/^-/, "", body); sub(/-$/, "", body)
            insec = (body == want)
            next
        }
        !insec { next }
        /<!--/ { incomment = 1 }
        incomment { if (/-->/) incomment = 0; next }
        /^[[:space:]]*$/ { next }
        { print }
    ' "$1"
}

# Words in that body.
#
# Words rather than physical lines. Lines are a property of how the author
# wrapped the prose, not of how much they wrote: the first real run was
# written unwrapped and every section passed, while the same text hard
# wrapped at this repository's 76 columns breached thirteen of twenty
# ceilings. A unit that answers differently depending on where the newlines
# fell is not measuring the thing the ceiling exists to bound.
#
# A table row counts its cell contents, so a table spends budget faster per
# visual line than prose does. No ceilinged section currently prescribes
# one.
_section_words() {
    _section_body "$1" "$2" | awk '{ n += NF } END { print n + 0 }'
}

# Every declared ceiling, as "<section> <limit>" pairs across all templates.
_ceiling_keys() {
    for t in $(_templates); do
        _frontmatter "$t" | sed -n 's/^ceiling-\([a-z0-9-]*\)-words:[[:space:]]*\([0-9]*\)/\1 \2/p'
    done
}

_p1_templates_missing_declarations() {
    for t in $(_templates); do
        rel="${t#${SANDBOX_DIR}/}"
        [ -n "$(_fm_value "$t" artifact)" ] || echo "${rel}: no 'artifact:' in frontmatter"
        [ -n "$(_fm_value "$t" owner)" ]    || echo "${rel}: no 'owner:' in frontmatter"
        _frontmatter "$t" | grep -q '^ceiling-' \
            || echo "${rel}: declares no ceiling-* keys, so nothing constrains its sections"
    done
}

_p2_invalid_status() {
    for a in $(_artifacts); do
        rel="${a#${SANDBOX_DIR}/}"
        status="$(_fm_value "$a" status)"
        case "$status" in
            Draft|Approved|"Superseded by "*) ;;
            *) echo "${rel}: status is '${status}' — expected Draft, Approved, or 'Superseded by <path>'" ;;
        esac
    done
}

_p3_missing_index_rows() {
    index="${PLANNING_DIR}/README.md"
    # Every artifact path a template claims, plus every artifact that exists.
    { for t in $(_templates); do _fm_value "$t" artifact; done
      for a in $(_artifacts); do echo "docs/planning/$(basename "$a")"; done
    } | sort -u | while IFS= read -r path; do
        [ -n "$path" ] || continue
        grep -q "$(basename "$path")" "$index" \
            || echo "${path}: no row in docs/planning/README.md"
    done
}

_p4_ceiling_violations() {
    for a in $(_artifacts); do
        rel="docs/planning/$(basename "$a")"
        for t in $(_templates); do
            [ "$(_fm_value "$t" artifact)" = "$rel" ] || continue
            _frontmatter "$t" | sed -n 's/^ceiling-\([a-z0-9-]*\)-words:[[:space:]]*\([0-9]*\)/\1 \2/p' \
            | while read -r section limit; do
                actual="$(_section_words "$a" "$section")"
                [ "$actual" -le "$limit" ] \
                    || echo "${rel}: section '${section}' is ${actual} words, ceiling is ${limit}"
            done
        done
    done
}

_p5_duplicate_owners() {
    for t in $(_templates); do _fm_value "$t" artifact; done \
    | sort | uniq -d | while IFS= read -r dup; do
        [ -n "$dup" ] && echo "${dup}: claimed by more than one template — ownership must be unambiguous"
    done
}

# Owners ADR 002 specifies that are not built yet. Asserting their
# existence would fail on purpose-built absence, so they are exempt — but
# as data rather than as a sentence in a comment, so the exemption shrinks
# visibly and P-7 covers every owner the moment the list empties, with no
# edit to the check itself.
#
# The list is now empty. project-planning landed in Phase 4 of #69, so P-7
# resolves all four template owners rather than two. That widening is the
# observable worth checking after this change — not the exit status, which
# was green while the exemption still covered scope.md and charter.md. The
# mechanism stays for the next owner ADR 002 names before it is built.
_UNBUILT_OWNERS=""

_p7_missing_owner_skills() {
    for t in $(_templates); do
        rel="${t#${SANDBOX_DIR}/}"
        owner="$(_fm_value "$t" owner)"
        # A missing owner: key is P-1's finding, not this one's.
        [ -n "$owner" ] || continue
        case " ${_UNBUILT_OWNERS} " in
            *" ${owner} "*) continue ;;
        esac
        [ -f "${SANDBOX_DIR}/global-claude/skills/${owner}/SKILL.md" ] \
            || echo "${rel}: owner '${owner}' names no skill at global-claude/skills/${owner}/SKILL.md"
    done
}

_p6_dead_ceiling_keys() {
    for t in $(_templates); do
        rel="${t#${SANDBOX_DIR}/}"
        _frontmatter "$t" | sed -n 's/^ceiling-\([a-z0-9-]*\)-words:.*/\1/p' | while IFS= read -r key; do
            found=""
            while IFS= read -r heading; do
                [ "$(_slug "$heading")" = "$key" ] && found=yes
            done < <(grep '^## ' "$t" | sed 's/^## //')
            [ -n "$found" ] || echo "${rel}: ceiling-${key}-words names no '## ' section in this template"
        done
    done
}

# The charter template asks for the Decision to be "filled in by a person,
# with a date". The first real Decision was written without one and passed
# every check; the date was added afterwards, on request.
#
# Keyed on the section being filled, not on status: Approved. A charter is
# Approved the moment the writing skill finishes it, with the Decision
# legitimately still blank — ADR 002 decision 3's vocabulary records
# document lifecycle, and ADR 004 decision 7 is explicit that a no-go
# charter is Approved too. A check keyed on status would therefore fail on
# every correctly written charter, and a check that fails on correct input
# gets switched off.
#
# This cannot compel a person to decide. It requires only that a decision
# they made can be placed in time against the artifacts it was made on.
_p8_undated_decisions() {
    for a in $(_artifacts); do
        rel="docs/planning/$(basename "$a")"
        body="$(_section_body "$a" decision)"
        [ -n "$body" ] || continue
        printf '%s\n' "$body" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
            || echo "${rel}: '## Decision' is filled in but carries no ISO date"
    done
}

_report() {
    if [ -n "$1" ]; then
        echo "--- $2 ---" >&2
        echo "$1" >&2
    fi
}

# bats test_tags=fast, hostonly
@test "P-0: the template set is not empty" {
    run _templates
    [ "$status" -eq 0 ]
    if [ -z "$output" ]; then
        echo "--- no templates under ${TEMPLATE_DIR} ---" >&2
        echo "P-1, P-3, P-5 and P-6 iterate over this set. An empty set makes" >&2
        echo "all four pass while asserting nothing, so the contract would" >&2
        echo "report green with no templates behind it. Check TEMPLATE_DIR." >&2
    fi
    [ -n "$output" ]
}

# bats test_tags=fast, hostonly
@test "P-0b: the ceiling set is not empty" {
    run _ceiling_keys
    [ "$status" -eq 0 ]
    if [ -z "$output" ]; then
        echo "--- no ceiling-*-words keys under ${TEMPLATE_DIR} ---" >&2
        echo "P-4 iterates over the keys it finds in each template. A template" >&2
        echo "the parser no longer matches yields no ceilings, and P-4 passes" >&2
        echo "over nothing — green with no ceiling behind it. That is P-0's" >&2
        echo "failure one level down, and the key was renamed from ceiling-*" >&2
        echo "to ceiling-*-words when the unit changed from lines to words." >&2
    fi
    [ -n "$output" ]
}

# bats test_tags=fast, hostonly
@test "P-1: every template declares an artifact path, an owner, and ceilings" {
    run _p1_templates_missing_declarations
    [ "$status" -eq 0 ]
    _report "$output" "templates missing declarations"
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "P-2: every planning artifact carries a valid status" {
    run _p2_invalid_status
    [ "$status" -eq 0 ]
    _report "$output" "artifacts with an invalid status"
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "P-3: every artifact path has a row in the index" {
    run _p3_missing_index_rows
    [ "$status" -eq 0 ]
    _report "$output" "artifact paths missing from the index"
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "P-4: no artifact section exceeds its template's ceiling" {
    run _p4_ceiling_violations
    [ "$status" -eq 0 ]
    _report "$output" "sections over ceiling"
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "P-5: no artifact path is claimed by more than one template" {
    run _p5_duplicate_owners
    [ "$status" -eq 0 ]
    _report "$output" "artifact paths with ambiguous ownership"
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "P-6: every declared ceiling names a section that exists" {
    run _p6_dead_ceiling_keys
    [ "$status" -eq 0 ]
    _report "$output" "ceiling keys naming no section"
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "P-7: every template owner outside the exemption list resolves to a skill" {
    run _p7_missing_owner_skills
    [ "$status" -eq 0 ]
    _report "$output" "owners naming no committed skill"
    [ -z "$output" ]
}

# bats test_tags=fast, hostonly
@test "P-8: a filled Decision section carries a date" {
    run _p8_undated_decisions
    [ "$status" -eq 0 ]
    _report "$output" "decisions with no date"
    [ -z "$output" ]
}
