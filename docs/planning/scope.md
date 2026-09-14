---
status: Approved
date: 2026-09-11
phase: planning
owner: project-planning
---

# Scope

## TL;DR

Fix three documentation gaps in `claude-sandbox`'s instruction layer (`global-claude/`), surfaced while prepping `project-planning`'s first real run: state the minimal vs. ideal host environment this project assumes (#102), decide how Planning-phase scope intake records inference and what actually qualifies for Planning (#103), and make `global-claude/`'s cross-repo citations resolve correctly wherever they're injected (#104). All three are currently silent-failure risks rather than crashes — undocumented assumptions, an approval gate with no teeth against misread constraints, and citations that resolve to a wrong file instead of erroring — which is why bundling them into one Planning run is worth doing now rather than fixing each ad hoc.

## Problem statement

Anyone operating this sandbox or authoring under `global-claude/` works against an instruction layer with three undocumented, silent (not crashing) failure modes:
- `#102`: environment assumptions (memory/CPU, cgroups v2 delegation, UID matching, egress allowlist, baked-in toolchains, GH_TOKEN, whether judgment rules hold under the driving model) are scattered, so no operator can tell which tier — minimal or ideal — their host is in. R-6's cgroups incident is the worked example.
- `#103`: the entry/approval gate defends against unanswered questions but not against a plausible misreading of answered ones, and has no principled Planning-vs-Design boundary.
- `#104`: `global-claude/` is injected into every project this sandbox touches, but its citations resolve only inside this repo — elsewhere they dangle or silently resolve to the wrong file.

Solved means each gap gets a documented, checkable answer instead of an implicit one.

## Constraints

- ADRs are never rewritten — amendments land as new ADRs that supersede or qualify the one they touch (existing project convention, not new).
- Must not break any existing `tests/test_docs_integrity.bats` check (D-1–D-8) or `tests/test_planning_artifacts.bats`.
- No changes to container-security-gated files (`base/Dockerfile`, `base/entrypoint.sh`, `squid/squid.conf`, the `permissions` block in `settings.json`) — that's Case E territory, out of scope for this doc-only bundle.
- Case-based commit-confirmation rules apply per `global-claude/CLAUDE.md` (Case D/E always confirm).
- This sandbox session has no container engine available, so `hostonly`/engine-gated tests can be inspected but not run here — verification against them is deferred.
- Solo-operator capacity, no stated deadline.

## Non-goals

- Building #102's model-tier-enforcement mechanism (whether the instruction layer's rules hold under a given model) — the issue defers this; only naming the gap is in scope.
- Turning any single #102 assumption into an entrypoint health check — a separate decision, per the issue's own scoping.
- Actually implementing #103's ledger/entry-test mechanism inside `project-planning`'s SKILL.md or ADR 004 — this Planning run settles the two decisions; building the mechanism (if adopted) is Design-phase work, gated on the charter's Decision.
- A full manual audit of every doc in the repo for cross-repo-citation bugs beyond the confirmed `CLAUDE.md:71` instance — the proposed `D-9` static check is meant to catch the rest automatically, not a hand audit.
- Resolving ADR 003's broader "weakest rung" enforcement gap (rung-1/rung-2 checks failing silently) — only the citation-portability instance is in scope here.
- Expanding this Planning run to any issue beyond #102/#103/#104.

## Definition of done

- Planning: `scope.md`, `prior-art.md`, `feasibility.md`, `charter.md` all exist under `docs/planning/`, pass `tests/test_planning_artifacts.bats`, and the charter's `## Decision` is filled in by a human.
- If Go: #102 → BUILDING.md (or a linked doc) states environment assumptions in Minimal/Ideal tiers; #103 → both decisions are recorded in `project-planning`'s SKILL.md/ADR 004 as Design resolves them; #104 → `CLAUDE.md:71` (and any other flagged instance) uses the name-by-document-and-project form, ADR 003 is qualified, and `D-9` in `tests/test_docs_integrity.bats` passes.
- Each of #102/#103/#104 closed on GitHub, referencing the commit(s) that resolved it.
- If No-go or Deferred: the charter records that outcome with reasoning, and no issue is closed prematurely — a recorded no-go is itself the done condition.

