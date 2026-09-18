# ADR 006 — Scope intake's inference ledger and the Planning entry test

## Status

Accepted

## Context

Issue #103 raises two questions about the entry to Planning. Both were
unexercised when it was written; the first real run has since happened,
bundling #102, #103 and #104, and its artifacts are in `docs/planning/`.
That run is the evidence below.

**The transcription rule guards unanswered questions, not interpretation.**
`project-planning`'s intake rule says every substantive claim in `scope.md`
traces to something the operator said, and that a question they did not
answer becomes an explicit gap rather than a plausible guess. What it does
not reach is reading what *was* said as something stronger or narrower than
it was. Once written, an interpretation is indistinguishable from dictation
— the argument ADR 004 decision 2 already makes one step removed, that a
verdict measured against invented constraints cannot be told apart, in the
finished artifact, from one measured against given ones.

The first run produced exactly that failure. `docs/planning/0102-instruction-layer-silent-failures/scope.md`
§Constraints carries "This sandbox session has no container engine
available, so `hostonly`/engine-gated tests can be inspected but not run
here". The operator never said it; the model inferred it, flagged three
*other* guesses in the same section and not that one, and the operator
approved the section. It is also false: `hostonly` marks the tests that need
no engine, and what the sandbox actually lacks is `bats`. An approved,
committed, cited constraint, wrong, and indistinguishable from dictation —
produced by the first run that was able to produce it.

**Intake did not run as dictation at all.** The operator asked the model to
propose each section and approved them one at a time. The rule does not
describe that mode; it assumes the operator supplies content and the skill
formats it. Under propose-and-approve every claim originates with the model
and approval is the only trace of the operator's intent, which is precisely
the condition under which an unmarked inference is invisible.

**The entry test.** #103 rejects "Case A/B → skip feasibility" and proposes
that Planning applies when the open question is whether the work should
exist. Cases A–E classify a change; Planning scopes a project, and they are
different units. Pruning Planning by Case also runs ADR 004 decision 5
backwards: that decision holds that a Case assigned at Planning time rests
on strictly less information than one assigned at Design time, so pruning
Planning by Case requires classifying earlier still.

#103 pairs the test with a corollary — a change nameable as a single
`type(scope): subject` commit never enters Planning. The first run is a
counterexample to the test used as an exclusion rule: existence was settled
by #102, #103 and #104 before Planning began, so the test would have refused
the run. That run produced the scoping alternative recorded in ADR 005's
Alternatives, the WSL 2.5.x regression now feeding #102, and the four
findings in #106.

## Decision

**1. Intake declares its inferences, and the ledger is empty before
approval.** While intake is open, the skill keeps a ledger of claims bound
for `scope.md` that did not come from the operator's words: interpretations
of what was said, and anything the operator has not explicitly ratified.
Each entry names the claim and what it was inferred from. Before
`status: Approved`, every entry is resolved — the operator confirms it, and
it becomes dictation; corrects it; or it is rewritten as an explicit gap. An
unresolved entry blocks approval.

The ledger is conversational and ephemeral, not a committed artifact. That
is sound only because an approved `scope.md` is defined to have none left:
the ledger's product is the file, not a record beside it.

The boundary, stated because the first run crossed it without noticing:
summarising material the operator supplied is not inference. Supplying a
fact the operator never stated is — however obvious it looks, and however
true it happens to be.

**2. Propose-and-approve is a supported intake mode, and it raises the bar
rather than lowering it.** The operator may ask the skill to draft sections.
When they do, every substantive claim in the draft starts on the ledger,
because none of it traces to the operator's words yet; approving a section
clears its entries. This is the mode the first run used and the mode the
transcription rule did not describe.

**3. Approval means every claim has been ratified.** This gives the entry
gate semantic content beyond "the operator said yes", which is what ADR 004
decision 7 already asks `status: Approved` to carry — that the document is
final and correct. ADR 004 decision 2 is unchanged: intake still always
requires a human. This qualifies how that approval is obtained, not whether
one is needed.

**4. Planning applies when the open question is whether the work should
exist — as a routing default, not a gate.** If existence is settled and only
the shape is open, that is Design. The default fires when nobody has asked
the question; it does not refuse a run the operator has deliberately chosen,
which is what the first run was. An operator who overrides it says so, and
the reason belongs in `scope.md`.

**5. The single-commit corollary is not adopted.** Naming a change as one
commit subject is a judgment about the change's shape, which is what Cases A
and B encode. Making it before Planning is the same backwards move as
pruning by Case, one step further back and on less information again.

