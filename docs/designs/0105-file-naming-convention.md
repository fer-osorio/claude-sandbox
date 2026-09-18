# File Naming Convention for Documentation

## Status
Draft

## Context

Issue #105 asks that a documentation filename be mechanically resolvable
both ways, from topic to file and from file to topic, and free of
collisions. The tree today follows three schemes: kebab-case slugs in
`docs/designs/`, `<YYYY-MM>-` in `docs/plans/`, and snake_case at the top
of `docs/`.

Prior art, researched 2026-09-18:

- **Sequential numbers collide.** A sequence is a central allocator, and
  parallel branches draw from it independently. Git then merges two
  `0189-*.md` files without conflict, because their names differ. log4brains
  dropped required numbering for this reason ("avoids git merge issues").
- **An external allocator does not collide.** Kubernetes KEPs and Rust RFCs
  prefix the tracking issue or PR number. The prefix is unique by
  construction, and it leads back to the discussion.
- **One directory per proposal.** Each KEP is a directory, and that is the
  shape `docs/planning/` lacks. It holds one slot per artifact, so a second
  Planning run overwrites the first. That was observed on 2026-09-18, when
  a prior-art pass for this issue would have replaced the #102–#104
  artifact.

Two in-repo constraints were checked. Lines ~120–123 of
[ADR 002](../adr/002-planning-artifact-contract.md) reject naming *as a
substitute for the index*, which leaves naming as such open.
`auto-memory-seeding.md` §4.1 ("Do not encode a filename convention") is
scoped to memory topic files. Neither constraint blocks this change.

## Decision

`<NNNN>` is the tracking issue number, zero-padded to four digits. A
document with no issue uses the number of the PR that introduced it.
Issues and PRs share one GitHub number space, so the prefix stays
collision-free. Several documents may share an `NNNN`. The full filename is
the identity.

| Series | Form |
|---|---|
| Design documents | `docs/designs/<NNNN>-<slug>.md` |
| Implementation plans | `docs/plans/<NNNN>-<slug>-v<N>.md` |
| Planning bundles | `docs/planning/<NNNN>-<slug>/`, fixed artifact names inside; see ADR 008 |
| ADRs | unchanged: `docs/adr/<NNN>-<slug>.md` |
| Reference documents (not a series) | `docs/<slug>.md`, no prefix |

Every slug is lowercase kebab-case. Case-insensitive host filesystems
(Windows, and macOS by default) make case-only differences a collision
risk, which rules out camelCase.

**Exempt:**

- ADRs, whose number is their citable identity. The global layer cites
  them as "ADR 00N of the claude-sandbox project" in other repositories.
- Fixed-path contract documents the global layer cites target-relatively in
  every project (`docs/designs/docs-as-code-workflow.md`).
- `docs/tmp/`, which is untracked scratch.

**Existing files are renamed.** Each `NNNN` is taken from the introducing
commit's issue reference, or else from the PR that merged it. All eight
design documents without an issue arrived through a PR. `git log --follow`
preserves their history.

**Enforced by:**

- D-11: every `docs/` path cited in a tracked file outside the global layer
  resolves. This covers the bare-path citations in `start.sh` and in test
  comments, which D-1 does not see.
- D-12: names conform, and no two ADRs share a number.

## Consequences

- Name a new document once its issue exists. The number is known before
  the file is, so placing the file takes no lookup, and neither does
  finding it from its issue.
- Chronology becomes approximate, because issue numbers follow when an
  issue was opened, not when its document was written. Accepted.
- GitHub blob URLs to old paths in past issue and PR bodies stop resolving.
  The history itself is intact.
- ADR numbering remains a sequence, so it can still collide. D-12 turns a
  silent collision into a failing check. It does not prevent the collision.

## Alternatives considered

**`YYYYMMDD-<slug>`.** Needs no issue, derives from git for every existing
file, and sorts chronologically. Rejected because it leads nowhere: the
filename alone gives no way back to the discussion. The issue-or-PR rule
already covers documents without an issue.

**A scope token (`<prefix>-<scope>-<slug>`).** More searchable by area.
Rejected because the scope vocabulary has to be fixed or it drifts, and the
directory already carries most of the scope.

**Renaming ADRs into the same scheme.** Uniform, but every "ADR 00N"
citation breaks silently, here and in every project's copy of the global
layer.

**Leaving existing files alone.** Zero churn, but two schemes would then
coexist indefinitely, which is the problem #105 was opened for.

## Implementation plan

1. `docs: design for file naming convention (#105)` — this document.
2. `docs: ADR 008 — per-bundle planning directories (#105)`.
3. `test(docs): D-11 — every docs/ path cited in a tracked file resolves`.
4. `refactor(docs): rename design docs and plans to <NNNN>-<slug> (#105)`.
   Waits on PR #125.
5. `refactor(docs): kebab-case the reference docs (#105)`.
6. `feat(planning): per-bundle planning directories (#105)`, per ADR 008.
7. `test(docs): D-12 — naming conformance and ADR number uniqueness`.
8. `docs: record naming convention in workflow doc (closes #105)`.
