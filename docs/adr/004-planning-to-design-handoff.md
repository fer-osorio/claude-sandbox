# ADR 004 — Planning-to-Design handoff and gate placement

## Status

Accepted

## Context

[ADR 002](002-planning-artifact-contract.md) specifies handoff *between*
Planning sub-skills — file-based, one owner per path, under
`docs/planning/`. It says nothing about the boundary at the end of the
phase. [ADR 001](001-agentic-sdlc-scope.md) states that the existing
`design` and `commit-convention` skills keep working unchanged and that L1
extends rather than replaces them, which bounds the blast radius without
defining the interface.

[`design`](../../global-claude/skills/design/SKILL.md) Steps 1–3 still
assume a human arrives with a change in mind and classifies it
interactively. Nothing tells it a charter exists, where to find it, or
whether an approved charter pre-determines the case.

Four further questions turn out to be the same question. ADR 001 flags
against itself, in its own Consequences, that under L1 *"the approval gate
moves entirely to the end of a run — worth watching, because a gate at only
one end catches less than a gate at both."* Whether the orchestrator stops
between steps, whether scope-intake can run headless, where the second
approval gate sits, and what a no-go terminates into are four views of one
decision: **where the human sits in an event-triggered run.** Settling them
in four documents produces four documents that have to agree.

One asymmetry drives most of what follows. `design`, `project-feasibility`
and the future `project-planning` orchestrator all live in the injected
global layer and are present in every repository the sandbox is pointed at,
while `docs/planning/` is per-project. A rule that assumes the directory
exists does not fail loudly where it does not — it invents. Phase 2 of #69
was reclassified Case A → Case C on exactly that discovery, and
[`planning-skill-output-routing.md`](../designs/planning-skill-output-routing.md)
§Decision 2 settled the general form: presence of `docs/planning/` is the
opt-in signal.

## Decision

**1. Gates at both ends of an L1 run.** A human authors and approves
`docs/planning/scope.md` before a run starts, and fills the charter's
Decision section after it ends. Everything between those two points is
headless. This is the organizing rule; decisions 2–4 are its mechanics.

ADR 001's worry was that L1 moves the gate to one end. It does not have to.
The entry gate is not a prompt the agent waits at — it is an artifact that
must already exist for the run to be legitimate at all.

**2. Scope-intake always requires a human.** The orchestrator does not
derive a problem statement, constraints or non-goals from conversation, and
refuses to run headless without `docs/planning/scope.md`. An L1 run enters
the sequence at prior-art, with `scope.md` supplied as input.

This is the input contract `project-feasibility` already enforces, applied
one step earlier and for the same recorded reason: a verdict measured
against invented constraints is indistinguishable, in the finished
artifact, from one measured against given ones. Intake is where the
non-goals are set, so an invented `scope.md` yields a run that researches
its own invention and declares it feasible — internally coherent, with
nothing signalling the fabricated premise.

**3. The orchestrator runs straight through, and stops early only on a
disqualifying finding.** No stop between steps in the normal case. A step
whose own written artifact contradicts continuing stops the run.

This is not an addition. ADR 002 Consequences already promises that a
disqualifying prior-art finding stops the run with partial output still
readable; a bare run-to-completion policy would silently break an accepted
ADR. An early stop **writes its artifact and updates the index row** rather
than discarding output — the resumability half of that promise is what the
written artifact carries.

**4. `charter.md` is an optional input to `design`, gated on
`docs/planning/` existing.** `design` reads it when the directory is
present and behaves exactly as it does today when it is not — the same
found / not-found shape Step 1 already uses for
`docs/designs/docs-as-code-workflow.md`, and the same opt-in signal as
routing §Decision 2.

Where the charter is read, ADR 002 decision 6 governs how: `design` cites
`docs/planning/charter.md §<section>` and builds on it. It does not restate
it, and it does not re-derive a problem statement that `scope.md` already
holds.

**5. The charter informs classification without determining it.** `design`
Step 2 runs its decision tree independently. The charter supplies
constraints and non-goals the tree operates *on*; it does not assign a
Case, and no Case recorded in a charter binds Step 2.

The reason is timing, not authority. Step 2 asks whether a change crosses
module boundaries and how reversible it is. Those are Design-phase facts. A
charter written at Planning time cannot know them, so a Case assigned there
is assigned on strictly less information.

