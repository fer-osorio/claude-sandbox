# CLAUDE.md - Global

## Design Workflow
- Before starting any significant change, invoke `/design` to produce a
  design document and wait for approval before writing code

## Git Workflow
- Follow Angular commit convention (see `commit-convention` skill)
- Never commit on `main`; create a branch first
- Do not include tool-generated attribution trailers in commits
- Avoid command substitution `$()` in commit messages
- One logical change per commit
- Case A and B: commit without asking
- Case C: commit without asking when that individual commit would qualify
  as Case A or B on its own; confirm for the design-document commit and
  the closing commit
- Case D and E: always confirm, however small the change looks
- Committing without asking never extends to pushing, opening PRs, or
  creating issues
- See docs/designs/docs-as-code-workflow.md §4 for case selection

## Output discipline
- Spend length only on what the diff or a linked document cannot carry;
  restating a linked document is not earned length
  (docs/engineering-principles-by-lifecycle-phase.md §Part I.4)
- Default to Markdown for prose deliverables. A richer format — HTML, a
  published page — is earned when Markdown cannot carry the content
  (interaction, charts, layout), or when it was asked for

## Interpreter discipline
- Before creating a venv or any build artifact in /workspace, verify the
  interpreter or toolchain version is already baked into the image
  (check the relevant Dockerfile), not installed ephemerally via
  Strategy B (docker exec -u root).
- If the needed version isn't in the image, stop and tell the operator
  to rebuild via Strategy A rather than installing it ephemerally and
  building a persistent artifact against it.
- If entrypoint logs a "broken interpreter reference" warning at session
  start, treat it as a signal to rebuild the venv before proceeding with
  any task that depends on it.
- Note: the entrypoint check only scans .venv directories up to three
  levels below /workspace (maxdepth 3). A venv nested more deeply than
  that is not inspected — apply this policy uniformly regardless of
  nesting depth.
