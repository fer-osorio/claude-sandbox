# Planning Artifact Finalization

## Status

Draft

## Context

### What is missing

The first real Planning run (`docs/planning/`, 2026-09-11) exposed three
gaps in what "finished" means for a Planning artifact. All three are
recorded as findings 1–3 of #106.

**1. P-4's unit is ambiguous.** `_p4_ceiling_violations` in
`tests/test_planning_artifacts.bats` counts non-blank physical lines
against the `ceiling-<section>:` integers declared in
`global-claude/templates/planning/*.md`. Physical lines are a property of
how prose was wrapped, not of how much was written. This run's artifacts
were written as unwrapped paragraphs, so every section passed. Hard-wrapped
at the repository's 76 columns, 13 of 20 sections breach.

**2. Nothing names the owner of `Approved` on the three artifacts a skill
writes.** `swe-prior-art-research` SKILL.md:111, `project-feasibility`
SKILL.md:84 and `project-planning` SKILL.md:155 each say frontmatter
carries `status`; none says who sets it or when. `scope.md` is the
exception — `project-planning` SKILL.md:23 states plainly that a person
authors and approves it. The three outputs have no equivalent sentence, and
on the first run the operator had to ask.

ADR 004 decision 7 constrains the answer without supplying it: `status`
records document lifecycle, not decision outcome, and a no-go charter
carries `status: Approved` because "the document is final and correct."

**3. Nothing checks that a filled Decision carries a date.**
`global-claude/templates/planning/charter.md` instructs: "Left blank by the
skill. Filled in by a person, with a date." The first real Decision was
written without one and passed every check; the date was added afterwards,
on request.

### What was measured

Per-section word counts, and line counts after hard-wrapping at 76 columns
with `fold -s -w 76`, across the four committed artifacts:

| Artifact §Section | Ceiling | Wrapped lines | Words |
|---|---|---|---|
| `scope` §TL;DR | 6 | 11 | 104 |
| `scope` §Problem statement | 12 | 16 | 137 |
| `scope` §Constraints | 12 | 14 | 103 |
| `scope` §Non-goals | 12 | 16 | 148 |
| `scope` §Definition of done | 10 | 14 | 114 |
| `prior-art` §TL;DR | 6 | 11 | 90 |
| `prior-art` §Findings | 60 | 48 | 467 |
| `prior-art` §Build vs adopt | 15 | 18 | 150 |
| `prior-art` §Confidence | 8 | 16 | 130 |
| `feasibility` §TL;DR | 6 | 8 | 78 |
| `feasibility` §Technical | 20 | 19 | 144 |
| `feasibility` §Operational | 15 | 14 | 132 |
| `feasibility` §Financial | 15 | 14 | 128 |
| `feasibility` §Risk inventory | 20 | 19 | 170 |
| `feasibility` §Confidence by dimension | 12 | 11 | 91 |
| `charter` §TL;DR | 6 | 8 | 68 |
| `charter` §Recommendation | 12 | 15 | 127 |
| `charter` §Evidence | 20 | 27 | 224 |
| `charter` §Open questions | 12 | 16 | 147 |
| `charter` §Decision | 8 | 3 | 6 |

Prose density, measured rather than assumed: **8.67** words per line across
these four artifacts wrapped at 76 columns, **9.69** across the committed
prose in `docs/adr/` and `docs/designs/` as committed. The second figure is
higher because it includes table rows, which are denser than body prose.

### Why this is not an ADR

ADR 002 decision 4 states the intent as "a TL;DR of at most three
sentences." The line-count proxy was chosen in `docs/planning/README.md`,
not in the ADR, and ADR 002's own Consequences anticipate revision: "the
ceilings in decision 5 will sometimes be wrong and will need revisiting."
ADR 002 decision 7 describes what the test asserts — "no artifact exceeds
its template's ceilings" — without naming a unit.

Replacing a broken proxy implements decision 4 more completely rather than
changing it. That is the precedent #111 set against ADR 005 decision 3.

Finding 2 fills a gap ADR 004 decision 7 left rather than reversing
anything it decided, and the answer below is the one decision 7 and
decision 3 jointly imply. No ADR is superseded.

## Decision

### 1. Ceilings count words, and say so in the key

