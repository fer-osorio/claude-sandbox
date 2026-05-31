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
