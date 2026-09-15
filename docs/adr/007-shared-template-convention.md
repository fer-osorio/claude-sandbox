# ADR 007 — Shared template convention

## Status

Accepted

## Context

Six template files ship in the injected layer, in three shapes that do not
agree:

| Template | Declares | Instructions | Checked by |
|---|---|---|---|
| `templates/planning/*.md` (four) | `artifact`, `owner`, `phase`, `ceiling-<section>-words` in YAML frontmatter | per-section HTML comments | P-0 through P-8 |
| `templates/planning-index.md` | nothing | one preamble comment | nothing |
| `templates/docs-as-code-workflow-template.md` | nothing (`**Version:** 1.0.0` as bold text) | 13 HTML comment blocks, plus `<placeholder>` tokens | nothing |

Issue #46 asks whether they should share one shape. The question is not
academic, and the cost has already been paid twice.

**An author facing three declared document structures produced a document
drawing on all three.**
[`auto-memory-seeding.md`](../designs/auto-memory-seeding.md), committed
2026-09-03, runs numbered sections 1–9 with a `## Changelog` — the shape no
document declares — while taking §2 "Current Structure" and §3 "Target
Structure" from `docs-as-code-workflow.md` §3 Case C and §6 "Consequences"
and §7 "Alternatives Considered" from the `design` skill's Step 6a. The
three structures share no section name with each other. One document now
shares names with all of them.

Nor are the shapes converging on their own. Seven of sixteen committed
design documents follow Step 6a exactly, spanning 2026-08-19 to 2026-09-15;
the numbered family's newest member falls inside that range, not before it.
The sixteen carry status in four different mechanisms.

**A convention that is never written down is a convention nobody can be
wrong about.** `global-claude/skills/design/SKILL.md:27` instructs an
author to "Replace `<org>/<repo>` in the frontmatter Scope field", and
`:55` to "Set `Status: Accepted` in the frontmatter". The workflow template
has no frontmatter: line 1 is a heading, lines 2–4 are bold key/value
pairs, and the `---` at line 6 is a horizontal rule. The skill has named a
structure the file does not have for as long as both have existed, and
nothing catches it, because `TEMPLATE_DIR` in
`tests/test_planning_artifacts.bats` points at `templates/planning` and
`global-claude/templates/*.md` is reached by no check at all.

Both facts have the same cause. This ADR settles the convention; it writes
no template and changes no test.

## Decision

**1. There are two kinds of template, and every template declares which it
is.** A **contract template** governs one artifact, at one path, written by
exactly one skill, whose sections a check can measure. It carries
`artifact:`, `owner:`, `phase:` and at least one `ceiling-<section>-words:`
key. A **scaffold template** is copied once into a project, after which the
project owns the result; it carries `seeded-by:` naming the skill that
copies it, and `unowned-because:` stating in one line why no single writer
owns the output.

The discriminator is not size or subject. A template is a contract template
only if all three hold: the output lands at a path the convention fixes
rather than the project chooses; exactly one skill writes it; and its
sections have a length a ceiling can bound. Failing any one makes it a
scaffold.

The four Planning templates are contract templates and are unchanged.
`planning-index.md` and `docs-as-code-workflow-template.md` are scaffolds.

Neither scaffold can be made to fit the contract without writing something
false; the first alternative below records what breaks in each case.

**1b. `artifact:` names the path whose sections its ceilings measure**, not
the path the output lands at — the index has the second without the first.
`unowned-because:` is a frontmatter value rather than a comment so the set
of unowned templates is greppable and shrinks visibly, in the style
`_UNBUILT_OWNERS` established: a template that acquires an owner is
promoted by deleting one key, visibly, in the diff.

**1c. A template's frontmatter is addressed to the checks and is never
copied into the output.** The contract tier already behaves this way —
ceilings stay in the template while the artifact carries `status`, `date`,
`phase` and `owner`. What the scaffolds gain is a real YAML block, deleted
on instantiation like the authoring comments.