Rename the frontmatter key from `ceiling-<section>:` to
`ceiling-<section>-words:` across all four templates, and convert each
value at **9 words per line**.

The rename is not cosmetic. It is the ambiguity fix: a reader of
`ceiling-evidence: 20` cannot tell the unit, which is the defect. It also
makes a stale template fail loudly — a key P-4 no longer recognises
contributes no ceiling, and the guard in decision 4 turns that silence into
a failure.

The constant 9 sits inside the measured range (8.67–9.69) and is rounded
rather than derived. Its justification is that it reproduces the line-based
verdict: at 9 words per line the two units agree on **19 of 20 sections**.
They disagree only on `scope` §Constraints — 14 wrapped lines against a
ceiling of 12 is a breach, 103 words against 108 is not. One borderline
disagreement is the evidence that the conversion preserves the budget
rather than loosening it, which ADR 002 lines 88–91 forbids.

Converted ceilings:

| Template | Key | Was (lines) | Now (words) |
|---|---|---|---|
| all four | `ceiling-tldr-words` | 6 | 54 |
| `scope` | `ceiling-problem-statement-words` | 12 | 108 |
| `scope` | `ceiling-constraints-words` | 12 | 108 |
| `scope` | `ceiling-non-goals-words` | 12 | 108 |
| `scope` | `ceiling-definition-of-done-words` | 10 | 90 |
| `prior-art` | `ceiling-findings-words` | 60 | 540 |
| `prior-art` | `ceiling-build-vs-adopt-words` | 15 | 135 |
| `prior-art` | `ceiling-confidence-words` | 8 | 72 |
| `feasibility` | `ceiling-technical-words` | 20 | 180 |
| `feasibility` | `ceiling-operational-words` | 15 | 135 |
| `feasibility` | `ceiling-financial-words` | 15 | 135 |
| `feasibility` | `ceiling-risk-inventory-words` | 20 | 180 |
| `feasibility` | `ceiling-confidence-by-dimension-words` | 12 | 108 |
| `charter` | `ceiling-recommendation-words` | 12 | 108 |
| `charter` | `ceiling-evidence-words` | 20 | 180 |
| `charter` | `ceiling-open-questions-words` | 12 | 108 |
| `charter` | `ceiling-decision-words` | 8 | 72 |

`_section_lines` is replaced by `_section_words`, counting whitespace-
separated fields on non-blank lines between one `## ` heading and the next.

### 2. The writing skill sets `Approved`; the human gate stays at the Decision

Each of the three output-writing skills sets `status: Approved` on the
artifact it owns, at the moment it finishes writing it. The operator is not
asked to approve `prior-art.md`, `feasibility.md`, or the charter as
documents.

This follows from ADR 004 decision 7: `status` records lifecycle, not
outcome, and "final and correct" describes completeness — a property the
writing skill knows and the operator would be rubber-stamping. Requiring
three operator stops would contradict ADR 004 decision 3's "run straight
through," and it would put a gate where nothing is being decided.

`scope.md` is unchanged and remains the exception. Its `Approved` is a
person ratifying a transcription of their own words, which is a real gate —
ADR 006 makes the inference ledger depend on it.

The charter is `Approved` as a document while `## Decision` is still blank.
That is deliberate and already implied by ADR 004 decision 7's treatment of
a no-go charter. The decision gate is the Decision section, not the status
field.

**Consequence for #82.** L1 headless runs now have one well-defined
stopping point rather than four ambiguous ones: everything up to and
including a written charter is machine-ownable; the Decision is not.

### 3. A filled Decision carries a date

New check **P-8**: if `charter.md` §Decision contains any non-comment text,
it contains an ISO-8601 date (`YYYY-MM-DD`).

Keyed on the section being filled, not on `status`. A check keyed on
`status: Approved` would fire on every charter written under decision 2,
including those whose Decision is legitimately still blank. P-8 cannot
compel a person to decide; it can only require that a decision they made is
dated.

### 4. A ceiling set that empties is a failure, not a pass

New check **P-0b**, mirroring the existing P-0: if the set of
`ceiling-*-words` keys parsed from the templates is empty, fail.

