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
# mean today: no artifact has been written yet, so P-2 and P-4 currently
# have nothing to iterate over and pass trivially. P-1, P-3, P-5 and P-6
# all assert against the four committed templates and carry real weight
# now. P-2 and P-4 bind automatically the first time a skill writes to
# docs/planning/ — no edit to this file required, which is the property
# worth having.
#
# What this suite deliberately does NOT catch:
#   - Whether an owner named in a template is a skill that actually
#     exists. project-feasibility and project-planning are specified by
#     ADR 002 and not yet built, so asserting existence today would fail
#     on purpose-built absence. Tighten this once Phase 3 and 4 land;
#     tests/test_docs_integrity.bats D-2 already does the equivalent for
#     the global layer.
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
TEMPLATE_DIR="${PLANNING_DIR}/templates"

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

# Artifacts are docs/planning/*.md excluding the index. Templates live one
# level down and are never artifacts.
_artifacts() {
    find "$PLANNING_DIR" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | sort
}

_templates() {
    find "$TEMPLATE_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | sort
}

# Non-blank, non-comment body lines under a "## <heading>" whose slug
# matches $2, up to the next "## " or end of file. The heading itself is
# not counted.
_section_lines() {
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
        { n++ }
        END { print n + 0 }
    ' "$1"
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
            _frontmatter "$t" | sed -n 's/^ceiling-\([a-z0-9-]*\):[[:space:]]*\([0-9]*\)/\1 \2/p' \
            | while read -r section limit; do
                actual="$(_section_lines "$a" "$section")"
                [ "$actual" -le "$limit" ] \
                    || echo "${rel}: section '${section}' is ${actual} lines, ceiling is ${limit}"
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

_p6_dead_ceiling_keys() {
    for t in $(_templates); do
        rel="${t#${SANDBOX_DIR}/}"
        _frontmatter "$t" | sed -n 's/^ceiling-\([a-z0-9-]*\):.*/\1/p' | while IFS= read -r key; do
            found=""
            while IFS= read -r heading; do
                [ "$(_slug "$heading")" = "$key" ] && found=yes
            done < <(grep '^## ' "$t" | sed 's/^## //')
            [ -n "$found" ] || echo "${rel}: ceiling-${key} names no '## ' section in this template"
        done
    done
}

_report() {
    if [ -n "$1" ]; then
        echo "--- $2 ---" >&2
        echo "$1" >&2
    fi
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