**6. Decision 4 goes in the skill's `description`; decisions 1 to 3 go in
its body.** Per ADR 003 decision 3, a description is in context every
session and a body only on invocation. A *when does this fire* rule has to
be in the description to fire at all; a procedure belongs in the body. The
new text is itself under `global-claude/`, so ADR 005 governs how it cites:
no repo-relative paths, and ADR numbers carry the project qualifier.

## Consequences

The failure that put a false constraint into the first run's `scope.md` is
now catchable at the moment it happens, by the one participant who can tell
inference from dictation: the operator, before approving. And the mode that
made it invisible is described rather than unmentioned, with the stricter
treatment attached to it.

Against that:

**Nothing enforces the ledger.** It is prose in a SKILL.md — rung 2 by ADR
003, the same class as ADR 004 decision 4, which the first run found
unimplemented and #106 records. No check can see a conversational ledger,
and a model that skips it produces a `scope.md` indistinguishable from one
that kept it. This is the weakest part of this decision, and it is stated
rather than mitigated: a convention nobody can fail is rung 2 by
construction, and saying so is better than inventing a probe for it.

**The bar is highest in the most convenient mode.** Decision 2 puts every
drafted claim on the ledger, so the easy path is the one with the most
entries to clear. An operator in a hurry approves a long ledger quickly,
which is approval without ratification wearing the right clothes.

**A default is weaker than a gate.** ADR 002's own argument is that a
ceiling routinely worked around is worse than none, because it teaches that
the contract is advisory. Decision 4 accepts that risk on the evidence of a
single run; whether overrides become routine is the thing to watch on the
second and third.

**This settles decisions, not mechanism.** #103 asked for decisions only.
Decision 6 places the text; it does not add a check, and none is proposed.

## Alternatives considered

**Chose:** an ephemeral ledger that must be empty before approval.
**Rejected:** a committed section of `scope.md` recording what was inferred.
**Why the rejected option is attractive:** it is durable and auditable, a
later reader sees exactly what was inferred, and it is what RAID-log practice
does — the precedent the Planning run's prior-art research found.
**What breaks if you try it anyway:** it changes the artifact contract ADR
002 fixes, adding a section and a ceiling and the checks that go with them,
and it preserves the one thing that should not survive the gate. An approved
`scope.md` is defined to hold no unratified claims, so a permanent list of
them records a state the gate forbids.

**Chose:** propose-and-approve is supported, with every drafted claim on the
ledger.
**Rejected:** forbid it — intake is dictation or it does not happen.
**Why the rejected option is attractive:** it is the simplest reading of the
existing rule and leaves no ambiguity about whose words are in the file.
**What breaks if you try it anyway:** it refuses the mode the operator
actually used on the first run, and an operator who wants drafting help will
get it outside the skill and paste the result back — the same file, with no
ledger at all.

**Chose:** the entry test as a routing default.
**Rejected:** a hard gate that refuses Planning once existence is settled.
**Why the rejected option is attractive:** a gate is checkable and a default
is not, and it is the form #103 proposed.
**What breaks if you try it anyway:** it would have refused the run whose
output is now cited in ADR 005's Alternatives and in #106, on the grounds
that three issues had already settled that the work should happen.

**Chose:** drop the single-commit corollary.
**Rejected:** keep it, as #103 proposed.
**Why the rejected option is attractive:** it is a bright line, cheap to
apply, and it keeps trivially small work out of a phase that would dwarf it.
**What breaks if you try it anyway:** it is Case reasoning moved before
Planning, which decision 2's own argument rejects and which ADR 004 decision
5's timing argument rejects harder the earlier it is made.

## References

- [ADR 002](002-planning-artifact-contract.md) — the artifact contract a
  committed ledger section would change; the advisory-contract argument
- [ADR 003](003-where-a-behavioural-rule-goes.md) — decision 3, description
  versus body, which decision 6 applies
- [ADR 004](004-planning-to-design-handoff.md) — decisions 2, 5 and 7
- [ADR 005](005-citing-across-the-repo-boundary.md) — governs how the new
  skill text cites
- Issue #103 — the two decisions; Issue #106 — the first run's findings
- [`docs/planning/0102-instruction-layer-silent-failures/charter.md`](../planning/0102-instruction-layer-silent-failures/charter.md) — the Go, and the
  named condition this ADR answers
- [`docs/planning/0102-instruction-layer-silent-failures/scope.md`](../planning/0102-instruction-layer-silent-failures/scope.md) §Constraints — the false
  constraint, left in place as evidence
