# ADR 012 — Diagram form in every project the sandbox is pointed at

## Status

Accepted

## Context

[ADR 011](011-diagram-form-criterion.md) decision 4 kept the diagram-form
criterion in this repository only. It deferred the copy for other projects
until the D-7 question was settled, and named the cost: the `design` skill
draws diagrams everywhere, but its criterion exists only here. #164 tracks
that deferral.

Two things have changed since then.

**#128 retired D-7.** Design
[`0128-global-layer-load-class-bounds.md`](../designs/0128-global-layer-load-class-bounds.md)
bounds the injected layer by load class. A line in a skill body is paid
only when that skill is invoked, and D-16 bounds the body at 500 lines.
`design/SKILL.md` is 339.

**The injected copy ADR 011 had in mind would reach fewer projects than
it seems.**
- [ADR 005](005-citing-across-the-repo-boundary.md) decision 1 requires an
  injected file to carry its claim inline. A citation of ADR 011 is
  provenance, and a project the sandbox is pointed at cannot read it. So
  any injected carrier holds the criterion itself.
- The workflow document is read in one place: `design` Step 1. Wherever
  the criterion goes, it is read while `design` runs.
- A copy in the workflow template reaches only projects seeded after the
  change. ADR 007 decision 3 records that a seeded document never hears
  from its template again.

## Decision

**1. The `design` skill carries the criterion inline,** in Step 6a, with
Step 6b pointing to it. The text is ADR 011 decision 1's four bullets, and
its note that a diagram may accompany an ordered list. The source is named
as "ADR 011 of the claude-sandbox project", as ADR 005 decision 1 requires.
This supersedes ADR 011 decision 4: the criterion applies in every
project, not this repository only.

**2. ADR 011 stays the criterion's home.** It holds the decision and its
trade-offs. The skill holds a copy so the criterion reaches projects that
cannot read ADR 011. This qualifies ADR 011 decision 1's "only home": the
skill holds a checked copy for delivery and is not a second place to
change it. A change to the criterion is a new ADR, as before, and then
the skill follows.

**3. D-17 checks the copy.** It reads ADR 011 decision 1's bullets, joins
their wrapped lines and drops emphasis markers. It fails if any bullet is
missing from `design/SKILL.md` normalized the same way. The check is
negative-controlled before it is believed.

**4. Unchanged:**
- **The workflow template.** Projects seeded from it get the criterion
  through the skill.
- **ADR 011 decision 2.** This repository's workflow document still cites
  ADR 011.
- **ADR 011 decision 3** stays local. Its reason is that D-1 and D-11,
  this repository's link checks, cannot see a path inside a fence.
  Another project has neither check.

**5. Precedence follows ADR 007 decision 5b.** The skill governs the shape
of a design document and an ADR, and diagram form is part of that shape. A
project that writes its own rule into its workflow document overrides the
skill's copy, because `design` Step 1 defers to that document.

## Consequences

The criterion reaches every project at the moment it applies. That
includes projects seeded before this change and projects with no workflow
document. It reaches them through the injected skill, so removing it is an
edit here, not a change scattered across other repositories.

It costs about nine lines each time `design` runs, in every project. It
adds nothing to D-15's description budget, which has 203 bytes of
headroom (#179).

There are now two copies of the criterion in this repository, the ADR and
the skill. D-17 is the reason that is acceptable: ADR 007's Context
records two unchecked copies drifting for months under one version
number.

D-17 holds the skill to text that is never rewritten. A superseding ADR
that changes the criterion must also repoint the check. It fails until it
does, which is the intended direction.

The reach is no wider than before. The criterion is read only while
`design` runs, so a diagram drawn in a README or a user guide outside
`design` still has nothing to measure it against. ADR 011's
unenforceability consequence stands: nothing asserts that an author
applies the criterion.

## Alternatives considered

**Chose:** the `design` skill.
**Rejected:** the workflow template's §2.2, as ADR 011 decision 4 and #164
first named it.
**Why the rejected option is attractive:** it is the carrier ADR 011
already chose for this repository, so every project would look the same.
The seeded copy belongs to the project, which can edit it. And it costs
nothing at load time.
**What breaks if you try it anyway:** it reaches only projects seeded
after the change, and ADR 007 decision 3 says nothing tells an older
project the template moved. It is read at the same moment as the skill,
during `design` Step 1, so it buys no reach the skill lacks. It also
leaves a second copy here with no check able to compare it, because an
instantiated document is meant to differ from its template.

**Chose:** carry the criterion.
**Rejected:** close #164 and make ADR 011 decision 4 permanent.
**Why the rejected option is attractive:** the failure is benign. A
project with no criterion draws diagrams by judgment, not by an invented
rule, and nothing new is loaded anywhere.
**What breaks if you try it anyway:** the asymmetry ADR 011 recorded as a
defect stays. The skill that draws diagrams is global and the rule
governing it is not. Its deferral was conditional on D-7 alone, and that
condition is gone.

**Chose:** one checked copy.
**Rejected:** a copy with no check, held by ADR 011's rule that the
criterion changes only through a new ADR.
**Why the rejected option is attractive:** no test to write or maintain.
The copy is short, and the ADR rule already says where a change must
start.
**What breaks if you try it anyway:** a rule nobody can fail. An edit to
the skill's bullets would change the criterion in every project while
ADR 011 still read the old way, and nothing would turn red. That is ADR
007's evidence, repeated on a smaller file.

## References

- [ADR 011](011-diagram-form-criterion.md) — decision 1 (the criterion),
  decision 4 (superseded here), and the unenforceability consequence
- [ADR 005](005-citing-across-the-repo-boundary.md) — decision 1, the
  claim carried inline
- [ADR 007](007-shared-template-convention.md) — decision 3 (seeded copies
  go stale), decision 5b (precedence), and the drift recorded in its
  Context
- [`0128-global-layer-load-class-bounds.md`](../designs/0128-global-layer-load-class-bounds.md)
  — retired D-7 and added D-16
- #164 — the deferral this resolves; #99 — the criterion's origin; #179 —
  the description budget
