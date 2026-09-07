---
name: project-planning
description: "Run the Planning phase for a scoped project end to end — facilitate scope intake, sequence prior-art research and feasibility assessment, then write docs/planning/scope.md and docs/planning/charter.md as go/no-go material for a human gate. Trigger on a request to plan a project, start the Planning phase, or produce a project charter. Delegates to swe-prior-art-research and project-feasibility rather than competing with them — resolve by span, not by keyword: orchestrating the whole phase and ending in a charter routes here, while a standalone prior-art question or a single feasibility judgment routes to those skills directly. Requires an approved docs/planning/scope.md before any headless run, and never fills in the charter's Decision section."
---

# Project Planning

Act as the person who has to hand a decision to someone else and be
answerable for what is in it. The output is not a verdict — it is the
material a human uses to decide, arranged so that a no-go is as usable as a
go.

Two of the four Planning artifacts belong to this skill, and they face
opposite directions. `scope.md` takes dictation: it records what a person
said and nothing else. `charter.md` aggregates what the run found and then
stops short of the conclusion. Producing the conclusion is not this skill's
job — ADR 001 names autonomous go/no-go as an anti-goal.

## Input contract

**`docs/planning/scope.md` is required, and it must carry
`status: Approved`.** A person authors it and approves it; that approval is
the entry gate to the whole phase. Three cases, and only three:

1. **Present and approved** — read it, never rewrite it, continue.
2. **Absent, or present as `status: Draft`, with a person in the session** —
   facilitate intake (below), then stop for approval. A `Draft` scope means
   intake is not finished. The run does not continue past it.
3. **Absent with nobody present** — refuse and stop, naming the file and
   the status it needs. Do not derive a problem statement, constraints or
   non-goals in order to proceed.

**Intake is transcription, not derivation.** Every substantive claim in
`scope.md` traces to something the operator said in this session. Format
what they give you; do not infer what they did not. A question they did not
answer is written as an explicit gap — "not yet decided" — never filled with
a plausible-sounding guess.

A verdict measured against invented constraints is indistinguishable, in
the finished artifact, from one measured against given ones. Every later
step in this phase is measured against this file, and the file is committed,
indexed, and read by someone who was not here.

## Scaffolding

`docs/planning/` existing is the opt-in signal every Planning skill reads.
This skill may create it. **Its two peers may not, and that asymmetry is
deliberate.**

Create the directory only on an explicit request to begin planning for this
project, and say what the request grants:

> This project has no `docs/planning/`. Creating it opts the whole
> repository into the Planning contract — prior-art research and
> feasibility assessments will write committed artifacts here from now on,
> not just this run.

Never create it as a side effect of another task, and never in a headless
run. The second case does not arise on its own terms: a headless run
requires an approved `scope.md`, which requires the directory already.

Scaffolding writes two things:

1. `docs/planning/` itself.
2. `docs/planning/README.md`, following
   `~/.claude/templates/planning-index.md`. All four rows are created in
   their initial state.

The index is **the one place this skill writes rows it does not own**, and
the distinction is creation versus update. It creates the table; after
that, every skill updates only its own row, including this one.

## Workflow

1. **Establish scope.** Apply the input contract. On case 2, write
   `scope.md` from what the operator supplied and stop for approval.

2. **Prior art.** Hand off to `swe-prior-art-research`. It writes
   `docs/planning/prior-art.md` and updates its own index row. Do not
   research in its place, and do not summarise its output into a second
   copy that can disagree with the first.

3. **Feasibility.** Hand off to `project-feasibility`. It reads `scope.md`
   and the prior-art artifact, writes `docs/planning/feasibility.md`, and
   updates its own index row.

4. **Charter.** Re-read all three artifacts **from disk** before writing,
   even where they are still in the conversation. Write `charter.md`,
   leaving the Decision section as specified below, and report what was
   produced without recommending an outcome beyond what the Recommendation
   section already carries.

Run steps 2 through 4 straight through. There is no pause between steps in
the normal case.

**Stopping early.** After a step writes its artifact, stop the run only if
that artifact says, in its own words, that continuing is pointless — an
existing solution that already meets the scope, or an infeasibility no
named condition lifts.

The test is a quotation, not a judgment: **name the sentence and cite it as
`docs/planning/feasibility.md §Technical`. If no such sentence can be
quoted, continue.** Report the stop with that citation.

An early stop still leaves the artifact and its index row in place — the
partial output is the result, and re-running from the top is not required to
read it. **An early stop writes no charter.** A stop is an incomplete run,
not a no-go; a no-go is a person's entry in a charter that was written.

## Output

**Everything below applies only where `docs/planning/` exists** — either
because the project already had it, or because this run scaffolded it under
the section above.

1. Follow `~/.claude/templates/planning/scope.md` and
   `~/.claude/templates/planning/charter.md`. Their sections and order are
   the contract, and the `ceiling-<section>:` keys in their frontmatter are
   hard line limits per section. What does not fit does not belong in the
   artifact.
2. Write `docs/planning/scope.md` and `docs/planning/charter.md`.
   Frontmatter carries `status` (`Draft`, `Approved`, or
   `Superseded by <path>`), `date`, `phase` and `owner`; the `ceiling-*`
   and `artifact` keys stay in the template. Delete the template's
   authoring comments from the output — with the one exception below.
3. **The charter's Decision section is an exception to step 2.** Emit the
   `## Decision` heading and the template's authoring comment verbatim, and
   nothing else. That comment is the instruction to the person who fills it
   in; deleting it leaves a bare heading under a document that has just made
   a recommendation.
4. Every line under the charter's `## Evidence` cites its source as
   `docs/planning/scope.md §Constraints`. A claim that cannot be traced to
   one of the three preceding artifacts does not belong in the charter.
5. Update the `scope.md` and `charter.md` rows in `docs/planning/README.md`
   as each file is written: set the status cell, and change the artifact
   name from a code span to a markdown link now that the file exists.
   **Those two rows only.** The other two belong to other skills.

## Notes

- **Delegation is not summarisation.** Steps 2 and 3 belong to other
  skills, and their artifacts are the record. Re-deriving their conclusions
  into the charter produces a second copy that can drift from the first,
  which is what citation exists to prevent.
- **Mutual exclusion**: do not disambiguate by keyword — every skill in
  this phase legitimately uses the words "feasible" and "prior art".
  Disambiguate by span. Running the phase and ending in a charter is this
  skill; a standalone question about whether something exists is
  `swe-prior-art-research`; a standalone judgment about whether one scoped
  project should start is `project-feasibility`. In a Planning run all
  three fire, at different steps, in contract order — intended, not a
  collision.
- **The Decision section is reserved, and nothing enforces that but this
  sentence.** The section's line ceiling bounds its length, not its
  authorship. A decision written here would pass every check the contract
  has and would be the least visible failure in a finished artifact.
- A no-go is a first-class result. ADR 002 records that a refusal with its
  reasoning is the most reusable output this phase produces. Leave the
  charter in the tree with its status set; do not delete it.

## Changelog

- **0.1 (draft)** — Initial version, built to the contract in
  `docs/designs/project-planning-skill.md`. Not yet exercised against a
  real run; no Planning artifact has been written under it.
