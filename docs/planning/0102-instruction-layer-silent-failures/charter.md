---
status: Approved
date: 2026-09-11
phase: planning
owner: project-planning
---

# Project charter

## TL;DR

Proposal: fix three silent-failure gaps in `claude-sandbox`'s instruction layer — #102 (environment assumptions), #103 (Planning-entry semantics), #104 (citation portability) — as this Planning skill's first real run. The evidence points toward proceeding: all three are low-risk and well-precedented except #103 decision 2, a judgment call with no external validator, attached as a condition below.

## Recommendation

Proceed, with one named condition.

- Proceed with #102 and #104 unqualified — `docs/planning/0102-instruction-layer-silent-failures/feasibility.md §Technical` and `§Operational` rate them high-confidence and low-effort, with prior art (`docs/planning/0102-instruction-layer-silent-failures/prior-art.md §Build vs adopt`).
- Proceed with #103 decision 1 (ledger) — `feasibility.md §Technical` calls it low-risk; precedent solid (`prior-art.md §Findings`).
- Proceed with #103 decision 2 (entry test) as revisable, not load-bearing — `feasibility.md §Risk inventory`'s own mitigation, since `prior-art.md §Confidence` found no precedent.
- Named condition: if Design finds decision 2's entry test conflicts with ADR 004 decision 5 in practice, not just in #103's abstract argument, that is grounds to stop and revisit — not to proceed anyway.

## Evidence

- `docs/planning/0102-instruction-layer-silent-failures/scope.md §Problem statement` — all three are identified, silent-failure risks, not hypothetical.
- `feasibility.md §Technical` — none require new infrastructure or touch container-security files; #102 and #104 low-risk.
- `prior-art.md §Findings` — #102's cgroups gap traces to an unresolved upstream regression, which raises priority.
- `prior-art.md §Findings` — #103 decision 1 and #104's citation fix have convergent external precedent (RAID logs, arXiv:1210.7101, the AGENTS.md ecosystem).
- `feasibility.md §Financial` — deferral cost compounds: #104's bug is self-propagating, and #102/#103 stay undocumented meanwhile.
- Contradicting — `prior-art.md §Confidence`: #103 decision 2 and #104's core failure mode have no direct precedent; `feasibility.md §Technical`'s "buildable" does not mean "correct."
- Contradicting — `prior-art.md §Findings` flags the monorepo AGENTS.md scope-per-subtree pattern as a genuine alternative to #104's citation-form fix, not merely support for it.
- Contradicting — `feasibility.md §Risk inventory`: bundling three risk profiles into one Go/No-go; `scope.md §Definition of done` commits to independent Case classification at Design as the mitigation.
- Caution — `feasibility.md §Operational` and `scope.md §Constraints`: no container engine here, so `hostonly` verification is deferred, not completed.

## Open questions

- Not blocking: whether #104's repo-local `/workspace/CLAUDE.md` is right versus the citation-form rule and `D-9` alone — `prior-art.md §Findings` flags file-scoping as a worth-weighing alternative.
- Not blocking: #103's final Case (C, or escalating to D) — deferred to Design per ADR 004 decision 5 and `scope.md §Non-goals`.
- Not blocking: whether `D-9` is still the free ID in `tests/test_docs_integrity.bats` when #104 reaches implementation.
- Not blocking: #102's model-tier row has no path to resolution (`scope.md §Non-goals`) and stays an open gap regardless.
- Blocking, per the named condition: whether #103 decision 2 conflicts with ADR 004 decision 5 once examined at Design.

## Decision

Go

Agreed with the recommendations.

2026-09-11

