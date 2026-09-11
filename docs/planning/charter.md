---
status: Approved
date: 2026-09-11
phase: planning
owner: project-planning
---

# Project charter

## TL;DR

Proposal: fix three silent-failure documentation/governance gaps in `claude-sandbox`'s instruction layer — #102 (environment assumptions), #103 (Planning-entry semantics), #104 (cross-repo citation portability) — as the first real run of this Planning skill. The evidence points toward proceeding: all three are technically low-risk and well-precedented, except #103 decision 2, which is a genuine judgment call with no external validator. The Recommendation below names that as the one condition worth attaching.

## Recommendation

Proceed, with one named condition.

- Proceed with #102 and #104 without qualification — `docs/planning/feasibility.md §Technical` and `§Operational` both rate them high-confidence, low-effort, with direct prior art (`docs/planning/prior-art.md §Build vs adopt`).
- Proceed with #103 decision 1 (ledger) — `feasibility.md §Technical` calls it low-risk once approved; precedent is solid (`prior-art.md §Findings`).
- Proceed with #103 decision 2 (entry test) as a revisable decision, not a load-bearing one — `feasibility.md §Risk inventory`'s own mitigation, since `prior-art.md §Confidence` found no external precedent for it at all.
- Named condition: if Design-phase analysis finds decision 2's entry test actually conflicts with ADR 004 decision 5 in practice (not just in the abstract argument #103 makes), that is grounds to stop and revisit before implementing it — not to proceed anyway.

## Evidence

- `docs/planning/scope.md §Problem statement` — all three issues are already-identified, currently silent-failure risks, not hypothetical ones.
- `feasibility.md §Technical` — none require new infrastructure or touch container-security files; #102 and #104 rated low-risk.
- `prior-art.md §Findings` — #102's WSL2/cgroups gap traces to a documented, currently-unresolved upstream regression, which raises rather than lowers priority.
- `prior-art.md §Findings` — #103 decision 1 and #104's citation-form fix both have direct, convergent external precedent (RAID logs plus arXiv:1210.7101; the AGENTS.md ecosystem's shared-file practice).
- `feasibility.md §Financial` — opportunity cost of deferring is real and compounding: #104's bug is self-propagating, #102/#103's risks stay undocumented longer the longer this waits.
- Contradicting/caution — `prior-art.md §Confidence`: #103 decision 2 and #104's core failure mode have no direct precedent; `feasibility.md §Technical`'s "buildable" does not mean "correct."
- Contradicting/caution — `prior-art.md §Findings` flags the monorepo AGENTS.md "scope each file to its own subtree" pattern as a genuine alternative to #104's proposed citation-form fix, not merely supporting evidence for it.
- Contradicting/caution — `feasibility.md §Risk inventory`: bundling all three into one charter risks collapsing three different risk profiles into one Go/No-go; `scope.md §Definition of done` commits to independent Case classification at Design time as the stated mitigation.
- Caution — `feasibility.md §Operational` and `scope.md §Constraints` both note this sandbox has no container engine, so `hostonly` test verification is deferred, not completed, by this charter.

## Open questions

- Not blocking: whether #104's proposed repo-local `/workspace/CLAUDE.md` is the right mechanism versus relying on the citation-form rule and `D-9` check alone — `prior-art.md §Findings` flags file-scoping (the monorepo AGENTS.md pattern) as a worth-weighing alternative at Design time.
- Not blocking: #103's exact final Case (C, or escalating to D) — explicitly deferred to Design per ADR 004 decision 5 and `scope.md §Non-goals`.
- Not blocking: whether `D-9` is still the free ID in `tests/test_docs_integrity.bats` by the time #104 reaches implementation, since other `D-` tests could land first.
- Not blocking: #102's "model tier" assumption row has no proposed path to resolution (`scope.md §Non-goals`) and will remain a named, open gap regardless of this charter's outcome.
- Blocking, per Recommendation's named condition: whether #103 decision 2 actually conflicts with ADR 004 decision 5 once examined at Design time, rather than only in the abstract argument #103 makes.

## Decision

Go

Agreed with the recommendations.

2026-09-11

