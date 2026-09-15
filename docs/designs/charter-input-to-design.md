# Charter Input to the Design Skill

## Status

Accepted

## Context

### What is missing

[ADR 004](../adr/004-planning-to-design-handoff.md) decisions 4 and 5
constrain `global-claude/skills/design/SKILL.md`. That file is unchanged.
The ADR specifies a target state nothing implements, which #89 opened to
track and #106 finding 4 confirmed against a real run.

It is no longer abstract. `docs/planning/charter.md` is a committed
artifact with `status: Approved`, written by the first real Planning run on
2026-09-11. The next `/design` invocation in this repository will not read
it.

Decision 6 needs no work. Step 7 (`design/SKILL.md:265-269`) is already
unconditional and nothing waives it; the ADR records intent so a later
reader does not remove the second gate as redundant. Saying so here keeps
this change scoped to decisions 4 and 5.

### Three constraints in #89 have expired

#89 was written before Phase 4 of #69 and before ADR 005. Re-verified
against the tree:

- **D-2 no longer blocks naming the orchestrator.**
  `global-claude/skills/project-planning/SKILL.md` was committed in
  `c5e9f72`, so a backticked `project-planning` resolves. #89's sequencing
  question — whether to build both sides of the handoff together — resolves
  with it. The writer exists; only the reader is missing.
- **D-7's figure is stale.** #89 says the global layer sits at 2144 lines.
  `tests/test_docs_integrity.bats:215` computes **2487** against a ceiling
  of 3000, counting every regular file under `global-claude/` rather than
  only `*.md`.
- **D-9 did not exist.** ADR 005 arrived with #104 and now governs what a
  file under `global-claude/` may cite, because those files are authored
  here and read inside a different repository.

### Why this is not an ADR

ADR 004 took the decision; this is execution. Nothing below reverses or
qualifies an accepted decision, so no ADR is superseded and none is
written. #89 §Shape reaches the same conclusion independently.

## Decision

### 1. A new `## Step 1b`, not a branch of Step 1

ADR 004 decision 4 asks for "the same found / not-found shape Step 1
already uses". Reusing the *shape* is right; sharing the *heading* is not.

Step 1's five branches all terminate by handing off to Step 2 —
`design/SKILL.md:20, 61, 71, 72, 75`. A block appended after them is
unreachable whichever branch fires, so "another block inside Step 1" is not
available without editing those terminators anyway. Placing the charter
read at the top of Step 1 instead is available, and worse: two
found/not-found disjunctions back to back under one heading, where Step 1's
four blocks are a disjunction of which exactly one fires. A charter block
sharing that heading reads as a fifth alternative, and the careless reader
is the one this change is written about.

Renumbering is ruled out by citations this repository cannot rewrite.
`global-claude/CLAUDE.md:71` pins Step 2 for case selection; ADR 004 pins
Step 7 and "Steps 1–3" at `:99`, `:169` and `:266`, and `:169` states that
decisions 4 and 5 assume the current Step 1–3 structure. ADRs are never
rewritten.

`Step 1b` preserves every external reference and costs no edit outside this
one file. The global layer already carries the idiom:
`global-claude/skills/commit-hook-setup/SKILL.md:45` is a `## Step 2a`, a
sequential lettered sub-step. `design`'s own 6a and 6b are alternatives
rather than a sequence — same notation, different shape, and the
distinction is worth noting so 1b is not read as a sibling of 6a.

The five terminators redirect to Step 1b. Three of them keep "using
built-in defaults", which qualifies the workflow-document outcome and
carries through Step 1b unchanged.

### 2. Decision 5 is stated twice, and the second placement is the one that matters

Step 1b closes with the non-binding rule and ends on a short imperative:
*read the charter first; do not let it decide.* #89 warns that "read the
charter first" and "let the charter decide" are one word apart, so the
distinction is placed where a skimming reader stops.

That is not sufficient on its own. `global-claude/CLAUDE.md:71` routes
readers **straight to Step 2** for case selection, and a reader entering
there never sees Step 1b. Step 2 therefore carries its own sentence: the
charter's constraints and non-goals are inputs to the questions below; any
Case it names is not.

