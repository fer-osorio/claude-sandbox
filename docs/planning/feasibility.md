---
status: Approved
date: 2026-09-11
phase: planning
owner: project-feasibility
---

# Feasibility

## TL;DR

Yes, buildable by this solo operator at low-to-moderate cost. #102 and #104 are straightforward documentation/test changes with strong prior art; #103 is the highest-risk item, since it's a decision about the very Planning process being exercised for the first time in this run, with no external precedent for its proposed Planning-vs-Design boundary. Cost is justified: per `docs/planning/scope.md §Problem statement`, all three currently degrade silently, and that risk compounds with every future session or project this instruction layer touches.

## Technical

Nothing here requires new infrastructure, dependencies, or runtime mechanism — `docs/planning/scope.md §Constraints` already excludes container-security files entirely.

- **#102**: trivial. Content-only; the facts to document are independently verifiable (`BUILDING.md`, `start.sh`, `tests/test_runtime_posture.bats`, and the external precedent in `docs/planning/prior-art.md §Findings`). No new mechanism required — `scope.md §Non-goals` excludes building an enforcement check.
- **#103**: buildable, with technical risk concentrated in decision 2. Decision 1 (ledger) has direct precedent (`prior-art.md §Findings`: RAID logs, arXiv:1210.7101) — low-risk once approved. Decision 2 (entry test) has no comparable prior art (`prior-art.md §Findings`); "buildable" here means a document can be written, not that the boundary is proven correct.
- **#104**: buildable. The fix (name-by-document-and-project citation form) is already demonstrated correctly in this repo (`global-claude/templates/planning-index.md`, this very `docs/planning/README.md`'s own ADR 002 citation) — a known-good pattern being generalized, not invented. The proposed static check matches the existing `D-1`/`D-2` idiom in `tests/test_docs_integrity.bats` exactly.

## Operational

Single operator (`scope.md §Constraints`), already working fluently within this repo's ADR/skill/test conventions across this session.

- **#102**: no special access needed to write the doc. This sandbox has no container engine (`scope.md §Constraints`), so firsthand verification of the described *effects* (not the doc itself) is deferred.
- **#103**: largely a judgment call by the operator about their own process — no external dependency, but the highest-stakes item, since it changes how every future Planning run in this repo behaves.
- **#104**: straightforward — grep-scale fix plus one new test. The real operational question is whether the operator wants a new repo-local `/workspace/CLAUDE.md` — a file that becomes an ongoing thing to keep in sync, not a one-time cost.
- No CI/review pipeline beyond the operator's own Case-based commit-confirmation discipline, already in force.

## Financial

Effort and opportunity cost only, per `scope.md §Constraints` ("solo-operator capacity, no stated deadline") — cost is measured in operator attention, not calendar time.

- **#102**: small effort (one doc section or page); low opportunity cost.
- **#103**: small-to-moderate effort for the decisions themselves (this Planning run is most of the cost); a larger, explicitly deferred cost (`scope.md §Non-goals`) if a mechanism is later built.
- **#104**: moderate effort (new ADR, new file, new test, at least one confirmed instance fixed); the bug is self-propagating — every future `global-claude/` file risks repeating it — so delay compounds the cost rather than deferring it.
- Opportunity cost of not doing this: all three are already-identified silent-failure risks (`scope.md §Problem statement`); deferring doesn't remove the risk, only leaves it undocumented longer.

## Risk inventory

- #103 decision 2 is untested prose with no prior art (`prior-art.md §Confidence`) and could be wrong on first use. Mitigation: keep it revisable until exercised by a second real Planning run.
- #104's proposed `/workspace/CLAUDE.md` becomes a second place instructions can drift from `global-claude/CLAUDE.md`. Mitigation: keep it minimal — only genuinely repo-local content.
- Bundling all three into one charter could produce one Go/No-go despite different risk profiles. Mitigation: `scope.md §Definition of done` already requires independent Case classification per issue at Design time.
- No container engine in this sandbox (`scope.md §Constraints`) blocks end-to-end `hostonly` test verification. Mitigation: explicit, documented deferral — already the constraint's own framing.
- #102's model-tier-assumption row has no owner or mechanism (`scope.md §Non-goals`). Mitigation: document it as a named, deferred gap, not an implied promise.
- ADR immutability (`scope.md §Constraints`) requires #103/#104 to land as new, superseding or qualifying ADRs — a pattern this project hasn't yet exercised for a partial (qualifying) amendment. Mitigation: Design phase should confirm the pattern works before assuming it.

## Confidence by dimension

- Technical: high — content-only changes with precedent both in this repo and externally (`prior-art.md §Findings`).
- Operational: high for #102/#104, moderate for #103 — decision 2 is a judgment call with no external validator; buildable is not the same as correct.
- Financial: lowest confidence of the three by nature (mirrors the asymmetry `prior-art.md §Confidence` notes for #103 decision 2 and #104's core mechanism) — effort estimates are the operator's own, unverified against any external benchmark.
- Overall: technical carries this assessment; financial should not be read as equally firm.
