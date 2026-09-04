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
| `scope.md` | not yet written | `project-planning` | Problem statement, constraints, explicit non-goals |
| `prior-art.md` | not yet written | `swe-prior-art-research` | Prior art, build-vs-adopt recommendation |
| `feasibility.md` | not yet written | `project-feasibility` | Technical / operational / financial feasibility, risk inventory |
| `charter.md` | not yet written | `project-planning` | Charter and go/no-go decision material |

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

**Ceilings are counted in lines, not sentences.** ADR 002 decision 4 asks
for a TL;DR of at most three sentences. The check counts lines instead,
because splitting prose into sentences is unreliable — abbreviations and
decimals both break it — and a check that misfires gets switched off, which
is worse than a cruder check that holds. Each template declares its own
ceilings as `ceiling-<section>:` keys in its frontmatter, so the numbers
live next to the sections they govern rather than in the test.

Three sentences remains the intent. The line ceiling is the mechanical
proxy for it.
