# Project Feasibility Skill

## Status

Draft

## Context

### What is missing

[ADR 002](../adr/002-planning-artifact-contract.md) decision 2 assigns
`docs/planning/feasibility.md` to a skill called `project-feasibility`.
The template exists at `global-claude/templates/planning/feasibility.md`
and names that owner in its frontmatter. The skill does not exist.

`tests/test_planning_artifacts.bats:22-27` records the consequence
explicitly: the suite deliberately does not assert that an owner named in
a template is a skill that exists, because `project-feasibility` and
`project-planning` are specified by ADR 002 and not yet built. Phase 3
retires half of that exemption.

This is the only genuinely new skill in the Planning set. `scope.md` and
`charter.md` are the orchestrator's own opening and closing steps, and
`prior-art.md` was routed in Phase 2 to a skill that already existed.

### The trigger collides with an existing skill

`swe-prior-art-research`'s description claims, in its first sentence,
to "evaluate technical feasibility for a software engineering problem or
idea" and to answer "whether something is technically feasible/worth
building". A skill named `project-feasibility` competes with that on the
most obvious keyword available.

The project has already been burned by exactly this and recorded the fix.
That skill's changelog 0.3 describes a mutual-exclusion clause against
`industry-research-analyst` that disambiguated by keyword, failed on a
compound query where both phrases appeared in one sentence, and was
replaced by a tie-breaker on *what the answer needs to conclude*. The same
failure is available here and the same fix applies.

[ADR 003](../adr/003-where-a-behavioural-rule-goes.md) decision 3 raises the
stakes: a skill's description is loaded every session and its body is not,
so the trigger is the part that must work, and "an unfired skill is the
failure mode that makes rung 2 worse than rung 3."

### The financial dimension is not a budget

ADR 001's phase mapping marks "budget estimate" and "financial-controller
sign-off" as not applicable to a single operator, while the template
carries a `## Financial` section with `ceiling-financial: 15`. Left
unstated, a skill reading the word "Financial" produces currency figures
that ADR 001 says do not belong, and does so with the false authority the
template's Confidence section exists to prevent.

## Decision

### 1. One skill, one file, inheriting the Phase 2 boundary

`global-claude/skills/project-feasibility/SKILL.md`. No `references/`
subdirectory — the routing note in `swe-prior-art-research` is the
precedent for how much fits in a body, and the three dimensions share one
reasoning pass rather than needing separate loadable content.

The global/per-project boundary is settled and not re-derived here:
templates in the global layer, artifacts per-project, routing gated on
`docs/planning/` existing. See
[`planning-skill-output-routing.md`](planning-skill-output-routing.md)
§Decision 1 and §Decision 2.

One difference from `swe-prior-art-research` is load-bearing. That skill
has a genuine non-Planning mode: asked an ad-hoc prior-art question it
answers in the conversation and writes nothing. `project-feasibility` has
no such mode. Its entire output is the artifact, so where
`swe-prior-art-research` degrades to conversational output,
`project-feasibility` declines and says what is missing.

### 2. Input contract, and what refusal is for

**`docs/planning/scope.md` is required.** Without it there is no problem
statement, no constraints and no non-goals, and a feasibility verdict
assembled from the prompt instead is precisely the failure the artifact
exists to prevent — a confident-looking judgment about constraints nobody
wrote down. The skill stops and names the missing file.

**`docs/planning/prior-art.md` is optional.** Its absence is recorded as a
named limitation under Confidence by dimension rather than blocking the
run. This follows the doctrine `swe-prior-art-research` already states:
absence of prior art is a finding, not a dead end, and usually means
higher risk rather than opportunity.

Both inputs are cited as `path §Section` and never restated, per ADR 002
decision 6.

### 3. The three dimensions do not have equal standing

The template's own comment names this as the document's characteristic
failure. The skill enforces the ordering rather than hoping for it:

