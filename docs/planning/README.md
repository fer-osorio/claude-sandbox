# Planning artifacts

Index for the Planning phase. One row per artifact: what it is, who writes
it, and whether it is current. A reader looking for one thing reads this
table and then opens one file — that is what the index is for.

The contract these artifacts follow is
[ADR 002](../adr/002-planning-artifact-contract.md). This README does not
restate it; it records the two implementation choices ADR 002 left open,
and nothing else.

## Index

| Artifact | Status | Owner | Contains |
|---|---|---|---|
| [`scope.md`](scope.md) | Approved | `project-planning` | Problem statement, constraints, explicit non-goals |
| [`prior-art.md`](prior-art.md) | Approved | `swe-prior-art-research` | Prior art, build-vs-adopt recommendation |
| [`feasibility.md`](feasibility.md) | Approved | `project-feasibility` | Technical / operational / financial feasibility, risk inventory |
| [`charter.md`](charter.md) | Approved | `project-planning` | Charter and go/no-go decision material |

Every skill that writes an artifact updates its own row here, and only its
own row. `tests/test_planning_artifacts.bats` fails if an artifact exists
without one.

Artifact names are code spans rather than links until the file exists — a
markdown link to an unwritten artifact is a dangling reference, and D-1 in
`tests/test_docs_integrity.bats` fails on it. The skill that writes an
artifact turns its own name into a link at the same time it fills in the
status.

## Two choices ADR 002 left open

**Templates live in the global layer, artifacts live here.** ADR 002
decision 5 requires templates to be files rather than advice inside a
SKILL.md, but does not say where they go. They are at
`global-claude/templates/planning/`, reaching a session as
`~/.claude/templates/planning/<artifact>.md`, because the skills that
follow them are injected into every project while this directory is
per-project. See
[`planning-skill-output-routing.md`](../designs/planning-skill-output-routing.md)
§Decision 1 for why, and §Consequences for what that costs.

Artifact paths are unchanged — decision 2 specifies them and only the
authoring inputs moved.

**Ceilings are counted in words, not sentences or lines.** ADR 002
decision 4 asks for a TL;DR of at most three sentences. Splitting prose
into sentences is unreliable — abbreviations and decimals both break it —
and a check that misfires gets switched off, so the check counts something
mechanical instead.

It counted physical lines until the first real run, which was written as
unwrapped paragraphs. Every section passed; the same text wrapped at this
repository's 76 columns breached thirteen of twenty ceilings. Lines measure
how an author wrapped the prose, not how much of it there is. The ceilings
were converted at nine words per line — the measured density of this
repository's wrapped prose — which reproduces the line-based verdict on
nineteen of the twenty sections.

Each template declares its own ceilings as `ceiling-<section>-words:` keys
in its frontmatter, so the numbers live next to the sections they govern
rather than in the test. Three sentences remains the intent; the word
ceiling is the mechanical proxy for it.
