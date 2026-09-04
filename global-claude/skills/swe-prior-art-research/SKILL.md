---
name: swe-prior-art-research
description: "Research prior art and evaluate technical feasibility for a software engineering problem or idea — has this been solved, built, or attempted before, and is it viable given real constraints. Trigger on requests to check whether an approach/idea/problem has precedent, existing solutions, or prior attempts, or whether something is technically feasible/worth building. Mutually exclusive with industry-research-analyst — resolve by what the answer needs to conclude, not by keyword: a personal build-vs-buy decision (even phrased as \"has anyone built X\") routes here, since surveying what exists is only an input to that decision; a market/competitive landscape report routes to industry-research-analyst instead. Also distinct from technical-explanation-structure (explaining an already-identified system). Also mutually exclusive with project-feasibility, on the same test: whether a scoped project should start, ending in a committed docs/planning/feasibility.md, routes there — whether a solution already exists and an approach is viable routes here, and is an input to that judgment."
---

# Software Engineering Prior-Art & Feasibility Research

Act as a research engineer whose job is to prevent reinvented wheels and
premature builds. The output isn't a landscape — it's an answer to
"has this been done, how, and should I do it too."

## Workflow

1. **Frame the problem precisely.** Restate the problem/idea in specific
   technical terms: inputs, constraints, what "solved" would mean. If it
   maps onto a known CS problem class (e.g. "this is a variant of
   consistent hashing," "this is bin packing under X constraint"), name
   it before searching — misclassifying a known problem as novel wastes
   the research pass.

2. **Novelty classification (routing).** Decide which of three buckets
   this falls in, since it determines search strategy:
   - **Well-trodden** — established literature/solutions exist. Go
     straight to canonical approaches and survey-level sources.
   - **Known class, novel combination** — the general problem is known
     but the specific constraint mix may not be. Search the general
     class, then check adjacent/analogous problems for the specific
     combination.
   - **Plausibly novel** — no obvious precedent. Search adjacent
     problems and decompose into sub-problems that likely *do* have
     precedent individually.

3. **Scope/constraints check.** If unclear, ask ONE consolidated
   question covering: hard constraints (language/stack, scale, latency,
   existing infra), what "feasible" means in this context (prototype vs.
   production), and what's already been tried. Skip if already clear
   from context.

   For **well-trodden** problems (step 2), don't frame this as "is it
   feasible" — step 2 already answered that (yes, established solutions
   exist). Frame it as "which constraint determines which known approach
   fits" instead. The open question at that point is applicability, not
   existence.

4. **Research brief.** Before the full research, state: the source
   types you'll draw from, the angle (canonical-solution survey vs.
   analogous decomposition, per step 2), and what's intentionally out of
   scope.

5. **Structured findings.** Evidence-rich, source-cited. For each prior
   attempt found: who did it, how, what tradeoffs they accepted, and any
   maturity/adoption signal. Distinguish established practice from
   one-off/experimental work. Explicitly surface failure reports —
   "attempted X, abandoned because Y" is often the most valuable finding.

6. **Feasibility verdict.** Unlike a landscape report, this closes with
   an explicit assessment: technical feasibility given the stated
   constraints, what's directly reusable vs. needs adaptation, the
   single biggest risk/unknown, and — if nothing relevant turned up —
   say so plainly. Absence of prior art is itself a data point (higher
   risk, or a genuine opportunity), not just a dead end.

7. **Follow-ups (optional, max 3).** Only if they'd meaningfully extend
   the work. When in doubt, suggest none.

Steps 5 and 6 produce the content; where that content goes depends on the
project. See **Planning-phase output** below before writing it up.

## Source hierarchy

- **Primary/technical**: papers (arXiv, ACM/IEEE), RFCs/specs, standards
  docs, OSS source and issue trackers, engineering blogs from teams that
  shipped the thing, postmortems.
- **Community signal (qualitative only)**: HN, Stack Overflow, Reddit,
  mailing lists. Treat as war-stories evidence for failure modes and
  real-world friction — never as authoritative technical fact. Same
  discipline as "social listening" in the market-research skill, but
  calibrated for engineering credibility, not sentiment.
- **Adoption-signal weighting (within any tier)**: package registries
  and technical blogs are increasingly padded with abandoned,
  copy-cat, or AI-generated filler content — a plausible-sounding
  source with no adoption evidence is noise, not a finding. Weight by
  stars/downloads/commit recency and known production users before
  treating something as a real data point. Prose that reads like
  marketing copy (unverifiable claims of expert review or endorsement,
  generic superlatives with no specifics) is itself a signal to
  discount the source, not cite it.

## Format and style

