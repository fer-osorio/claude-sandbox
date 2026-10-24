---
status: Approved
date: 2026-10-24
phase: planning
owner: project-planning
---

# Project charter

## TL;DR

The research found no basis for one line count across `global-claude/`.
The vendor sets limits per load class instead. The evidence points toward
#128's third option: replace D-7's tree-wide count with per-class bounds,
taken from vendor guidance and labelled as such.

## Recommendation

Proceed to a design for #128 option 3, with one condition. The bound on
the total length of skill descriptions is written as a policy figure. That
check names its assumed window size and characters-per-token ratio at the
threshold.

What would change this:
- The operator wants a cap on total tree growth for its own sake, apart
  from context cost. Then D-7 stays as a policy number with its rationale
  restated, which is option 2.
- A source turns up that measures adherence against always-loaded size
  for Claude Code specifically.

## Evidence

- D-7's own rationale is the cost paid in every session
  (`docs/planning/0128-global-layer-line-ceiling/scope.md §Problem statement`).
  That is the yardstick for what follows.
- No source supports a tree-wide line count. The vendor limits apply per
  file and per load class
  (`docs/planning/0128-global-layer-line-ceiling/prior-art.md §Findings`).
- D-6's 200 lines matches the vendor's CLAUDE.md guidance (same section).
- The every-session share is about 5% of what D-7 counts
  (`docs/planning/0128-global-layer-line-ceiling/feasibility.md §Financial`).
- Each bound is a host-only check in the shape of D-6 to D-8
  (`docs/planning/0128-global-layer-line-ceiling/feasibility.md §Technical`).
- Against: the vendor's 200 and 500 come with no published evidence, and
  IFScale is one preprint
  (`docs/planning/0128-global-layer-line-ceiling/prior-art.md §Confidence`).
- Against: one study found file size had no effect on adherence, so
  smaller is not shown to be better (`prior-art.md §Findings`).
- Against: dropping the tree-wide count leaves on-demand files bounded
  only per skill
  (`docs/planning/0128-global-layer-line-ceiling/feasibility.md §Risk inventory`).

## Open questions

**Blocking:** none.

**Tolerable, for the design to settle:**
- the description bound's figure and its window assumption (200k or 1M);
- whether templates need any bound at all;
- whether the hook's output is bounded.

**Deferred by scope:** the trim. Shortening descriptions also lowers the
listing share
(`docs/planning/0128-global-layer-line-ceiling/scope.md §Non-goals`).

## Decision

<!-- Left blank by the skill. Filled in by a person, with a date.
     Go / No-go / Deferred, and the reasoning in one or two lines.

     A recorded no-go with its reasoning is the most reusable output this
     phase produces — it stops the same idea being re-proposed from
     scratch in six months. Do not delete this file on a no-go; set its
     status and leave it. -->
