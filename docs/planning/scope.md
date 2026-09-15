---
status: Approved
date: 2026-09-11
phase: planning
owner: project-planning
---

# Scope

## TL;DR

Fix three silent-failure gaps in `claude-sandbox`'s instruction layer: the host environment this project assumes (#102), how Planning intake records inference and what qualifies for Planning (#103), and citations under `global-claude/` that resolve only inside this repo (#104). None crashes; each fails quietly, which is why they are bundled into one run.

## Problem statement

Anyone operating this sandbox or authoring under `global-claude/` faces three undocumented, non-crashing failure modes:
- `#102`: environment assumptions — memory, cgroups v2 delegation, UID matching, egress, toolchains, `GH_TOKEN`, the driving model's judgment — are scattered, so no operator can tell which tier their host is in. R-6's cgroups incident is the worked example.
- `#103`: the entry gate defends against unanswered questions but not against a plausible misreading of answered ones, and has no principled Planning-vs-Design boundary.
- `#104`: `global-claude/` is injected into every project, but its citations resolve only inside this repo — elsewhere they dangle or silently resolve to the wrong file.

## Constraints

- ADRs are never rewritten — amendments land as new ADRs that supersede or qualify the one they touch (existing project convention, not new).
- Must not break any existing `tests/test_docs_integrity.bats` check (D-1–D-8) or `tests/test_planning_artifacts.bats`.
- No changes to container-security-gated files (`base/Dockerfile`, `base/entrypoint.sh`, `squid/squid.conf`, the `permissions` block in `settings.json`) — that's Case E territory, out of scope for this doc-only bundle.
- Case-based commit-confirmation rules apply per `global-claude/CLAUDE.md` (Case D/E always confirm).
- This sandbox session has no container engine available, so `hostonly`/engine-gated tests can be inspected but not run here — verification against them is deferred.
- Solo-operator capacity, no stated deadline.

## Non-goals

- Building #102's model-tier-enforcement mechanism — the issue defers it; naming the gap is what is in scope.
- Turning any #102 assumption into an entrypoint health check — a separate decision, per the issue's own scoping.
- Implementing #103's ledger or entry test. This run settles the two decisions; building the mechanism is Design work, gated on the charter's Decision.
- A hand audit of every doc for cross-repo-citation bugs beyond `CLAUDE.md:71` — the proposed `D-9` check is meant to catch the rest.
- Resolving ADR 003's broader weakest-rung gap; only the citation-portability instance is in scope.
- Any issue beyond #102, #103 and #104.

## Definition of done

- Planning: all four artifacts exist, pass `tests/test_planning_artifacts.bats`, and the charter's `## Decision` is human-filled.
- If Go: #102 states environment assumptions in Minimal and Ideal tiers; #103's two decisions are recorded as Design resolves them; #104 converts every flagged citation to the qualified form, qualifies ADR 003, and lands `D-9` passing.
- #102, #103 and #104 closed, with the commits that resolved them.
- If No-go or Deferred: the charter records that outcome with reasoning, and no issue is closed — a recorded no-go is itself done.

