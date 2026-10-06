# ADR 011 — Diagram form, and where that criterion lives

## Status

Accepted

## Context

[#99](https://github.com/fer-osorio/claude-sandbox/issues/99) settled what
form a diagram should take in this repository and recorded the trade-offs
behind it. Its own framing is that *"the deliverable is the criterion, not
the conversion."* The criterion is in a GitHub issue.

An issue is not a carrier. Nothing loads it at the moment someone is about
to draw a diagram, and it stops being read at all once it closes. The
criterion has already been applied twice — converting one diagram and
refusing another, both recorded on #99 — and both times by a reader who
happened to open the issue. That access pattern does not survive it.

[ADR 003](003-where-a-behavioural-rule-goes.md) ranks three placements and
admits the most specific that fits. Rung 1 is an artifact format spec, and
one exists: [`docs-as-code-workflow.md`](../designs/docs-as-code-workflow.md)
owns what format a document must follow, and the `design` skill's Step 1
already reads it and defers to it. That is a carrier at the point of
writing for no always-on cost, which is what rung 1 is for.

Two further facts bound the decision. The injected copy,
`global-claude/templates/docs-as-code-workflow-template.md`, would reach
every project the sandbox is pointed at — but D-7's ceiling stands at 2793
of 3000 lines and #128 is rationing what remains. And D-1 strips fenced
code blocks before link-checking while D-11 does not, so whether a path
inside a diagram is machine-checked depends on how it is written.

## Decision

**1. The criterion lives in this ADR, and this is its only home.**

- A diagram earns its place only when the relationship is **not
  expressible as an ordered list**: branching, cycles, or more than one
  path between two nodes.
- Branching or sequenced flow → mermaid.
- Containment that is genuinely a tree, such as a file listing → keep the
  fenced tree. Mermaid makes it worse.
- A picture of a table → a table.

A diagram may accompany an ordered list rather than replace it. Mermaid
does not render in a terminal, which is where both the operator and an
agent read these most often, so the list is not redundant when both are
present.

**2. `docs-as-code-workflow.md` cites this ADR and does not restate it.**
One line, in the document the `design` skill already reads. ADR 003
decision 4 forbids a second copy, and the format spec is the carrier, not
the home.

**3. A diagram may not be the only place a path is named.** A relative
link inside a fenced block is checked by neither D-1 nor D-11: D-1 skips
the fence, and D-11 matches only tokens beginning `docs/`. Any path a
diagram depends on is therefore also named in prose beside it.
[`pipeline.md`](../planning/pipeline.md) is written to this rule and is the
worked example.

**4. This repository only.** The injected template copy is deferred until
the D-7 budget question resolves, tracked on #128 and #146. Until then a
project without this ADR has no criterion, which is the cost decision 4
accepts rather than hides.

**5. #99 stays open.** Decision 1 supersedes its *Criteria first* section.
Its diagram inventory and its opportunistic conversion policy are
untouched, and the conversions themselves are still outstanding.

## Consequences

The criterion becomes citable. `ADR 011 decision 1` resolves for a reader
who was not present at the discussion, which an issue body does not once it
closes.

Placement costs nothing always-on. Rung 1 was available, so under ADR 003
decision 2 rung 3 was never admissible — this ADR spends no line of D-6's
budget and no line of D-7's.

Against that:

**Decision 2 is rung-2 enforcement, and this ADR is rung 3 of the
enforcement ladder — prose.** Nothing asserts that an author reads the
criterion before drawing a diagram, and no check can: #99's conversion
policy is deliberately opportunistic, so a blanket box-drawing check would
fail on roughly 350 existing lines, and asserting "no *new* ones" needs
diff-aware checks this suite does not have. The criterion is unenforceable
by construction and is recorded here as such rather than left to look like
an oversight.

**Decision 4 leaves the rule project-local while the skills that draw
diagrams are global.** This is the same asymmetry ADR 004 names in its own
Context: a rule that assumes a document exists does not fail loudly where
it does not. Here the failure is benign — no criterion, rather than an
invented one — but it means the injected `design` skill can produce a
diagram in another repository with nothing to measure it against.

**Decision 3 is narrow and will be read as broader than it is.** It
constrains where paths are written, not whether diagrams may cite
anything. An author who reads it as "no paths in diagrams" loses legible
node labels for no benefit.

## Alternatives considered

**Chose:** this ADR as the home, cited from `docs-as-code-workflow.md`.
**Rejected:** a new §Diagram form section in `docs-as-code-workflow.md`,
with no ADR.
**Why the rejected option is attractive:** one file instead of two, the
rule sits in the document that is actually loaded, and it needs no
indirection for the reader who is already there.
**What breaks if you try it anyway:** the trade-offs go unrecorded. #99's
*Trade-offs on record* — mermaid diffs semantically, against mermaid not
rendering in a terminal — is the half a future reader needs in order to
revisit the rule rather than rediscover it, and a format spec is the wrong
shape for an argument. ADRs are never rewritten, which is the property a
convention meant to be permanent wants.

**Chose:** rung 1, a citation from the format spec.
**Rejected:** rung 3, a line in `global-claude/CLAUDE.md` §Output
discipline.
**Why the rejected option is attractive:** always-on placement is the only
one that cannot fail to load, and the rule is short enough to fit in a
sentence.
**What breaks if you try it anyway:** ADR 003 decision 2 admits rung 3
only by failing rungs 1 and 2, and rung 1 is available here. It would also
land in the section #98 is open against for accumulating wording, paid out
of D-6 at 96 of its 200 lines.

**Chose:** this repository only.
**Rejected:** put the criterion in the injected template now, so every
project gets it.
**Why the rejected option is attractive:** the skills that draw diagrams
are global, so a project-local rule is placed asymmetrically to the thing
it governs — which is a real defect, recorded above as a consequence.
**What breaks if you try it anyway:** it spends D-7 budget that #128 is
mid-decision about, and #128's option 3 may change what D-7 counts at all.
Adding lines to the injected layer while its ceiling is under review
pre-commits that decision from the outside.

**Chose:** prose, with the unenforceability recorded.
**Rejected:** a D-check asserting no new box-drawing diagrams.
**Why the rejected option is attractive:** every other documentation rule
in this repository that matters has a D-check, and this project's own
position is that a rule nothing can fail stops holding the first time it is
inconvenient.
**What breaks if you try it anyway:** the check contradicts #99's
conversion policy. 350 lines across 15 files are grandfathered by
intention, so the only assertable form is about new content, which this
suite cannot express. A check that must be suppressed 15 times teaches that
the contract is advisory — the outcome ADR 002 decision 5 warns about for
ceilings.

## References

- [ADR 003](003-where-a-behavioural-rule-goes.md) — the three rungs,
  decision 2's admission test, and decision 4's no-restatement rule
- [ADR 007](007-shared-template-convention.md) — decision 5, why a format
  an injected skill carries is cited rather than copied
- [`docs-as-code-workflow.md`](../designs/docs-as-code-workflow.md) — the
  format spec decision 2 amends, and the document `design` Step 1 reads
- [`pipeline.md`](../planning/pipeline.md) — the worked example for
  decisions 1 and 3
- #99 — the criterion's origin, its diagram inventory, and the
  conversion policy decision 5 leaves open
- #128, #146 — the D-7 budget question decision 4 waits on
- #157 — the general case: output rules stated where they cannot fire
