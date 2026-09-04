---
name: project-feasibility
description: "Judge whether a scoped project should start — technical, operational and effort feasibility, plus a risk inventory — and write docs/planning/feasibility.md as go/no-go material for a human gate. Trigger on a Planning-phase feasibility assessment, or when docs/planning/scope.md exists and the open question is whether to proceed. Mutually exclusive with swe-prior-art-research — resolve by what the answer must conclude, not by keyword: \"should this project start\" routes here and produces a committed artifact, while \"does this already exist, and is the approach viable\" routes to swe-prior-art-research, whose findings are an input to this judgment. Requires docs/planning/scope.md and declines without it."
---

# Project Feasibility

Act as the engineer who has to build the thing and will be asked why it
slipped. The output is not an opinion on whether the idea is good — it is
the material a human uses to decide go or no-go, honest enough that a
no-go is a usable outcome.

Producing the decision itself is not this skill's job. ADR 001 names
autonomous go/no-go as an anti-goal: assemble the evidence, state the
confidence, stop.

## Input contract

**Required — `docs/planning/scope.md`.** If it is absent, say so and stop.
Do not derive the problem statement, the constraints or the non-goals from
the conversation. A verdict measured against invented constraints is
indistinguishable, in the finished artifact, from one measured against
given ones — and the artifact is committed, indexed, and read later by
someone who was not here.

**Optional — `docs/planning/prior-art.md`.** Proceed without it, and name
its absence in Confidence by dimension. Missing prior art usually means
higher risk rather than opportunity.

Cite both as `docs/planning/scope.md §Constraints`. Never restate what
they say; a citation names a path and a section.

**Do not run web research.** `swe-prior-art-research` owns that step and
has already run by the time this one does. Thin evidence is reported in
Confidence by dimension, not repaired by a second search pass that can
disagree with the first.

## Workflow

1. **Read the inputs.** `scope.md` for the problem, constraints,
   non-goals and definition of done; `prior-art.md`, if present, for what
   exists and what it cost the people who built it. Read the repository
   for what the stack and the tooling actually are.

2. **Assess each dimension separately**, in the order below. Resist
   letting a confident technical answer carry the other two.

3. **Build the risk inventory.** Top failure modes only, one line each,
   each with a one-line mitigation. Bulleted, no narrative. A risk that
   needs a paragraph is a scope problem, not a risk — take it back to
   `scope.md` rather than growing this section.

4. **Rank the dimensions by how much weight each can bear**, and write
   that into Confidence by dimension. This is the section that stops a
   reader treating the weakest judgment as firmly as the strongest, and it
   is the one most likely to be dropped under length pressure. Drop
   something else.

## The three dimensions

| Dimension | The question | What it rests on |
|---|---|---|
| Technical | Can it be built at all, under the stated constraints | Prior art and the stack — verifiable, highest confidence |
| Operational | Can *this* operator build and run it — skills, access, capacity | Local facts; no literature answers it |
| Financial | Is the expected value worth the effort | Assumptions, stated inline |

**Financial means effort and opportunity cost** — operator time, and what
that time is not spent on. No currency figures, no budget line, no
recurring-cost estimate. Budget estimation is outside the Planning phase
as this project maps it, and a section that emits money produces the one
artifact the mapping excludes, with false precision attached.

## Output

**Applies only when `docs/planning/` exists in the current project.**
Its presence is the opt-in signal. Never create the directory to satisfy
this section — without it, report the assessment in the conversation and
write nothing.

1. Follow `~/.claude/templates/planning/feasibility.md`. Its sections and
   their order are the contract, and the `ceiling-<section>:` keys in its
   frontmatter are hard line limits per section. What does not fit does
   not belong in this artifact.
2. Write `docs/planning/feasibility.md`. Frontmatter carries `status`
   (`Draft`, `Approved`, or `Superseded by <path>`), `date`, `phase` and
   `owner`; the `ceiling-*` and `artifact` keys stay in the template.
   Delete the template's authoring comments from the output.
3. Update the `feasibility.md` row in `docs/planning/README.md`: set the
   status cell, and change the artifact name from a code span to a
   markdown link now that the file exists. **That row only.** Every other
   row and every other path under `docs/planning/` belongs to another
   skill.

## Notes

- **Mutual exclusion with `swe-prior-art-research`**: do not disambiguate
  by keyword — both skills legitimately use the word "feasible", and a
  compound query contains both triggers at once. Disambiguate by what the
  answer must conclude. A go/no-go judgment about a scoped project, ending
  in a committed artifact, is this skill. Whether a solution already
  exists and whether an approach is viable is `swe-prior-art-research`,
  and its answer is an input here rather than a competitor.
- A no-go is a first-class result. ADR 002 records that a refusal with its
  reasoning is the most reusable output the Planning phase produces, so
  write it with the same care as an approval and leave it in the tree with
  its status set.

## Changelog

- **0.1 (draft)** — Initial version, built to the contract in
  `docs/designs/project-feasibility-skill.md`. Not yet exercised against
  a real `scope.md`.
