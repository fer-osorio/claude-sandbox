# swe-prior-art-research changelog

- **0.7 (draft)** — Paths resolve through the Current bundle (ADR 008 of the
  claude-sandbox project). A second run under the flat layout would have
  overwritten the first run's Approved prior-art artifact.
- **0.6 (draft)** — Named the owner of `status: Approved` on the Planning
  artifact. The first real run left it unset because no sentence said who
  set it, and the operator had to ask. Lifecycle is not verdict — ADR 004
  of the claude-sandbox project, decision 7 — so completeness is this
  skill's to declare.
- **0.5 (draft)** — Reciprocal mutual-exclusion clause against the new
  `project-feasibility` skill, in the description and the notes. This
  skill's own feasibility claim is deliberately not narrowed: it is
  correct for standalone use, and narrowing it would trade a live
  collision for a skill that stops firing. The tie-breaker is the same one
  0.3 established — what the answer must conclude, not which words appear.
- **0.4 (draft)** — Added the Planning-phase output section: in a project
  carrying `docs/planning/`, findings become `docs/planning/prior-art.md`
  under the contract in ADR 002 of the claude-sandbox project rather than a
  reply. Gated on the directory
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
