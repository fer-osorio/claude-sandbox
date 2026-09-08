<!-- Template for docs/planning/README.md, written once when the
     Planning directory is scaffolded. Copy, then delete these comments.

     Deliberately carries no relative links. This file is written into an
     arbitrary project, where the paths this sandbox uses for its own ADRs
     and designs do not exist. Name a document; do not link to it. -->

# Planning artifacts

Index for the Planning phase. One row per artifact: what it is, who writes
it, and whether it is current. A reader looking for one thing reads this
table and then opens one file — that is what the index is for.

The contract these artifacts follow is ADR 002 of the sandbox project,
which assigns each path exactly one owner. This file records the rows and
the two rules that govern them, and nothing else.

## Index

| Artifact | Status | Owner | Contains |
|---|---|---|---|
| `scope.md` | not yet written | `project-planning` | Problem statement, constraints, explicit non-goals |
| `prior-art.md` | not yet written | `swe-prior-art-research` | Prior art, build-vs-adopt recommendation |
| `feasibility.md` | not yet written | `project-feasibility` | Technical / operational / financial feasibility, risk inventory |
| `charter.md` | not yet written | `project-planning` | Charter and go/no-go decision material |

Every skill that writes an artifact updates its own row here, and only its
own row. The table above is created once, with every row in its initial
state; after that a skill touches one cell pair and leaves the rest alone.

Artifact names are code spans rather than links until the file exists — a
markdown link to an unwritten artifact is a dangling reference, and a link
checker fails on it. The skill that writes an artifact turns its own name
into a link at the same time it fills in the status.