| Dimension | Question | Basis |
|---|---|---|
| Technical | Can it be built at all, under `scope.md` §Constraints | Prior art and the stack — verifiable |
| Operational | Can *this* operator build and run it | Local to here; no literature answers it |
| Financial | Is the expected value worth the effort | Assumption-laden; assumptions stated inline |

**Financial means effort and opportunity cost — operator time, and what
that time is not spent on. No currency figures, no budget line, no
recurring-cost estimate.** ADR 001 excludes budget estimation from this
project's Planning phase, and a skill that emits money anyway would be
producing the one artifact the phase mapping says is not applicable here.

`## Confidence by dimension` is mandatory and is the mechanism that makes
the ordering visible to a reader who skips everything else. An artifact
whose weakest section reads as firmly as its strongest has failed even if
every claim in it is true.

### 4. No new research pass

The skill reads `scope.md`, `prior-art.md`, and the repository itself. It
does not run web research.

That work belongs to `swe-prior-art-research`, which has already done it
by the time this step runs, and duplicating it costs a second research
pass to re-derive conclusions the previous artifact already records —
re-derivation being what ADR 002 decision 6 forbids, at roughly the token
multiple ADR 001's context section cites for a tooled agent.

### 5. Trigger, and mutual exclusion with `swe-prior-art-research`

The description discriminates on what the answer must conclude, not on
which words appear:

- **"Should this project start?"** — a go/no-go judgment about a scoped
  project, producing decision material for a human gate. This skill.
- **"Does this already exist, and is the approach viable?"** — prior art
  and technical viability of a solution, whether or not any project is
  being decided. `swe-prior-art-research`.

`swe-prior-art-research`'s own claim on feasibility is **not narrowed**.
It is correct for standalone use, and narrowing it would trade a live
collision for a dead skill. Both descriptions gain a reciprocal
tie-breaker clause instead, matching the pattern that skill already uses
against `industry-research-analyst`.

The Planning-context reading is the sharp end: in a run that follows the
contract, both skills fire, at different steps, in the order ADR 002
decision 2 lays out. That is intended, not a collision.

### 6. Risk inventory shape

Bullets, one line per risk, each with a one-line mitigation, no narrative.
`ceiling-risk-inventory: 20` enforces the budget; the skill states the
reason the template gives — a risk that needs a paragraph is a scope
problem, not a risk.

### Case classification (docs-as-code-workflow.md)

Case C. §4 question 1: a new global skill is a new abstraction, it
constrains Phase 4 (the orchestrator sequences it and consumes its
output), and it changes an existing skill's always-loaded description.
Not Case E — nothing here touches the files §6 enumerates as container
security controls.

Recorded against #69. No ADR: ADR 002 already decided the path, the owner
and the contract; this document decides how the owner behaves, which is
design rather than architecture.

## Consequences

The Planning phase gains its only missing capability. After this, two of
the four artifact paths have a real owner and the remaining gap is the
orchestrator.

Half the owner-existence exemption in `tests/test_planning_artifacts.bats`
can retire. It cannot retire fully until Phase 4, so the tightening is
staged as a check with a named exemption list rather than a comment —
data that shrinks visibly to empty, instead of prose that has to be
remembered.

Against that: **the Financial decision is local, and the skill is global.**
ADR 001 scopes its phase mapping to a single-operator project, but this
skill is injected into every repository the sandbox opens. A project that
genuinely has a budget gets a feasibility document that refuses to
estimate cost, and nothing in the skill will tell it why. The alternative
was worse — emitting money by default contradicts the only phase mapping
this project has written down — but the mismatch is real and will surface
the first time the sandbox plans something with a spend line.

The refusal in decision 2 makes the skill unusable in a fresh project
until `scope.md` exists, and `scope.md`'s owner is Phase 4. Until the
orchestrator lands, running this skill means hand-writing a scope
artifact. That is the intended cost of refusing to invent constraints, but
it does mean Phase 3 ships a capability that is awkward to exercise.