**6. Two independent approval gates at the phase boundary.** Charter
approval ends Planning. The `design` skill's Step 7 approval still gates
Design separately. Neither is waived by the other.

They answer different questions — *should this exist* versus *is this
design right* — and approving the first is not evidence for the second.
This decision changes nothing operationally; it records that the sequencing
is deliberate, so that a later reading does not treat the second gate as
redundant and remove it.

**7. `status` records document lifecycle, not decision outcome.** A no-go
charter carries `status: Approved` — the document is final and correct —
with the no-go itself in the human-filled Decision section. A later charter
may supersede it via `Superseded by <path>`, so a recorded no-go is
reopenable rather than terminal.

ADR 002 decision 3 admits `Draft`, `Approved` and `Superseded by <path>`,
and nothing else. Keeping outcome out of that field means the vocabulary is
unchanged and P-2 in `tests/test_planning_artifacts.bats` needs no edit.

**8. Phase 4 delivers the orchestrator skill only.** L1's trigger — `claude
-p` fired by a client signal — is tracked as its own work item, #82, opened
with this ADR rather than when it is scheduled.

A trigger with no orchestrator has nothing to fire, so the dependency is
strict. But ADR 001 line 38 calls L1 the *committed target* while nothing
in the tree implements or tracks it, and that is the open-ended-ladder
failure ADR 001 argues against in its own alternatives: silence reads as
"not yet", and an unstated commitment cannot be enforced. Tracking it is
separable from scheduling it, and costs nothing.

## Consequences

The boundary is now an interface rather than an operator habit. Design
cites Planning's output instead of re-deriving it, which is ADR 002
decision 6 extended one step further than ADR 002 reached.

ADR 001's one-ended-gate worry is answered rather than accepted. Under
decisions 1–3 an L1 run is bracketed by two human judgments and supervised
at neither end during execution, which is a stronger position than the
end-only gate ADR 001 anticipated — and it costs no interactivity, because
the entry gate is an artifact rather than a prompt.

Against that:

**Decision 4 is rung-2 enforcement.** Nothing asserts that `design`
actually reads a charter that exists. It is prose in a SKILL.md, and prose
is where [ADR 003](003-where-a-behavioural-rule-goes.md) puts the weakest
carriers. This joins the known gap that nothing asserts the *right* skill
fires at all, tracked on #69, rather than being a new gap this ADR creates.

**Decision 3 makes step sequence semantically load-bearing.** An early stop
depends on which step found the disqualifying result, and nothing asserts
the orchestrator runs its steps in order. P-7 resolves that a template's
`owner:` names a committed skill; it says nothing about sequence. That is a
real gap, recorded here rather than assumed covered.

**Decision 2 means L1 is not end-to-end.** A run cannot begin from a bare
idea. Some class of automation people expect from "event-triggered
planning" is deliberately not available, and the operator writes `scope.md`
by hand or in an interactive L0 session first.

**Decision 6 keeps two gates in a workflow trending headless.** They
bracket different phases, so a single run still stops once — but an
operator moving from charter to implementation stops twice, and the second
stop will sometimes feel redundant. It is not, and decision 6 exists so
that judgment is made against a written reason rather than in the moment.

**Decision 8 leaves L1 unbuilt.** The committed target stays committed and
unimplemented; what changes is that it is now visible, as #82.

Decisions 4 and 5 assume `design` keeps its current Step 1–3 structure. A
future rewrite of that skill inherits an input contract specified here, and
this ADR is where that contract is recorded rather than in the skill.

## Alternatives considered

**Chose:** `charter.md` as an optional input, gated on `docs/planning/`.
**Rejected:** a required input, cited by path in the `design` skill.
**Why the rejected option is attractive:** it is the only form that
guarantees the charter is read, and an optional input is exactly the kind
of rule that quietly stops holding.
**What breaks if you try it anyway:** `design` is injected into every
repository, and `docs/planning/` is per-project. A hard citation to a path
that does not exist does not stop the run — the skill invents a substitute,
which is the failure mode routing §Decision 2 was written to remove and the
reason Phase 2 was reclassified Case A → Case C.

**Chose:** the charter informs classification without determining it.
**Rejected:** the charter assigns the Case, and `design` skips Step 2.
**Why the rejected option is attractive:** one classification instead of
two, decided when the project is being scoped, by whoever knows most about
why the work is being proposed at all.
**What breaks if you try it anyway:** it creates a second classifier that
can disagree with the first, and it classifies Design-phase facts — module
boundaries, reversibility — from Planning-phase information. The charter's
Decision section is also human-filled by ADR 001's anti-goal, so a Case
recorded there is either another field for the operator to fill or a
model-authored judgment in the one section reserved from the model.

**Chose:** two independent approval gates.
**Rejected:** collapse to one — charter approval clears Design's Step 7.
**Why the rejected option is attractive:** one human decision instead of
two, which is the direction the whole L0 → L1 ladder is heading, and the
second gate genuinely does sometimes ask a question the first already
answered.
**What breaks if you try it anyway:** implementing it means adding a
conditional bypass to Step 7 — currently the only approval gate that exists
anywhere in the workflow — so the change spends the project's strongest
enforcement point to save one confirmation.

**Chose:** scope-intake always requires a human.
**Rejected:** two modes — interactive intake in a session, generated intake
when headless.
**Why the rejected option is attractive:** it is the only option under
which L1 delivers what "event-triggered planning" sounds like: a signal
arrives and a charter comes out, with no human in the loop until the
decision.
**What breaks if you try it anyway:** the generated path invents the
constraints that every later step measures against, and produces an
artifact indistinguishable from a well-founded one — the input contract
`project-feasibility` already declines. It also doubles the control flow of
the orchestrator's first step, in the mode that is hardest to observe:
`bats` is not in the sandbox image, so headless behaviour is verified least.

**Chose:** `status` stays lifecycle; the no-go lives in the Decision
section.
**Rejected:** add a `No-go` value to the `status` vocabulary.
**Why the rejected option is attractive:** a reader sees the outcome in
frontmatter without opening the body, which is precisely what ADR 002
decision 3 says the field is for.
**What breaks if you try it anyway:** the field then carries two orthogonal
axes, and a no-go that is later revisited has no way to express both its
outcome and its supersession. It also widens the valid set that P-2 checks —
a check negative-controlled for the first time on 2026-09-04 — to buy a
convenience the Decision section already provides.

**Chose:** the orchestrator runs straight through, with a conditional early
stop.
**Rejected:** stop between every step for human review.
**Why the rejected option is attractive:** maximum oversight, a gate at
every artifact boundary, and no run can go far wrong before someone sees
it.
**What breaks if you try it anyway:** it is incompatible with L1 by
construction. Under `claude -p` there is nobody to resume from a mid-run
stop, so the orchestrator would be permanently L0-only and ADR 001's
committed target could never be reached through it.

**Chose:** Phase 4 delivers the orchestrator skill only.
**Rejected:** Phase 4 delivers the orchestrator and the L1 trigger.
**Why the rejected option is attractive:** it closes the gap between ADR
001's committed target and the tree in one phase, rather than leaving a
commitment visible and unmet.
**What breaks if you try it anyway:** one phase then delivers both a skill
and a change to how sessions are invoked — two logical changes, one of
which is an execution-environment concern with its own failure modes, while
Phase 4 already carries four unsettled mechanics of its own.

## References

- [ADR 001](001-agentic-sdlc-scope.md) — the L1 commitment, the autonomous
  go/no-go anti-goal, and the one-ended-gate consequence this ADR answers
- [ADR 002](002-planning-artifact-contract.md) — the intra-phase contract
  this extends past the phase boundary; decisions 3 and 6, and the
  stop-early promise in its Consequences
- [ADR 003](003-where-a-behavioural-rule-goes.md) — the enforcement ladder
  that makes decision 4 rung 2
- [`design/SKILL.md`](../../global-claude/skills/design/SKILL.md) — Steps
  1–3 and Step 7, the entry path and gate decisions 4–6 constrain
- [`docs-as-code-workflow.md`](../designs/docs-as-code-workflow.md) —
  Case A–E routing decision 5 preserves
- [`planning-skill-output-routing.md`](../designs/planning-skill-output-routing.md)
  — §Decision 2, the opt-in signal decision 4 reuses; §Decision 5, the
  scaffolding responsibility Phase 4 inherits
- [`docs/planning/README.md`](../planning/README.md) — the artifact index
  an early stop under decision 3 must still update
