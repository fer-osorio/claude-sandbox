# CLAUDE.md - Global

## Design Workflow
- Before starting any significant change, invoke `/design` to produce a
  design document and wait for approval before writing code

## Git Workflow
- Follow Angular commit convention (see `commit-convention` skill)
- Never commit on `main`; create a branch first
- Do not include "Co-Authored-By" lines in commits
- Avoid command substitution `$()` in commit messages
- Prefer single-file atomic commits; use multi-file commits only when changes are tightly coupled
- Always ask before staging and committing any change

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
