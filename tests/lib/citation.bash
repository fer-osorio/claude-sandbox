# lib/citation.bash — citation resolution, per ADR 010 of this repository.
#
# A citation is `path §Section`. ADR 010 decision 1 makes validity a question
# of resolution rather than spelling: path resolves against the citing
# document's own directory first, then the repository root, and §Section must
# match a heading in the resolved document. Decision 2 makes the section half
# load-bearing — a path that resolves while its section lives elsewhere is a
# failed citation, not a stylistic one.
#
# Engine-free on purpose, and it must stay that way. Every caller runs in the
# host-only CI selection; a dependency on a container engine here would gate
# each caller's setup() and drop all of them out of that selection at once,
# which is the failure #81 produced and the placement rule in the testing SDD
# §6.2 exists to prevent.
#
# Two limits, stated rather than left to be discovered:
#
#   - Matching is line-based, so a citation hard wrapped across a newline
#     inside its backticks is invisible here. No committed citation is in
#     that state; a check that cannot see something should say so.
#   - A document that quotes a dead citation to discuss it — ADR 010 does
#     exactly that — is indistinguishable from one that makes the citation.
#     Callers exempt those by file, as D-11 already does.

# Regex-escape, so a section whose text carries a metacharacter is matched
# literally. "TL;DR" is harmless; a "." in a heading would otherwise match
# any character and make the check quietly permissive.
_citation_re_escape() {
    printf '%s' "$1" | sed 's/[][\.*^$(){}?+|/]/\\&/g'
}

# One pattern, named once. The path must end in .md, which is what keeps
# ordinary code spans out: `echo $KEY` and `start.sh:235` are not citations.
_CITATION_RE='`[A-Za-z0-9_./-]+\.md[^`]*§[^`]+`'

# Every `path §Section` on stdin, as "line<TAB>path<TAB>section".
#
# Stdin rather than a filename so that one tokenizer serves both callers: a
# whole document, where the line numbers are real and get reported, and a
# single section piped in, where only the paths matter.
citation_tokens() {
    grep -noE "$_CITATION_RE" \
    | while IFS=: read -r ln tok; do
        tok="${tok#\`}"
        tok="${tok%\`}"
        printf '%s\t%s\t%s\n' \
            "$ln" \
            "$(printf '%s' "${tok%%§*}" | sed 's/[[:space:]]*$//')" \
            "$(printf '%s' "${tok#*§}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    done
}

# The file a citation of $2, written in document $1, resolves to. Echoes
# nothing when it resolves nowhere.
#
# Document directory first, then the repository root, per ADR 010 decision 1.
# The order is the decision: it is what makes a bare sibling correct inside a
# planning bundle without making it correct anywhere else.
citation_target() {
    local dir
    dir="$(dirname "$1")"
    if [ -f "${dir}/$2" ]; then
        printf '%s\n' "${dir}/$2"
    elif [ -f "${SANDBOX_DIR:?citation_target needs SANDBOX_DIR}/$2" ]; then
        printf '%s\n' "${SANDBOX_DIR}/$2"
    fi
}

# True when $2 names a heading in document $1.
#
# Two accepted forms, because both are in use. A section is cited by its
# heading text ("§Technical" against "## Technical"), or by its number
# ("§4" against "## 4. Introduction", "§2.1" against "### 2.1 Overview") —
# the numbered form is how the docs-as-code workflow document is cited, and
# a matcher that took only heading text would report that citation as broken.
citation_section_exists() {
    local sect
    sect="$(_citation_re_escape "$2")"
    grep -qE "^#{1,6}[[:space:]]+${sect}[[:space:]]*\$" "$1" && return 0
    case "$2" in
        [0-9]*) grep -qE "^#{1,6}[[:space:]]+${sect}[.[:space:]]" "$1" && return 0 ;;
    esac
    return 1
}

# Every citation in $1 that does not resolve, as one finding per line.
# Callers add their own prefix; this says only what is wrong.
citation_defects() {
    local doc="$1" ln path sect target
    citation_tokens < "$doc" | while IFS="$(printf '\t')" read -r ln path sect; do
        target="$(citation_target "$doc" "$path")"
        if [ -z "$target" ]; then
            echo "${doc}:${ln}: cites '${path}', which resolves neither beside the document nor at the repository root"
        elif ! citation_section_exists "$target" "$sect"; then
            echo "${doc}:${ln}: cites '${path} §${sect}', and that document has no such section"
        fi
    done
}
