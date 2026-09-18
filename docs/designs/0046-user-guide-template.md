# User-guide template

## Status

Accepted

## Context

Issue #46 carries two deliverables. The first, the shared template
convention, landed as [ADR 007](../adr/007-shared-template-convention.md).
This is the second: a committed template declaring what a user guide
contains, so that #47 — which proposes offering one when a project lacks it
— has something to propose.

Three facts constrain the shape before any section list is chosen.

**The repository's own workflow document does not know what a user guide
is.** `docs-as-code-workflow.md` §2.2's document-type table has rows for
commit messages, issues, plans, design documents, ADRs, planning artifacts,
`BUILDING.md`, `ARCHITECTURE.md`, security documents and operational guides.
There is no user-guide row, and the same omission ships in the template. The
nearest row, "Operational guide", covers setup and operational procedures for
infrastructure components, which is not the same document. A row states a
location and a lifespan; neither can be assumed.

**`docs/user-guide.md` is entirely sandbox-specific in content, and its
shape is not.** All seven of its sections and all twelve of its relative
links describe claude-sandbox: profiles, `start.sh`, the global instruction
layer, Strategy A/B. Nothing in it addresses a project mounted at
`/workspace`. But its framing — a task-oriented document that defers build
commands to `BUILDING.md` and internals to `ARCHITECTURE.md` — is the most
portable thing in the file, and is precisely what the missing table row has
to say.

**A template shipped in `global-claude/` cannot carry repo-relative links.**
[ADR 005](../adr/005-citing-across-the-repo-boundary.md) decision 1 permits
only target-relative paths or paths inside the injected layer. All twelve of
`docs/user-guide.md`'s links die under that rule, so the template is not a
copy of that document with the specifics removed — the links are structural,
not incidental, and the template must be written without them.

## Decision

### 1. One scaffold template, at `global-claude/templates/user-guide.md`

ADR 007 decision 1 admits a template as a **contract** only if all three
hold: the output lands at a path the convention fixes, exactly one skill
writes it, and its sections have a length a ceiling can bound. A user guide
fails the first two — a project chooses where its guide lives and owns it
from then on. It is therefore a **scaffold**, carrying `seeded-by:` and
`unowned-because:` and none of `artifact:`, `owner:`, `phase:` or `ceiling-*`.
P-1's scaffold branch fails it otherwise.

ADR 007 decision 5's admission test asks whether a skill already loaded at
the moment of authorship carries the format. For a design document and an ADR
the answer is yes, and #121 deleted the duplicates accordingly. For a user
guide the answer is no — no injected skill carries one — so a template file
is admitted. Recording both outcomes is what makes the test a rule rather
than a rationalisation applied after the fact.

**One template, not two.** #46 asks whether a guide for the sandbox and a
guide for a mounted project are the same shape. They are: the differences
between them are entirely content, and the sections below hold for both.
Writing two would add a fourth and fifth template shape, which is the
outcome ADR 007 exists to prevent.

### 2. `design` seeds it, and its Step 1 says so

`seeded-by:` must resolve to a committed skill, and P-7 checks it. Declaring
`seeded-by: design` while `design` seeds nothing would pass P-1 and P-7 —
both check the skill is committed, not that it seeds anything — and would be
a declaration nothing backs.

So `design`'s Step 1 "explicit setup request" path gains one step: after
saving the workflow document, offer a user guide seeded from this template.
The path already writes the document-type table that gains the user-guide
row, so seeding the document that row describes is coherent rather than
bolted on.

**It is an offer, not an action.** The setup path is entered on an explicit
request to initialise the workflow, and a project that wants no user guide
must be able to decline in one word. This is deliberately narrower than #47,
which inspects the mounted project on every session start and is a judgment
this does not make.

### 3. The section list

Derived from `docs/user-guide.md` by keeping what survives generalisation:

| Section | Kept because |
|---|---|
| Preamble: what this document is for, and what defers to `BUILDING.md` / `ARCHITECTURE.md` | The most portable thing in the source; also what the doc-type row has to state |
| Everyday operations | `Starting a session` generalises to "the two or three things a user does most" |
| Configuration and modes | `Choosing a profile` generalises to "how to pick between variants", optional where a project has one mode |
| Credentials and access | `Authenticating a session` generalises; optional, and explicitly so — a project with no credentials should delete it rather than write "none" |
| Extending it | `Adding a tool` generalises to "how to add to this, and what not to do" |
| Troubleshooting | Generalises unchanged; symptom, cause, fix |
| Where to go next | `Running the test suite` generalises to pointers out |