**1d. ADR 002 decision 5 is read as binding contract templates.** It says
"Templates carry hard section ceilings" with no scoping qualifier, inside
an ADR titled *Planning-phase artifact contract* whose Consequences argue
in terms of the Planning ceilings; the generality is accidental. ADR 002 is
not rewritten. Stating the scope it left open is the move
[ADR 005](005-citing-across-the-repo-boundary.md) decision 1 made on
[ADR 003](003-where-a-behavioural-rule-goes.md) decision 4.

**2. The checks cover every template in the injected layer, not one
subdirectory.** `TEMPLATE_DIR` becomes `global-claude/templates`, reaching
`planning/` as well.

The argument is P-0's own, one directory up. P-0 exists because moving the
templates without moving the pointer once produced six passes over zero
templates; today a second directory is watched by nothing, so a seventh
template could be added beside the two scaffolds and never be seen, suite
green throughout.

This ADR writes no test code. It states what the widened checks must
assert:

- Every template declares `template-tier:` with a value from the closed set
  `{contract, scaffold}`. **An absent, misspelled or unrecognised value
  fails.** It is never treated as the laxer tier.
- P-1 branches. Contract: today's three findings, unchanged. Scaffold:
  `seeded-by:` resolves to a committed skill, `unowned-because:` is
  non-empty, and `artifact:`, `owner:` and `ceiling-*` are absent. A
  scaffold carrying contract keys is miscategorised and fails.
- P-0 guards each tier separately. Both branches degrade to silence over an
  empty set, which is the whole reason P-0 is in the file.
- P-3, P-4, P-5 and P-7 select contract templates by `template-tier:`, not
  by whether a frontmatter lookup happened to return bytes.
- P-7 covers both tiers — `owner:` for contract, `seeded-by:` for
  scaffold — so every template has at least one declared skill that must
  resolve.
- Each widened check is negative-controlled before it is believed, and the
  control is recorded in the file's header beside the existing dated
  entries.

The first is load-bearing: keying the tier on a *missing* `artifact:` would
let a typo — `artifcat:` — silently demote a contract template, after which
four checks pass over it. The likeliest mistake would be answered by
checking less.

**3. Templates carry no version, and the markers that exist are
decorative.** `docs-as-code-workflow-template.md:2`, `design/SKILL.md:7`
and this repository's instantiated
[`docs-as-code-workflow.md`](../designs/docs-as-code-workflow.md)`:2` each
carry `1.0.0`, in three different syntaxes. Nothing compares them, and this
ADR does not make anything compare them.

