---
status: Approved
date: 2026-10-24
phase: planning
owner: project-feasibility
---

# Feasibility

## TL;DR

Grounding D-7 in what
`docs/planning/0128-global-layer-line-ceiling/prior-art.md §Build vs adopt`
names is buildable with the checks that exist today, and small. The hard
part is not code. One of the three limits, the description listing budget,
depends on things the repository cannot see, so any figure for it stays a
policy choice.

## Technical

Every limit prior-art names can be checked host-only, in the shape of the
D-6 and D-7 checks already in `tests/test_docs_integrity.bats`.
- **CLAUDE.md under 200 lines** is D-6 as it stands, so there is nothing
  to build.
- **A per-skill body limit of 500 lines** is a loop over
  `global-claude/skills/*/SKILL.md`. The largest SKILL.md is 339 lines
  today.
- **A total-description bound** can reuse D-8, which already extracts each
  description. The measured 6731 characters come from the same logic.

The weak link is the listing budget. It is 1% of a context window the
repository does not know, and the global layer shares it with plugin and
synced skills it cannot count. A check can bound only this layer's share.
Its number cannot be derived from the vendor rule without assuming a
window size and a characters-per-token ratio
(`docs/planning/0128-global-layer-line-ceiling/prior-art.md §Confidence`).

## Operational

There is one operator, working through agent sessions on this branch
model. The checks are `hostonly`, so `ci.yml` runs them on every PR in
seconds, with no engine and no image rebuild. `bats` is available in the
sandbox, so the checks can be negative-controlled locally, the way D-6 to
D-9 were.

The ongoing cost is tracking the vendor. The 1% budget, the 1,536-character
cap and the 500-line guidance are Claude Code behaviour, versioned and
changed without notice. Someone has to notice when they move. Nothing does
that today, and a pinned figure in a test goes stale silently.

## Financial

The effort is small: a handful of host-only tests and a rewrite of D-7's
rationale comment. That assumes the design chooses per-class checks;
choosing is a non-goal here
(`docs/planning/0128-global-layer-line-ceiling/scope.md §Non-goals`).

The value is that #128 gets decided on evidence rather than by default. At
184 lines of headroom, D-7 is likely to trip on templates and skill bodies,
which cost nothing per session. The lines that do cost every session are
about 5% of what it counts
(148 of 2816: CLAUDE.md plus the description frontmatter).

The opportunity cost is time not spent on #135, which #146's order
already puts after #128, so the cost falls on a path that is already serial.

## Risk inventory

- **The description bound is set from an assumed token ratio.** Mitigation:
  state the assumption at the check and treat the number as policy.
- **The vendor changes the budget or the caps.** Mitigation: cite the docs
  URL and the date checked at each threshold.
- **Dropping the tree-wide count lets on-demand files grow unnoticed.**
  Invoked bodies still cost context. Mitigation: the per-skill body limit,
  plus a decision on whether templates need any bound at all.
- **Hook output is uncounted.** Today it is two lines, printed only when a
  project lacks a user guide. Mitigation: bound it in the hook's own test,
  or record it as accepted.
- **The vendor's 200 and 500 come without published evidence.** Mitigation:
  cite them as vendor guidance, not as research.

## Confidence by dimension

1. **Technical, high.** The checks mirror D-6 to D-8, and the measurements
   were taken on this tree.
2. **Operational, medium.** Building is easy. Tracking the vendor has no
   mechanism and depends on someone remembering to check.
3. **Financial, low to medium.** The effort is small, but the value rests on
   D-7 actually tripping on on-demand files, which is a projection from
   past growth.