Dropped: `The global instruction layer`, which is a claude-sandbox concept
with no counterpart in a mounted project.

### 4. The document-type row

Added to `docs-as-code-workflow.md` §2.2 and to the shipped template:

| Type | Location | Purpose | Lifespan |
|---|---|---|---|
| **User guide** | `docs/` (project chooses the filename) | Task-oriented day-to-day usage; defers build commands to `BUILDING.md` and internals to `ARCHITECTURE.md` | Living document |

The location column states a directory rather than a path because the tier
says the project chooses. That is the same fact `unowned-because:` records,
in the place a reader of the workflow document will look.

### 5. `docs/user-guide.md` is not reconciled here

Deriving the template from it is in scope. Editing it to match is a separate
logical change, and bundling the two would make the diff argue for itself.

## Consequences

**Easier.** #47 becomes buildable: it can propose a user guide because one is
now defined. An SDD template, named in #46's comment as the next consumer,
has a worked second example of the scaffold tier to follow.

**Harder.** `design` grows, and the setup path now produces two documents
where it produced one. The offer is one more thing a setup run can get wrong.

**Cost against D-7.** The global layer is at 2513 / 3000. The template is
roughly 55 lines and the `design` step roughly 10, so about 2578 — inside the
ceiling, with the headroom #121 returned covering most of it.

**A declaration that outruns its mechanism is avoided, not eliminated.**
`seeded-by: design` becomes true when Step 1 seeds it. Nothing asserts that
it stays true: P-7 checks the skill exists, not that it still seeds anything.
If the step is later removed, the frontmatter silently becomes a lie. That is
the same class of gap as #113 and is not closed here.

## Alternatives considered

**Chose:** one generic template, mounted-project-shaped.
**Rejected:** two templates, one per audience.
**Why the rejected option is attractive:** the two guides really do differ in
content, and #46 flags the question as scope-changing, so splitting looks
like the cautious reading.
**What breaks if you try it anyway:** the differences are content, not shape
— every section above holds for both — so the second template would duplicate
the first with different examples. That is two shapes to keep in sync and the
fourth and fifth template forms in the repository, which is the cost ADR 007
was written to stop.

**Chose:** `design` seeds it from its existing setup path.
**Rejected:** ship the template now and let #47 build the seeder.
**Why the rejected option is attractive:** #47 is where a user-guide
mechanism belongs, it inspects the mounted project rather than this one, and
adding a step to `design` pre-empts a design not yet written.
**What breaks if you try it anyway:** the template cannot declare a true
`seeded-by:` in the meantime, and the only passing alternative is naming a
skill that does not seed it — a declaration nothing backs, in a repository
that has filed #113, #101 and #81 about exactly that. #47 remains free to add
a session-start mechanism later; this does not occupy that ground.

**Chose:** scaffold tier.
**Rejected:** contract tier with per-section word ceilings.
**Why the rejected option is attractive:** ceilings are the mechanism that
stops a document sprawling, and a sprawling user guide is the obvious failure
mode. The contract tier is also the better-tested branch.
**What breaks if you try it anyway:** ADR 007 decision 1 makes the tier a
consequence of three facts, not a preference — the path is project-chosen and
no single skill writes the output, so two of three fail. Declaring it a
contract would require an `artifact:` path that is false for every project
that puts its guide anywhere else, and P-1 would be asserting a path nothing
writes.

## Implementation plan

1. `docs(designs)`: this document. **First commit on the branch.**
2. `feat(templates)`: add `global-claude/templates/user-guide.md` — scaffold
   frontmatter, the seven sections, authoring comments, no repo-relative
   links.
3. `feat(skills)`: extend `design` Step 1's setup path to offer a user guide
   after saving the workflow document.
4. `docs(workflow)`: add the user-guide row to the document-type table in
   `docs/designs/docs-as-code-workflow.md` and in the shipped template.
5. `docs`: closing commit referencing #46.

Verification at each step: P-0, P-0c, P-1, P-7 and D-2, D-7, D-9 by
extracting the helpers and calling them directly, each probe first confirmed
to report against deliberately broken input. `bats` reaches the image in
#118, which is open and not merged, so the suite's own wiring stays
unexercised from a session. CI is the authority.
