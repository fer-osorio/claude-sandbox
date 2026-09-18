---
template-tier: scaffold
seeded-by: project-planning
unowned-because: project-planning writes a row when it opens a bundle and
  moves Current, and every other Planning skill only reads it, so the file
  is the project's, not one skill's output.
---

<!-- Template for docs/planning/README.md, written once when the Planning
     directory is scaffolded. Copy, then delete these comments.

     Deliberately carries no relative links until a bundle exists, for the
     same reason as the per-bundle index: a link to an unwritten path is a
     dangling reference. -->

# Planning bundles

One directory per Planning run, named `<NNNN>-<slug>` after its tracking
issue. Each carries its own index of artifacts. Exactly one row is
**Current**: the bundle every Planning skill reads and writes. Skills
resolve it here and never infer it from the directory listing (ADR 008 of
the claude-sandbox project).

## Bundles

| Bundle | Current | Issue | Question |
|---|---|---|---|

Opening a bundle adds a row, marks it Current, and unmarks the previous
one. Nothing else changes a row.