**Nothing tests that the right skill fires.** D-8 asserts a description
parses; no check asserts that a feasibility question routes here rather
than to `swe-prior-art-research`. The mutual exclusion is prose in two
descriptions, which is rung 2 of the enforcement ladder, and the failure
mode — the wrong skill firing, or neither — is silent. The `0.3` changelog
entry on `swe-prior-art-research` shows this class of clause failing once
already, and it was caught by manual re-testing rather than by a gate.

## Alternatives considered

**Chose:** a separate `project-feasibility` skill.
**Rejected:** extend `swe-prior-art-research` to write `feasibility.md`
as well.
**Why the rejected option is attractive:** its description already claims
feasibility, so there is no collision to resolve, no second description
competing for the same trigger, and no new file in the global layer — the
skill that has the prior art in hand is the obvious one to judge what it
means.
**What breaks if you try it anyway:** ADR 002 decision 2 gives the two
artifacts different owners, and P-5 exists to keep that unambiguous. Worse,
the two have opposite defaults: prior-art research is a general-purpose
question answered in conversation, while feasibility is a contract step
that only produces an artifact. Merging them makes every ad-hoc prior-art
query in any repository start reaching for `docs/planning/`.

**Chose:** one skill covering three dimensions.
**Rejected:** three skills, one per dimension.
**Why the rejected option is attractive:** the dimensions have genuinely
different confidence profiles, which is the project's own stated reason
for preferring composable pieces, and each would be independently
testable.
**What breaks if you try it anyway:** the section that carries the most
weight is Confidence by dimension, which is a comparison — it requires all
three judgments in one place to say which one can bear load. Three skills
would each declare their own confidence and nothing would rank them, which
is the failure the section was written to prevent. Three descriptions
would also compete for one trigger, tripling the collision this design
already has to manage once.

**Chose:** refuse without `scope.md`.
**Rejected:** derive the problem statement from the conversation when the
artifact is absent.
**Why the rejected option is attractive:** it keeps the skill invocable
standalone, which the phase plan explicitly wanted for every piece, and a
missing file is a thin reason to refuse work the model could plainly do.
**What breaks if you try it anyway:** the artifact then asserts
constraints and non-goals that nobody wrote down, with the authority of a
committed document carrying `status: Draft` and a place in the index. A
feasibility verdict is only as good as the constraints it was measured
against, and inventing them is indistinguishable, in the output, from
having been given them.

**Chose:** no research pass of its own.
**Rejected:** let the skill search when `prior-art.md` is thin or absent.
**Why the rejected option is attractive:** it makes the skill complete on
its own, and a feasibility judgment built on a thin prior-art artifact is
genuinely weaker than one built on fresh evidence.
**What breaks if you try it anyway:** it re-derives what the previous step
already recorded, which ADR 002 decision 6 forbids and which costs a
second research pass to produce a second copy that can disagree with the
first. The honest handling of thin evidence is to say so in Confidence by
dimension, which is what that section is for.

## Implementation plan

1. Write `global-claude/skills/project-feasibility/SKILL.md`: description
   with the tie-breaker clause, input contract and refusal, the three
   dimensions with Financial bounded to effort, the mandatory Confidence
   section, the artifact and index-row routing from Phase 2.
2. Add the reciprocal tie-breaker to `swe-prior-art-research`'s
   description and a `0.5` changelog entry. Its feasibility claim is not
   narrowed.
3. Add `P-7` to `tests/test_planning_artifacts.bats`: every `owner:` named
   by a template resolves to a committed skill, with `project-planning`
   listed as a named exemption until Phase 4 lands. The exemption is an
   array in the test, not a sentence in a comment.
4. Verify: global-layer line ceiling (D-7), `CLAUDE.md` unchanged (D-6),
   both descriptions still parse (D-8), markdown links resolve (D-1),
   `P-0` through `P-7` green.
5. Update the #69 checklist and note that owner-existence tightening is
   now partial rather than absent.

Step 4 requires `bats` on the host — `BUILDING.md:215`.