The rename in decision 1 creates this hole. P-4 iterates over keys it finds
in the template; a template that no longer matches the parser yields zero
ceilings and P-4 passes over nothing. That is the exact degradation
`tests/test_planning_artifacts.bats:43-48` records as having already
happened once — "moving the templates without moving the pointer produced
exactly that, six passes over zero templates."

### 5. The committed artifacts are brought within their ceilings

Twelve sections breach the word ceilings, by 392 words in total:

| Artifact §Section | Words | Ceiling | Over |
|---|---|---|---|
| `scope` §TL;DR | 104 | 54 | +50 |
| `scope` §Problem statement | 137 | 108 | +29 |
| `scope` §Non-goals | 148 | 108 | +40 |
| `scope` §Definition of done | 114 | 90 | +24 |
| `prior-art` §TL;DR | 90 | 54 | +36 |
| `prior-art` §Build vs adopt | 150 | 135 | +15 |
| `prior-art` §Confidence | 130 | 72 | +58 |
| `feasibility` §TL;DR | 78 | 54 | +24 |
| `charter` §TL;DR | 68 | 54 | +14 |
| `charter` §Recommendation | 127 | 108 | +19 |
| `charter` §Evidence | 224 | 180 | +44 |
| `charter` §Open questions | 147 | 108 | +39 |

All four TL;DRs breach, and by the widest relative margins. That is the
section ADR 002 decision 4 singles out by name, so the most-breached
section is the one the contract is most explicit about.

Trimming is not deletion. ADR 002 decision 5 already prescribes the
remedy — "what does not fit in the template does not belong in that
artifact; it belongs in a document with its own home." Overflow that
carries real content moves; overflow that restates an earlier artifact is
cut under ADR 002 decision 6.

**`status: Approved` is not disturbed by the trim.** The artifacts were
never within contract; P-4's unit hid that. Bringing them inside it makes
them what `Approved` already claimed they were. The `## Decision` a person
signed is unchanged, and it is 6 words against a 72-word ceiling.

## Consequences

**Easier.** The unit stops depending on the author's wrapping. An artifact
written as one long paragraph and the same artifact hard-wrapped now
receive the same verdict, which is the property P-4 was assumed to have and
did not. `docs/planning/README.md`'s stated rationale for the line unit —
that sentence-splitting is unreliable — is preserved: words are as
mechanical as lines and carry none of the wrapping dependency.

**Harder.** Word counts are less legible than line counts. An author cannot
glance at a section and estimate 20 lines; 180 words requires a tool. The
mitigation is that the ceilings are maxima and the failure message reports
the actual count, so the tool is the test.

**Imprecise where markdown is dense.** A table row counts its cell contents
as words, so a table consumes budget faster per visual line than prose.
None of the four templates currently prescribes a table in a ceilinged
section; if one is added later, the ceiling will need revisiting. That is
the revisiting ADR 002's Consequences already anticipates, not a new
failure mode.

**A pre-existing hole is left open, deliberately.** P-4 checks only sections
that have a declared ceiling. A section present in an artifact but absent
from the template's ceiling keys is not checked, and a ceiling key naming a
section absent from the artifact passes as zero. Neither is created by this
change and neither is fixed here; both belong with #96's coverage work.

**Rung 2 remains rung 2 for decision 2.** Who set `Approved` is not
observable in the artifact, so no check can assert it. The rule is prose in
three SKILL.md files, and `mechanism-verification` SKILL.md:85-87 is
explicit that the honest move is to say so rather than invent a probe. This
design says so.

**D-7 budget.** `global-claude/` is at 2401 markdown lines against a 3000
ceiling. Decision 2 adds roughly one sentence to each of three skills.

**Verification is bounded.** bats is not in the sandbox image, so the
helpers can be extracted and exercised directly from a session but the bats
wiring, tags and reporting cannot. P-4's rewrite, P-8 and P-0b each need a
negative control — observed reporting against a deliberately broken
fixture — recorded in the file's header comment alongside the existing
2026-09-04 entries. Whether CI selected them is #113, and cannot be
confirmed from inside a session.

## Alternatives considered