The reason is evidence. **All three read `1.0.0` today while disagreeing on
two things**: where the Case E trigger sits in the selection tree (#100),
and whether the ADR format includes `## Alternatives considered`. Three
numbers agreeing is not three documents agreeing, and a number that must be
bumped in three places is three places to forget. `base/entrypoint.sh`
reached the same conclusion for the commit-msg hook and compares contents
instead — which cannot be borrowed here, because an instantiated document
is *meant* to differ from its template.

#100 asks for the marker to be made load-bearing. This declines, and
decision 5 removes the duplication that makes the drift possible — the
structural answer a version number was standing in for.

**4. Three channels, each chosen by what must happen to its content.**
Frontmatter carries what a check reads and is deleted whole.
`<!-- comment -->` carries a prose instruction and is deleted.
`<token>` marks a substitution that survives into the output. In one
sentence: *anything that must be replaced is a token; anything that must be
deleted is a comment; anything a check reads is frontmatter.*

Both channels are kept because they fail asymmetrically: a leftover token
is visible in the rendered document, a leftover comment is not — which is
why `design/SKILL.md:50-53` carries a step whose only job is "Verify that
no `<!-- ... -->` comment blocks remain in the output."

The comment channel is load-bearing rather than stylistic. The check that
measures an artifact's sections skips comment runs, and that skip is what
lets P-8 tell an unfilled `## Decision` from a filled one.

**5. A format already carried by an injected skill gets no template file.**
The `design` skill's Step 6a is the single declared format for a design
document and Step 6b the single declared format for an ADR. Neither gets a
template file. The duplicate skeletons — `docs-as-code-workflow.md` §3 Case
C and its verbatim copy in the workflow template, and both files' Case D
ADR blocks — are replaced by a citation of the skill.

This applies ADR 003 literally rather than by analogy. Its rung 1 is
"Artifact template **or format spec**", and its applied table already
counts a skill body as a rung-1 carrier: *"Record rejections and their
appeal | Rung 1, carried | Cite `design/SKILL.md`; write nothing."* ADR 002
decision 6 supplies the rest — if a format already has a carrier, cite it
and stop.

The admission test for any future template file: **does a skill already
loaded at the moment of authorship carry the format?** If yes, cite it and
write nothing.

**5b. Precedence splits rather than looping.** `design` Step 1 says a
project's workflow document takes precedence over the skill's defaults,
which would be circular if Case C then cited the skill. It is not, once
Case C names rather than defines: **the workflow document governs which
case applies and what artifacts are produced; the skill governs the shape
of a design document and of an ADR.** A project wanting a different shape
writes one into its own workflow document — a definition, not a
restatement — and the skill defers as it already does.

**5c. The deletion is lossless**, and the mapping is recorded so that is
checkable rather than asserted:

| §3 Case C section | Step 6a home |
|---|---|
| Current structure | `## Context` |
| Target structure | `## Decision` |
| Motivation | `## Context` |
| Migration path | `## Implementation plan` |

Step 6a additionally requires `## Status`, `## Consequences` and
`## Alternatives considered`, which Case C's four do not. The deletion
gains coverage rather than trading it.

Citing the skill from the workflow template is legal under ADR 005 decision
1: the template ships only into projects where `design` is injected, so
`~/.claude/skills/design/SKILL.md` is a path inside the injected layer,
which that decision permits by name.

**6. What this does not decide.** The user-guide template, and #46's open
question of whether a guide for this sandbox and one for a mounted project
are one template or two — decision 5's admission test is what that work
applies. #100's Case E hoist. #78's other instances. The values of the
Planning ceilings. ADR 003's ladder, unchanged.

**The sixteen committed design documents are not reshaped.** The convention
binds templates and the documents written against them from here. Design
documents and ADRs are historical records; rewriting nine of them into a
shape they were not written in destroys provenance and changes nothing
about what gets written next.

## Consequences

A template's tier is visible in its own frontmatter, so "why does this file
not declare an owner" is answered in the file rather than by reading two
ADRs. The scaffolds stop being the files nothing checks. The cost is a key
on every template and a branch in P-1.

**Decision 2 also closes a latent near-miss.** P-5 passes today only
because a frontmatter lookup for a missing key emits zero bytes rather than
a blank line; a blank line would have made it fail on exit status with
empty output — a failure with no diagnostic. Selecting by tier states the
property instead of inheriting it from a `sed` detail.

**Decision 2 obliges someone to redo negative controls.** This suite's
value rests on dated observations of each check failing against a broken
fixture. Widening `TEMPLATE_DIR` and branching P-0 and P-1 invalidates
those observations for the checks it touches. A check believed to fire and
never re-observed is worth less than one left alone, so the re-control is
part of that work rather than a follow-up to it.

**Decision 5 returns budget.** Removing two duplicated skeletons from
`global-claude/` and adding citations back nets roughly thirty lines
against D-7's ceiling. This ADR itself lives in `docs/adr/` and costs
nothing against it.

**Decision 3 leaves a real gap open.** A project seeded from a scaffold
years ago has no way to tell that the scaffold has moved on, and this ADR
supplies none. That gap is unobservable from this repository by
construction — the seeded document lives in a repository this one has never
seen — so nothing written here could have closed it. What decision 5 closes
is the *other* half: drift between two copies that both live here.

**Nothing asserts that an author reads a template at all.** ADR 003 already
records this as rung 1's unmitigated weakness: a rung-1 rule fires only if
the template is reached for. The checks named in decision 2 assert that
templates are well-formed, never that one was used.

## Alternatives considered

**Chose:** two tiers, contract and scaffold.
**Rejected:** one convention — `artifact:`, `owner:` and ceilings on all
six templates.
**Why the rejected option is attractive:** one shape means one parser, one
P-1, and no tier key to declare or mistype; decision 2 collapses to
widening a path. It is also what #46 asks for in so many words — "whether
they share one shape".
**What breaks if you try it anyway:** `planning-index.md`'s `owner:` has no
honest value, and a plausible one makes P-7 resolve a skill that does not
own the file. `artifact: docs/planning/README.md` is worse: P-3 demands a
row pointing at itself while P-4 never finds the artifact — a check both
too strict and vacuous. And a ceiling on a 386-line workflow document is a
number chosen to be unreachable, which teaches the next author that
ceilings are decorative.

**Chose:** widen `TEMPLATE_DIR` to `global-claude/templates`.
**Rejected:** keep it pinned to `templates/planning`.
**Why the rejected option is attractive:** no test change, and no
obligation to redo the dated negative controls that give this suite its
value.
**What breaks if you try it anyway:** the two templates this ADR was
written to govern remain the two templates nothing checks, so the
convention is prose for exactly the files that provoked it — and a seventh
template can be added beside them and never be seen.

**Chose:** an explicit `template-tier:` whose absence fails.
**Rejected:** inferring the tier from whether `artifact:` is present.
**Why the rejected option is attractive:** no new key, no migration of the
four existing templates, and the inference is correct for all six files as
they stand today.
**What breaks if you try it anyway:** a typo in `artifact:` silently
reclassifies a contract template as a scaffold, and four checks begin
passing over it. The likeliest mistake is answered by checking less, and a
convention whose lax tier is the default erodes without anything turning
red.

**Chose:** no version marker, declared decorative.
**Rejected:** making the marker load-bearing — a check that the template,
the skill's declaration and this repository's instance agree.
**Why the rejected option is attractive:** it is what #100 asks for by
name, the three markers already exist, and a three-way comparison is a few
lines of `bats`.
**What breaks if you try it anyway:** it detects nothing it was built for.
All three markers read `1.0.0` today while disagreeing on Case E *and* on
whether `## Alternatives considered` exists, so the check passes on the
exact state that motivated it. A check that certifies the condition it was
built to catch is worse than no check.

**Chose:** scaffolds carry no version either.
**Rejected:** a `template-version:` on scaffolds only, declared unenforced,
as provenance.
**Why the rejected option is attractive:** the asymmetry is real. A
scaffold's output lives in another repository and outlives the template,
and a stamp is what lets a person reading that document in two years date
the seed. It costs one key and promises nothing.
**What breaks if you try it anyway:** a stamp nothing compares is the rule
nobody can fail that this project keeps finding and removing. It would be
the first convention admitted here on the strength of being cheap rather
than on being checkable, and the next one would cite it.

**Chose:** delete the duplicate skeletons; cite `design` Steps 6a and 6b.
**Rejected:** reconcile the structures into one merged skeleton, and give
the design document a template file for symmetry with the Planning four.
**Why the rejected option is attractive:** it is #78's first-listed remedy,
"align the artifacts". A directory where every declared format is a file is
easier to explain than one where some live in skill bodies, and a template
file could carry ceilings where Step 6a cannot.
**What breaks if you try it anyway:** reconciliation produces a third
shape, so the seven committed documents that follow Step 6a exactly become
non-conforming and the count of divergent shapes rises rather than falls. A
template file adds a second carrier for one format, which is how the
present defect was made: two copies under one version number, diverging
silently for months.

## References

- #46 — settle the shared template convention; #78 Instance 2 — the three
  declared design-document structures; #100 — the version marker's larger
  half
- [ADR 002](002-planning-artifact-contract.md) — decision 2 (one owner per
  path), decision 5 (ceilings), decision 6 (cite, do not restate), decision
  7 (enforced by a test)
- [ADR 003](003-where-a-behavioural-rule-goes.md) — rung 1 and its
  unmitigated weakness; the applied table naming a skill body as a carrier
- [ADR 005](005-citing-across-the-repo-boundary.md) — decision 1, which
  permits `~/.claude/…` paths and which this ADR follows in qualifying an
  earlier decision rather than rewriting it
- [`auto-memory-seeding.md`](../designs/auto-memory-seeding.md) — the
  document that drew on all three structures
- `tests/test_planning_artifacts.bats` — P-0 through P-8, and
  `TEMPLATE_DIR`
- `global-claude/skills/design/SKILL.md` — Steps 1, 6a and 6b
