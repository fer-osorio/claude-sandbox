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
# P-0c and P-1's two branches were negative-controlled on 2026-09-15, when
# TEMPLATE_DIR widened to cover both tiers (ADR 007 decision 2). Each probe
# was applied to a committed template and reverted:
#   - template-tier: scafold  -> P-0c reported the unrecognised value.
#   - owner: deleted from a contract template -> P-1's contract branch.
#   - owner: and a ceiling key added to a scaffold -> P-1's scaffold branch
#     reported both as belonging to a contract template.
#   - seeded-by: no-such-skill -> P-7 reported it, which is the half of P-7
#     that did not exist before the widening.
#
# The first attempt at those four controls reported nothing, for all four.
# The harness had not exported TEMPLATE_DIR, so _templates found no files
# and every check passed over an empty set. That is P-0's failure mode
# exactly, met in the harness rather than the suite, and it is the reason
# P-0c asserts each tier is non-empty rather than trusting that a branch
# with nothing in it would be noticed.
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
# docs/designs/0069-planning-skill-output-routing.md §Decision 1. This path is
# load-bearing — an empty TEMPLATE_DIR makes P-1, P-3, P-5 and P-6 pass over
# nothing rather than fail, so P-0 asserts the set is non-empty.
#
# It covers every template in the injected layer, not only planning/, per
# ADR 007 decision 2. Before that, global-claude/templates/*.md was reached
# by no check at all: a template could be added there and never be seen,
# which is P-0's own failure mode occurring in a directory P-0 did not
# watch.
TEMPLATE_DIR="${SANDBOX_DIR}/global-claude/templates"

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

# One directory per Planning run (ADR 008). Artifacts are the *.md files in
# each bundle, excluding its index. Templates live in the global layer (see
# TEMPLATE_DIR above) and are never artifacts.
_bundles() {
    find "$PLANNING_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

_artifacts() {
    find "$PLANNING_DIR" -mindepth 2 -maxdepth 2 -name '*.md' ! -name 'README.md' 2>/dev/null | sort
}

# A template's artifact: is "<bundle>/<name>.md"; an artifact matches it on
# <name>.md, since every bundle carries the same fixed names.
_template_for() {
    for t in $(_templates_of_tier contract); do
        [ "$(basename "$(_fm_value "$t" artifact)")" = "$(basename "$1")" ] && echo "$t"
    done
}

_templates() {
    find "$TEMPLATE_DIR" -maxdepth 2 -name '*.md' 2>/dev/null | sort
}

# ADR 007 decision 1 names two tiers. A contract template governs one
# artifact at one path with one owning skill and measurable sections; a
# scaffold is copied once and then owned by the project.
_TEMPLATE_TIERS="contract scaffold"

# Templates of one tier. Selection is on the declared value, never on
# whether some other key happened to be absent: keying the tier on a
# missing artifact: would let a typo demote a contract template, after
# which P-1, P-4, P-5 and P-7 would all pass over it.
_templates_of_tier() {
    for t in $(_templates); do
        [ "$(_fm_value "$t" template-tier)" = "$1" ] && echo "$t"
    done
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

# Every declared ceiling, as "<section> <limit>" pairs. Contract templates
# only — a scaffold declares none, by ADR 007 decision 1.
_ceiling_keys() {
    for t in $(_templates_of_tier contract); do
        _frontmatter "$t" | sed -n 's/^ceiling-\([a-z0-9-]*\)-words:[[:space:]]*\([0-9]*\)/\1 \2/p'
    done
}

# An undeclared or unrecognised tier is a failure, never a demotion to the
# laxer tier. A convention whose lax tier is the default erodes without
# anything turning red.
_p0c_bad_tiers() {
    for t in $(_templates); do
        rel="${t#${SANDBOX_DIR}/}"
        tier="$(_fm_value "$t" template-tier)"
        case " ${_TEMPLATE_TIERS} " in
            *" ${tier} "*) ;;
            *) echo "${rel}: template-tier is '${tier}' — expected one of: ${_TEMPLATE_TIERS}" ;;
        esac
    done
}