**Chose:** words, calibrated at 9 per line.
**Rejected:** physical lines, plus a new check requiring artifacts to be
hard-wrapped at 76 columns.
**Why the rejected option is attractive:** it codifies what the repository
already does — every committed `.md` is wrapped — it keeps the original
calibration untouched, line counts are legible to an author at a glance,
and a wrap check is independently useful for diff readability.
**What breaks if you try it anyway:** the ambiguity is not removed, it is
compensated for. Two checks now have to agree, and the ceiling check remains
correct only for as long as the wrap check holds. It also does not avoid
the trim — 13 sections breach instead of 12 — so the disruption is equal
and the ambiguity survives.

**Chose:** convert ceilings at the measured density.
**Rejected:** recalibrate ceilings to what the first run actually produced.
**Why the rejected option is attractive:** no artifact needs trimming, the
first real run's output is preserved exactly as the operator approved it,
and the argument that "the ceilings were guesses and this is the first
evidence" is not obviously wrong.
**What breaks if you try it anyway:** it is ADR 002 lines 88–91 exactly —
"a ceiling that is routinely worked around is worse than none, because it
teaches everyone the contract is advisory." Calibrating a ceiling to the
first artifact that breached it is the definition of working around it, and
it would set the precedent on the very first run.

**Chose:** the writing skill sets `Approved`.
**Rejected:** the operator approves each of the three outputs as it lands.
**Why the rejected option is attractive:** it matches `scope.md`'s gate
exactly, it is the most conservative reading of "final and correct," and
three cheap stops are a small price for a human seeing each artifact before
the next step builds on it.
**What breaks if you try it anyway:** it contradicts ADR 004 decision 3's
"run straight through," and it puts a gate where nothing is decided — the
operator would be ratifying a document's completeness, not its content,
which is rubber-stamping and trains the gate to be ignored. It also gives
L1 four stopping points, which is #82's problem made worse.

**Chose:** P-8 keyed on the Decision section being filled.
**Rejected:** P-8 keyed on `status: Approved`.
**Why the rejected option is attractive:** `Approved` is the natural
signal for "this document is done," and reading one frontmatter field is
simpler than parsing a section body.
**What breaks if you try it anyway:** under decision 2 a charter is
`Approved` the moment the skill finishes writing it, with `## Decision`
legitimately blank. The check would fail on every correctly-written
charter, which means it gets switched off.

## Implementation plan

Each step is one commit, and every commit leaves the suite green.

1. **This document.** `docs: design for planning artifact finalization (#106)`
2. **Finding 2.** Name the owner of `Approved` in
   `swe-prior-art-research` SKILL.md, `project-feasibility` SKILL.md, and
   `project-planning` SKILL.md; note the charter's blank-Decision case.
   `fix(skills): name who sets Approved on Planning outputs (#106)`
3. **Finding 1, artifacts first.** Trim the twelve breaching sections to
   their word ceilings, relocating content rather than deleting it where it
   carries weight. Green under the old check and the new one.
   `docs(planning): bring the first run's artifacts within their ceilings (#106)`
4. **Finding 1, mechanism.** Rename the ceiling keys in the four templates,
   replace `_section_lines` with `_section_words`, add P-0b, and update
   `docs/planning/README.md` §"Two choices ADR 002 left open", which
   currently documents the line unit.
   `test(planning): count section ceilings in words, not lines (#106)`
5. **Finding 3.** Add P-8.
   `test(planning): assert a filled charter Decision carries a date (#106)`
6. **Negative controls.** Record each new and changed check observed
   failing against a broken fixture, in the header comment of
   `tests/test_planning_artifacts.bats`.
   `docs(test): record negative controls for P-0b, P-4 and P-8 (#106)`

Findings 4 of #106 — `design` never reads the charter — is #89 and is not
in this plan.

## References

- #106 findings 1, 2 and 3
- `docs/adr/002-planning-artifact-contract.md` — decisions 4, 5, 7; lines
  88-91 on ceilings that are worked around
- `docs/adr/004-planning-to-design-handoff.md` — decisions 3 and 7
- `docs/adr/003-where-a-behavioural-rule-goes.md` — why decision 2 stays
  prose
- `docs/planning/README.md` §"Two choices ADR 002 left open" — the line
  unit this supersedes
- `tests/test_planning_artifacts.bats:14-48` — P-0's precedent and the
  bounded-verification note
- #96, #111 — adjacent coverage gaps deliberately not closed here
- #113 — why CI selection cannot be confirmed from a session
