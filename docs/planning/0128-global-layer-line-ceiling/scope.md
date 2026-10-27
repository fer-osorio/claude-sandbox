---
status: Approved
date: 2026-10-24
phase: planning
owner: project-planning
---

# Scope

## TL;DR

Find what developers and researchers have published about how much
always-loaded instruction text an agent can carry before it costs
something. Use that to justify D-7's 3000-line ceiling or replace it. The
number is not assumed wrong; it is assumed unjustified.

## Problem statement

D-7 caps everything under `global-claude/` at 3000 lines. That is 2816 as
of 2026-10-24, against 2793 when #128 opened. Its rationale, in
`tests/test_docs_integrity.bats`, is that every line costs context in
every session. It sets the ceiling "above current usage deliberately" as
a bound on unnoticed growth. Nothing outside the repository supports the
figure. #128's three options (trim, raise, change what is counted) can't be
weighed until the ceiling has a reason. Solved means the ceiling, or its
replacement, rests on cited findings.

## Constraints

Not yet decided.

## Non-goals

- **The trim** (#128 option 1). Deferred, to be discussed after this
  research.
- **Choosing among #128's options, or designing the change.** This run
  produces the evidence a design would cite. The design comes after.

## Definition of done

`prior-art.md` cites published findings on instruction and context size,
and says what they support for D-7: the current number, another number, or
another unit of measure. `feasibility.md` and `charter.md` follow as the
Planning contract requires.