_p1_templates_missing_declarations() {
    for t in $(_templates_of_tier contract); do
        rel="${t#${SANDBOX_DIR}/}"
        [ -n "$(_fm_value "$t" artifact)" ] || echo "${rel}: no 'artifact:' in frontmatter"
        [ -n "$(_fm_value "$t" owner)" ]    || echo "${rel}: no 'owner:' in frontmatter"
        _frontmatter "$t" | grep -q '^ceiling-' \
            || echo "${rel}: declares no ceiling-* keys, so nothing constrains its sections"
    done
    # A scaffold carrying contract keys is miscategorised, not half-checked.
    for t in $(_templates_of_tier scaffold); do
        rel="${t#${SANDBOX_DIR}/}"
        [ -n "$(_fm_value "$t" seeded-by)" ] \
            || echo "${rel}: no 'seeded-by:' in frontmatter"
        [ -n "$(_fm_value "$t" unowned-because)" ] \
            || echo "${rel}: no 'unowned-because:' — a scaffold states why no skill owns its output"
        for k in artifact owner; do
            [ -z "$(_fm_value "$t" "$k")" ] \
                || echo "${rel}: declares '${k}:', which belongs to a contract template"
        done
        _frontmatter "$t" | grep -q '^ceiling-' \
            && echo "${rel}: declares ceiling-* keys, which belong to a contract template"
    done
    return 0
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
    for b in $(_bundles); do
        index="${b}/README.md"
        brel="${b#${SANDBOX_DIR}/}"
        # Every artifact name a template claims, plus every artifact that
        # exists in this bundle.
        { for t in $(_templates_of_tier contract); do basename "$(_fm_value "$t" artifact)"; done
          for a in "$b"/*.md; do [ -e "$a" ] && basename "$a"; done
        } | grep -vx 'README.md' | sort -u | while IFS= read -r name; do
            [ -n "$name" ] || continue
            [ -f "$index" ] && grep -q "$name" "$index" \
                || echo "${brel}/${name}: no row in ${brel}/README.md"
        done
    done
}

# ADR 008 decision 2: the top-level index lists every bundle and marks
# exactly one Current, and that one exists. A stale or missing pointer is
# the new state ADR 008 introduced, so it is checked rather than trusted.
_p9_bad_current_bundle() {
    index="${PLANNING_DIR}/README.md"
    [ -d "$PLANNING_DIR" ] || return 0
    [ -f "$index" ] || { echo "docs/planning/README.md: missing"; return 0; }
    current="$(grep -F '**Current**' "$index" | grep -oE '[0-9]{4}-[a-z0-9-]+' | sort -u)"
    n="$(printf '%s' "$current" | grep -c .)"
    [ "$n" -eq 1 ] || echo "docs/planning/README.md: ${n} bundles marked Current — expected exactly one"
    for c in $current; do
        [ -d "${PLANNING_DIR}/${c}" ] || echo "docs/planning/README.md: Current names '${c}', which is not a directory"
    done
    for b in $(_bundles); do
        grep -qF "$(basename "$b")" "$index" \
            || echo "docs/planning/$(basename "$b"): no row in docs/planning/README.md"
    done
}

_p4_ceiling_violations() {
    for a in $(_artifacts); do
        rel="${a#${SANDBOX_DIR}/}"
        for t in $(_template_for "$a"); do
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
    for t in $(_templates_of_tier contract); do _fm_value "$t" artifact; done \
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

# Both tiers: a contract template names its writer in owner:, a scaffold
# names the skill(s) that copy it in seeded-by:. Every template therefore
# declares at least one skill that must resolve, which is what closes "a
# template nobody reads".
#
# seeded-by may name more than one skill, space-separated, since #47 gave
# the user-guide template a second seeder (user-guide-check) alongside
# design. owner stays single-valued — a contract template has exactly one
# writer — but the loop below runs once for it either way, so one code path
# covers both without weakening owner's cardinality.
_p7_missing_owner_skills() {
    for t in $(_templates); do
        rel="${t#${SANDBOX_DIR}/}"
        case "$(_fm_value "$t" template-tier)" in
            scaffold) key=seeded-by ;;
            *)        key=owner ;;
        esac
        value="$(_fm_value "$t" "$key")"
        # A missing key is P-1's finding, not this one's.
        [ -n "$value" ] || continue
        for owner in $value; do
            case " ${_UNBUILT_OWNERS} " in
                *" ${owner} "*) continue ;;
            esac
            [ -f "${SANDBOX_DIR}/global-claude/skills/${owner}/SKILL.md" ] \
                || echo "${rel}: ${key} '${owner}' names no skill at global-claude/skills/${owner}/SKILL.md"
        done
    done
}

_p6_dead_ceiling_keys() {
    for t in $(_templates_of_tier contract); do
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
        rel="${a#${SANDBOX_DIR}/}"
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
        echo "P-0c, P-1, P-3, P-5, P-6 and P-7 iterate over this set. An empty" >&2
        echo "set makes them all pass while asserting nothing, so the contract" >&2
        echo "would report green with no templates behind it. Check TEMPLATE_DIR." >&2
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
@test "P-0c: every template declares a recognised tier, and neither tier is empty" {
    run _p0c_bad_tiers
    [ "$status" -eq 0 ]
    _report "$output" "templates with no recognised template-tier"
    [ -z "$output" ]

    for tier in $_TEMPLATE_TIERS; do
        run _templates_of_tier "$tier"
        if [ -z "$output" ]; then
            echo "--- no '${tier}' templates under ${TEMPLATE_DIR} ---" >&2
            echo "P-1 branches on the tier, so an empty branch asserts nothing" >&2
            echo "while reporting green — P-0's failure mode, per tier." >&2
        fi
        [ -n "$output" ]
    done
}

# bats test_tags=fast, hostonly
@test "P-1: every template declares what its tier requires" {
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

# bats test_tags=fast, hostonly
@test "P-9: the bundle index names exactly one existing Current bundle" {
    run _p9_bad_current_bundle
    [ "$status" -eq 0 ]
    _report "$output" "bundle index out of step with docs/planning/"
    [ -z "$output" ]
}
