# Global-layer size bounds per load class

## Status
Accepted

## Context

#128 asks what D-7's 3000-line ceiling on `global-claude/` should be.
Planning closed with a go on 2026-10-25
([`charter.md`](../planning/0128-global-layer-line-ceiling/charter.md)
§Decision). The charter recommends #128's option 3 under one condition
(§Recommendation): replace the count across the whole tree with bounds per
load class, and write the description bound as a policy figure with its
assumptions stated. The evidence is in
[`prior-art.md`](../planning/0128-global-layer-line-ceiling/prior-art.md)
§Findings, and this document does not restate it.

The operator added #128's option 1, the trim that the scope deferred
([`scope.md`](../planning/0128-global-layer-line-ceiling/scope.md)
§Non-goals). This design takes it in.

Under the new accounting, the trim is judged by the class each line falls
in. A line removed from a skill description saves context in every session.
A line removed from a skill body saves context only when that skill is
invoked. A line removed from a template saves context only when the
template is read.

### Classification

This is Case C. The change spans `tests/test_docs_integrity.bats`,
six skills under `global-claude/skills/`, `ci.yml`'s floor, and three
documents. It changes what a named STRIDE control measures, which is
design 0003 §5.2's Denial of Service entry. It is not Case E: no file in
that trigger list changes. It is easily reversed, so it is not Case D.

## Decision

**1. D-7 is retired, and its ID is not reused.** The check, its constant and
its rationale comment are removed. The SDD row stays, marked retired with
a pointer here, so references to D-7 in ADRs 007 and 011 and in earlier
designs still resolve to a record.

**2. D-6 is unchanged.** Its 200 lines is the vendor's own figure for a
CLAUDE.md file. Its comment changes to cite that guidance instead of design
0003's illustration.

**3. D-15: the description listing.** For every
`global-claude/skills/*/SKILL.md`, the description is extracted and joined
into one line, accepting the two forms D-8 accepts. The check fails if:
- any single description exceeds **1,536 characters**, the vendor's
  truncation cap for each entry; or
- the descriptions together exceed **6,000 characters**.

6,000 is a policy figure, chosen by the operator on 2026-10-25. It derives
from three assumptions, stated in the check's comment:
- a 200k-token window, the smaller of the two in use;
- the vendor's listing budget of 1% of that window;
- about four characters per token, which the vendor does not document.

On those assumptions the budget is about 8,000 characters. 6,000 leaves a
quarter of it for plugin and synced skills, which this repository cannot
count. The comment cites the skills documentation URL and the date it was
checked, 2026-10-24. If the vendor's rule changes, the figure is
re-derived, not raised.

**4. D-16: skill length.** Every `global-claude/skills/*/SKILL.md` stays
within **500 lines**, the vendor's guidance. The figure includes
frontmatter, matching how the vendor states it.

**5. On-read files get no bound, deliberately.** Templates, hook scripts,
`settings.json`, and the skill changelogs from decision 6 enter context
only when something reads them. Bounding them in lines would bring back the
measure the research found no basis for. Their growth stays visible in
review. A template is read only by the skill that names it, and that
skill's length is bounded by D-16.

**6. Trim: skill changelogs move out of `SKILL.md`.** Each `## Changelog`
section moves verbatim into a `CHANGELOG.md` beside its `SKILL.md`. Six
skills have one, 101 lines in total, and they are context paid on every
invocation that no instruction uses. Each `SKILL.md` keeps no pointer to
its changelog: one would cost a line on every invocation and serve only a
maintainer, who finds the file by listing the directory.

**7. Trim: descriptions come down to at most 6,000 characters.** From 6,731,
that is at least 731 characters removed. Only text that is not trigger or
routing is removed: rationale, and preconditions that the body already
states. Each removed clause is listed in its commit with where the body
carries it, so ADR 003 decision 3's split is kept: the trigger stays in
the description and the procedure stays in the body. Candidates:
- project-planning's headless and Decision-section clause;
- project-feasibility's "declines without it";
- mechanism-verification's two rationale sentences;
- swe-prior-art-research's twice-stated mutual exclusion.

**8. The hook's output is accepted unbounded.** It is two lines, printed
only when a project has no user guide. A check on two lines costs more
than the risk it would bound. The rationale comment for D-15 and D-16
records this, so the omission is visible.