**The fenced decision tree is not touched.** Node 0 already reads "Is a
project-specific Case E defined in `docs/designs/docs-as-code-workflow.md`
… YES → Case E. Follow the procedure defined in the project workflow
document." The tree's only precedent for consulting an external document is
a node that delegates the Case to it. A charter node placed beside that
inherits the reading by adjacency, whatever its wording — which is decision
5's failure mode in the one location it must not occur. Prose above the
fence is this file's existing idiom for context on the block; the
"Secondary check" paragraph at `:103-105` sits outside it for the same
reason.

### 3. No ADR number, no skill name, no `description` change

- **No `ADR NNN` token in the skill.** An ADR number is unresolvable in the
  reader's repository, which is the hazard ADR 005 exists to name, and the
  D-9-legal qualifier costs about seven words per mention. Provenance
  belongs in this document, which is repo-local.
- **`project-planning` is not named in the body.** It is D-2-safe now, but
  naming it creates a cross-skill coupling in the always-injected layer
  that must survive any rename, in exchange for information the reader does
  not need. `design` conditions on the directory and the file, not on who
  wrote them.
- **The frontmatter `description` is unchanged.** It answers when this
  skill fires and which skill wins a collision. Reading the charter is
  neither: it changes what `design` does after firing, and nothing competes
  to read the charter at Design time. Adding it would spend always-on
  budget on a post-selection fact — rung-3 spending for a rung-2 rule,
  which is the inversion [ADR 003](../adr/003-where-a-behavioural-rule-goes.md)
  exists to prevent.
- **Nothing is added to `global-claude/CLAUDE.md`**, which stays at 96 of
  D-6's 200. Rung 3 is earned only by failing rungs 1 and 2. Rung 1 fails
  on precision rather than availability: the charter template is loaded
  when the charter is *authored*, by its owner, so a rule about how
  `design` *reads* it would sit in a file `design` never opens. Rung 2
  holds, and ADR 004's own Consequences already class decision 4 there.

### 4. Wording mirrors the peer skills

The opt-in sentence mirrors `swe-prior-art-research/SKILL.md:99-102`,
including "Never create the directory", the anti-invention guard
`project-planning/SKILL.md:79-81` depends on when it places its two peers —
`design` among them — in the may-not-create class. The citation sentence
mirrors the same file at `:118-121`, keeping "a citation names a path and a
section", which is the clause doing the work.

Three skills stating one rule three ways would be three rules to keep in
sync. That is ADR 002 decision 6 applied to the instruction layer itself.

Cited sections are drawn from the charter's real vocabulary —
`§Recommendation`, `§Open questions`, `§Decision`. `§TL;DR` and `§Evidence`
are omitted deliberately: the TL;DR restates the others, and citing it
invites the restatement ADR 002 decision 6 forbids.

## Consequences

**Nothing asserts that the read happens.** ADR 004's Consequences
(`:143-147`) already record decision 4 as rung-2 enforcement — prose in a
SKILL.md, the weakest carrier ADR 003 names. Implementing decisions 4 and 5
does not change that, and #89 states plainly that the issue must not be
closed on a claim that it does. This is the same class as #88, and as the
"whether an owner that does exist is the skill that actually fires"
exclusion already recorded in `tests/test_planning_artifacts.bats`.

No test file is touched. That is the honest outcome, not an omission: the
behaviour is a model reading a file when a directory exists, and this
repository has no harness that observes a skill's execution. Writing a
check that asserts the *prose* is present would be a check nobody can fail
in the sense that matters — `mechanism-verification/SKILL.md:85-87` says
the honest move is to say so rather than invent a probe.

**Easier.** Design-phase work in a project carrying `docs/planning/` starts
from the constraints and non-goals a person already approved, cited rather
than re-derived. The charter's own `§Open questions` routes Case
classification forward to Design, so the handoff it describes now has a
reader.

**Harder.** `design/SKILL.md` grows by 33 lines and gains a step that fires
in a minority of projects. Every project without `docs/planning/` pays
those lines in injected context for a step that immediately falls through.
That cost is accepted because the alternative — gating on configuration
rather than on the directory — is what
[`planning-skill-output-routing.md`](planning-skill-output-routing.md)
§Decision 2 already rejected, on the grounds that a flag is a second thing
to keep in sync and a project with the directory but not the flag fails
silently.