- Structured Markdown, source-cited, concise paragraphs.
- Flag temporal relevance — a 2015 approach to a since-solved problem
  (e.g. pre-io_uring Linux I/O patterns) needs that context stated, not
  presented as current best practice.
- State confidence explicitly where evidence is thin — don't let a
  single blog post read as consensus.

## Planning-phase output

**Applies only when `docs/planning/` exists in the current project.** Its
presence is the opt-in signal — a project without it gets the default
behaviour above and nothing is written to disk. Never create the directory
to satisfy this section.

When it does exist, the findings are an artifact rather than a reply:

1. Read `~/.claude/templates/planning/prior-art.md` and follow it. Its
   sections and their order are the contract, and the `ceiling-<section>:`
   keys in its frontmatter are hard line limits per section — what does not
   fit does not belong in this artifact.
2. Write to `docs/planning/prior-art.md`. Frontmatter carries `status`
   (`Draft`, `Approved`, or `Superseded by <path>`), `date`, `phase` and
   `owner`; the `ceiling-*` and `artifact` keys stay in the template.
   Delete the template's authoring comments from the output.
3. Read `docs/planning/scope.md` if present and cite it as
   `docs/planning/scope.md §Problem statement`. Do not restate the problem
   — a citation names a path and a section; "see the planning documents"
   does not.
4. Update the `prior-art.md` row in `docs/planning/README.md`: set the
   status cell, and change the artifact name from a code span to a markdown
   link now that the file exists. **That row only.** Every other row and
   every other path under `docs/planning/` belongs to a different skill.

`tests/test_planning_artifacts.bats` enforces 1, 2 and 4 where the project
carries that suite.

## Notes

- Pairs with `softwarecs-explanation-style` / `pl-explanation-style` when
  a found solution's internals need explaining — this skill finds and
  judges prior art, those supply the vocabulary for describing how it
  works.
- Pairs with `technical-explanation-structure` for the shape of any
  "how does the found solution work" subsection.
- Open question for later: if the novelty classification (step 2) ends
  up needing genuinely different content per bucket rather than just a
  different search angle, that's the signal to split into router +
  references — not before.
- **Mutual exclusion with `industry-research-analyst`**: don't
  disambiguate by keyword ("has anyone done X" vs. "worth building") —
  compound buy-vs-build queries contain both phrases at once and that
  test failed under the old wording. Disambiguate by what the answer
  needs to conclude: if the requester is deciding their own build/adopt
  action, this skill applies even though it requires surveying what
  exists — the survey is an input, not the deliverable. If the
  deliverable itself is a landscape/competitive report, that's
  `industry-research-analyst`.
- **Mutual exclusion with `project-feasibility`**: same tie-breaker, and
  the keyword test fails harder here — both skills legitimately say
  "feasible", and this one's own description claims technical feasibility.
  Resolve on what the answer must conclude. A go/no-go judgment about a
  scoped project, ending in a committed artifact, is `project-feasibility`.
  Whether something exists and whether the approach is viable is this
  skill, and the finding is an input to that judgment rather than a rival
  to it. In a Planning run both fire, at different steps, in the order
  ADR 002 lays out — that is intended, not a collision.

## Changelog

- **0.5 (draft)** — Reciprocal mutual-exclusion clause against the new
  `project-feasibility` skill, in the description and the notes. This
  skill's own feasibility claim is deliberately not narrowed: it is
  correct for standalone use, and narrowing it would trade a live
  collision for a skill that stops firing. The tie-breaker is the same one
  0.3 established — what the answer must conclude, not which words appear.
- **0.4 (draft)** — Added the Planning-phase output section: in a project
  carrying `docs/planning/`, findings become `docs/planning/prior-art.md`
  under the ADR 002 contract rather than a reply. Gated on the directory
  existing, because this skill is injected into every project and only
  some of them run that contract. Reasoning steps unchanged.
- **0.3 (draft)** — Re-tested the mutual-exclusion boundary with a
  compound buy-vs-build query ("has anyone built X... worth building
  our own?"). Old keyword-based clause failed — both halves of the
  sentence matched a different skill's trigger phrase. Replaced with a
  tie-breaker: resolve on what the answer needs to conclude (personal
  build/adopt decision vs. landscape report), not on which phrase
  appears.
- **0.2 (draft)** — Tested against 4 inline cases (2 trigger, 1
  boundary, 1 edge case). Fixes: adoption-signal weighting added to
  source hierarchy (low-quality/AI-generated filler was crowding
  legitimate results); mutual-exclusion clause added against
  `industry-research-analyst`, keyed on intent (build vs. compare)
  rather than topic overlap; step 3's constraint question reframed for
  well-trodden cases, where existential feasibility is already settled
  by step 2 and the open question is applicability.
- **0.1 (draft)** — Initial sketch, not yet validated or packaged.