**9. Design 0003 §5.2 is corrected in place.** Its Denial of Service control
says context cost is "bounded by the total size of injected Markdown
files". That is wrong for skills, whose bodies load on invocation. The
section is changed to name D-6, D-15 and D-16, and the change is recorded
as a Version 1.2 entry in its Changelog.

## Consequences

**The check fails on what costs context.** D-7 was 184 lines from failing,
and most of the lines it counted cost nothing per session. D-15 fails on
the description growth that would silently drop other skills' descriptions
from the listing.

**The description bound is a policy figure.** It rests on an undocumented
characters-per-token ratio. If the operator only ever runs a 1M window, it
binds about five times harder than the vendor's budget requires. That is
accepted and stated at the check rather than hidden in the figure.

**The figures go stale silently.** The vendor's 1%, 1,536 and 500 are
versioned behaviour. The citation and the date checked at each constant
are the only mitigation. Nothing re-checks them automatically.

**Removing description text risks mis-triggering, and nothing checks for
it.** Routing text was put into descriptions on purpose (ADR 006
decision 6), and decision 7 keeps it. Whether a trimmed description still
fires is not machine-checked here. That is rung 2 by ADR 003, and the
per-clause record in each commit is what makes a regression traceable.

**On-demand growth loses its tree-wide bound.** A new template or hook
script grows the layer without failing anything. That is the trade
decision 5 makes.

**#135's motivation is affected.** It argues that every line costs context
in every session. After this change only descriptions do. Updating #135 is
left until this design is accepted, at the operator's request.

**ADR 011 decision 4 is unblocked.** It deferred an injected template copy
until the D-7 question resolved. A template is on-read, so it costs nothing
against D-15 or D-16. Picking that up is a separate change.

## Alternatives considered

**Keep D-7 and restate its rationale as policy (#128 option 2).** It is
attractive because nothing changes and growth stays capped. It was rejected
because the charter's condition for this was an operator wish for a growth
cap for its own sake, and the operator chose option 3. It would also go on
failing on on-read lines, which cost nothing per session.

**Raise D-7.** It is attractive because it is one constant. It spends the
decision without making it, which is the trap #146 names.

**Deduplicate the `<bundle>` definition** that four skills repeat, by
citing the planning-bundles template (#128 option 1's first candidate).
It is attractive under ADR 003 decision 4, no restatement. It was rejected
for three reasons:
- each copy carries a different failure branch: stop, stop unless someone
  is present, or continue without a charter. Those branches stay, so the
  saving is about three lines per skill;
- the saving falls in bodies, paid on invocation only;
- the citation adds a file read at the exact step that resolves paths,
  and a skipped read there fails silently.

**Measure in tokens instead of characters.** It is attractive because the
vendor's budget is defined in tokens. It was rejected because a test cannot
tokenize without a model-specific tokenizer in the image. Characters with a
stated ratio is the honest approximation.

**Bound each description below 1,536 characters**, for example at the 1,024
characters some secondary sources attribute to the open Agent Skills
specification. That figure could not be verified: the specification's site
was refused by the egress proxy on 2026-10-25. The vendor's cap is the one
documented.

## Implementation plan

1. **This design document.** `docs(design): design for global-layer bounds
   per load class (#128)`.
2. **Move the skill changelogs** to `CHANGELOG.md` beside each `SKILL.md`
   (decision 6). One commit, six skills, contents unchanged.
3. **Trim the descriptions** to at most 6,000 characters (decision 7). Use
   one commit per skill, each listing what was removed and where the body
   carries it.
4. **Add D-15 and D-16, and retire D-7** (decisions 1 to 4 and 8). Rewrite
   the rationale comment, and negative-control each check:
   - push one description past 1,536;
   - push the total past 6,000;
   - pad one `SKILL.md` past 500 lines.

   Watch each fail, revert, and record the result in the comment. Raise
   `ci.yml`'s `HOSTONLY_FLOOR` from 50 to 51, since D-7 goes and two checks
   arrive.
5. **Update the testing SDD.** In
   `docs/designs/0011-claude-sandbox-testing-module-sdd.md`, retire the D-7
   row and add rows for D-15 and D-16. Fix the §citation table, bump the
   version and add a Revision History row.
6. **Correct design 0003 §5.2** (decision 9).
7. **Closing commit** (closes #128). Then comment on #135, and note on
   #146 that #128 is done.