**Budget.** The global layer goes from 2487 to 2520 against D-7's 3000,
spending about 6% of remaining headroom. This document is under
`docs/designs/` and costs nothing against that ceiling.

**Verification is bounded.** `bats` is not in the sandbox image, so D-2,
D-7 and D-9 are exercised here by extracting their helpers and calling them
directly. That covers the awk and sed logic and not the bats wiring, the
tags, or the reporting. Whether CI selected anything is #113 and cannot be
established from a session.

## Alternatives considered

**Chose:** a new `## Step 1b`.
**Rejected:** a fifth block inside Step 1.
**Why the rejected option is attractive:** ADR 004 decision 4 asks for "the
same found / not-found shape Step 1 already uses", and the most literal
reading of that is the same heading; it also adds no step to a file that
already has ten.
**What breaks if you try it anyway:** Step 1's five terminators all send the
reader to Step 2, so a block after them never executes — the change would
be inert while looking correct, which is the failure mode this repository
keeps finding. Put before them and it reads as a fifth alternative of a
disjunction where exactly one branch fires.

**Chose:** `Step 1b`.
**Rejected:** renumbering, so the charter read becomes Step 2 and the rest
shift.
**Why the rejected option is attractive:** sequential integers are what a
reader expects, and lettered sub-steps look like accreted history.
**What breaks if you try it anyway:** `global-claude/CLAUDE.md:71` and ADR
004 `:99, :169, :266` both cite step numbers by value, and ADR 004 `:169`
states that decisions 4 and 5 assume the current structure. ADRs are never
rewritten, so the citations cannot be corrected — they would simply become
wrong.

**Chose:** decision 5 as prose above the fenced tree, stated twice.
**Rejected:** a node inside the tree.
**Why the rejected option is attractive:** the tree is where classification
happens, a node is impossible to skim past, and node 0 already consults an
external document, so the precedent appears to exist.
**What breaks if you try it anyway:** that precedent is the problem. Node 0
delegates the Case to the document it names. A charter node beside it
inherits that reading by adjacency regardless of wording, which converts
"the charter informs classification" into "the charter performs it" — the
exact failure decision 5 exists to prevent.

**Chose:** silence in the frontmatter `description`.
**Rejected:** naming the charter there.
**Why the rejected option is attractive:** the description is the only part
of a skill always in context, so a reader who never opens the body would
otherwise not know the charter is read at all.
**What breaks if you try it anyway:** the description's job is selection —
when this skill fires, and which skill wins a collision. The charter read
is post-selection and uncontested, so the line buys discoverability with
always-on budget for every session in every project, which is the rung
inversion ADR 003 refuses.

## Implementation plan

Each step is one commit.

1. **This document.** `docs: design for charter input to the design skill (#89)`
2. **Decision 4.** Add `## Step 1b` without its closing paragraph, and
   redirect Step 1's five terminators.
   `feat(skills): read the project charter when Planning applies (#89)`
3. **Decision 5.** Add Step 1b's closing paragraph and the Step 2 sentence.
   `feat(skills): keep Case classification independent of the charter (#89)`
4. **Close.** Flip this document's `Status` to `Accepted`.
   `docs(designs): accept the charter-input design (closes #89)`

The 2/3 split is by decision rather than by file region. Decision 5 is the
load-bearing wording, and #89 asks for it to survive a careless reading —
so its diff should contain nothing but that clause in both of its
placements, reviewable on its own.

## References

- #89 — the tracking issue; #106 finding 4 — the same gap found by the
  first real run
- [ADR 004](../adr/004-planning-to-design-handoff.md) — decisions 4, 5 and
  6, and the Consequences paragraph recording decision 4 as rung 2
- [ADR 002](../adr/002-planning-artifact-contract.md) — decision 6,
  citation rather than restatement
- [ADR 003](../adr/003-where-a-behavioural-rule-goes.md) — the placement
  ladder behind decision 3
- [ADR 005](../adr/005-citing-across-the-repo-boundary.md) — why no ADR
  number appears in the skill
- [`planning-skill-output-routing.md`](planning-skill-output-routing.md)
  §Decision 2 — the opt-in signal this reuses
- `global-claude/skills/design/SKILL.md` — Steps 1, 2 and 7
- #88, #113 — the enforcement and CI-evidence gaps this does not close
