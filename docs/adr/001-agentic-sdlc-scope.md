# ADR 001 — Scope and adoption level for agentic SDLC automation

## Status

Accepted

## Context

`../sdlc_reference_guide.md` describes seven phases staffed by project
managers, business analysts, C-suite sponsors, financial controllers, a
release manager, a change-management team, and training specialists.
claude-sandbox has one operator. The phases are portable; the staffing is
not, and nothing so far has recorded which artifacts in that guide are
load-bearing here and which are ceremony inherited from an organizational
context that does not exist.

A research pass in August 2026 into agentic SDLC prior art found the field
converged on a consistent shape: a single capable agent loop with shell,
file, and test-runner access; human approval at high-impact actions;
persistent memory; and context-isolated subagents only where a task is
genuinely non-trivial. Academic systems that encode the SDLC as multi-agent
role simulation (MetaGPT's Product Manager / Architect / Engineer / QA,
ChatDev's virtual company) are widely cited and not widely shipped. Reported
token cost scales roughly 1× for a chat call, 4× for a tooled single agent,
15× for a multi-agent system.

That research also produced a four-level maturity ladder. A ladder with no
declared stopping point is a roadmap, not a decision: every unbuilt level
becomes an implicit commitment, because silence reads as "not yet."

## Decision

**1. Commit to levels 0 and 1 only.**

| Level | Description | Status |
|---|---|---|
| L0 | Manual session; `design` skill Case A–E routing; approval before code and before commit | In force today |
| L1 | Same control flow, event-triggered — `claude -p` fired by a client signal, phase sequencing still deterministic and ours | Committed target |
| L2 | Orchestrator delegating to context-isolated subagents | Not committed; gated on the trigger below |
| L3 | Parallel fan-out across subagents | Out of scope |

L0 and L1 are both *workflows* rather than agents in the sense that matters
here: the control flow belongs to us, and the model fills in steps.

**2. The L2 trigger, written down so it is checkable.** L2 is reconsidered
when either is observed and recorded in an issue: a single Planning run
measurably exhausts the session's usable context, or two sub-steps must read
large disjoint parts of the repository. Until then L2 stays unbuilt. "It
would be more elegant" is not the trigger.

**3. Phase mapping.** Which reference-guide artifacts are load-bearing for a
single operator, and which are not:

| Phase | Load-bearing here | Not applicable here |
|---|---|---|
| 1 Planning | Feasibility study, risk inventory, project charter, go/no-go | Budget estimate, C-suite sponsorship, financial-controller sign-off |
| 2 Requirements | Problem statement and explicit non-goals, folded into the charter and the SDD | SRS as a separately baselined document, RTM, PO/BA roles |
| 3 Design | `docs/designs/` SDDs and `docs/adr/` ADRs | HLD/LLD split, UI/UX wireframes, DBA and security-engineer sign-off |
| 4 Development | Source, tests, Angular-convention commits | Sprint backlog, tech-lead review gate |
| 5 Testing | The bats suite and the CI gate | Separate QA function, UAT, dedicated performance and penetration testers |
| 6 Deployment | `build.sh` / `start.sh`; images rebuilt locally | Release manager, change management, training materials, rollback runbook — there are no production users |
| 7 Maintenance | GitHub issues, ADR supersession | Incident dashboards, support organization |

**4. Anti-goals.** Deliberately not built, at any level:

- **Autonomous go/no-go.** The agent produces decision *material*; the human
  holds the gate. Automating this makes it easy to rationalize starting
  projects that should not start, which is the most expensive failure in the
  whole cycle.
- **Virtual-company role simulation.** See alternatives below.
- **L3 parallel fan-out**, until L2 exists and demonstrates a bottleneck.

## Consequences

Scope is now bounded and the boundary is checkable rather than a matter of
recollection. The existing `design` and `commit-convention` skills keep
working unchanged — L1 extends them rather than replacing them. Cost stays
near 4× rather than 15×. The approval gate stays human at both ends.

Against that: L1 means an agent begins work without a human present at the
start, so the approval gate moves entirely to the end of a run — worth
watching, because a gate at only one end catches less than a gate at both.
The phase mapping is a judgment recorded at one point in time. Declaring L3
out of scope guarantees some genuinely parallelizable work will run
sequentially, and that is accepted.

This ADR assumes a single operator. If the project gains collaborators, the
mapping in decision 3 stops being valid and this ADR should be superseded
rather than quietly reinterpreted.

## Alternatives considered

**Chose:** a bounded L0→L1 ladder with a written L2 trigger.
**Rejected:** MetaGPT/ChatDev-style multi-agent role simulation.
**Why the rejected option is attractive:** it maps one-to-one onto the
reference guide's role list, so the organizational chart becomes the
architecture with no translation step — the design appears to write itself.
**What breaks if you try it anyway:** the roles are precisely the part of
the guide that does not apply to a single operator, so the mapping is to a
fiction; the ~15× token cost buys parallelism this workload does not have;
and the systems that pioneered it are cited far more often than they are
run in production.

**Chose:** declare an explicit stopping point and an explicit trigger.
**Rejected:** leave the ladder open-ended.
**Why the rejected option is attractive:** it costs nothing to write, keeps
every option open, and avoids committing to a boundary that might later look
wrong.
**What breaks if you try it anyway:** scope then grows by default rather
than by decision. An unstated boundary cannot be violated, so it cannot be
enforced, and each level gets built because it is next rather than because
it is needed.

**Chose:** keep `sdlc_reference_guide.md` as-is and record the mapping here.
**Rejected:** rewrite the guide to fit a single operator.
**Why the rejected option is attractive:** a guide with nothing inapplicable
in it is faster to read and harder to misapply.
**What breaks if you try it anyway:** the guide is portable reference shared
with other projects; forking it here produces two copies that drift. The
phases are the general part and the mapping is the project-specific part —
editing the general document to encode a local decision puts the knowledge
in the wrong place.

## References

- [`sdlc_reference_guide.md`](../sdlc_reference_guide.md) — phase vocabulary and artifact lists
- [`engineering-principles-by-lifecycle-phase.md`](../engineering-principles-by-lifecycle-phase.md) — "name your anti-goals", "prefer narrowing to accumulating"
- [`docs-as-code-workflow.md`](../designs/docs-as-code-workflow.md) — Case A–E routing this decision preserves
