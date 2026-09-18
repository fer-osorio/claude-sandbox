# Planning artifacts

Index for one Planning run: #102, #103 and #104. One row per artifact: what it is, who writes
it, and whether it is current. A reader looking for one thing reads this
table and then opens one file — that is what the index is for.

The contract these artifacts follow is
[ADR 002](../../adr/002-planning-artifact-contract.md), laid out per bundle
by [ADR 008](../../adr/008-per-bundle-planning-directories.md). This README
does not restate either.

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
