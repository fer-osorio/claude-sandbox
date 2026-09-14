# ADR 005 — Citing across the repository boundary

## Status

Accepted

## Context

Everything under `global-claude/` is authored in this repository and read
in another one: the entrypoint copies it into `~/.claude` in every session,
whatever project is mounted at `/workspace` (G-10 asserts the copy). A
repo-relative path written there resolves against the reader's repository,
not this one. Issue #104 lists the instances; a sweep on 2026-09-11 confirms
them and finds no others:

| Citation | Where | In another project |
|---|---|---|
| `docs/designs/docs-as-code-workflow.md §4` | `global-claude/CLAUDE.md:71` | Present only if the project instantiated the workflow template — a condition the line does not state |
| `docs/engineering-principles-by-lifecycle-phase.md` | `CLAUDE.md:76`, `mechanism-verification:26` | Dangling |
| `docs/adr/003-where-a-behavioural-rule-goes.md` | `mechanism-verification:87` | Dangling, or that project's own ADR 003 |
| `docs/designs/project-{planning,feasibility}-skill.md` | `project-planning:164`, `project-feasibility:111` | Dangling; changelog provenance |
| `ADR 001` / `ADR 002`, unqualified | `project-planning`, `project-feasibility`, `swe-prior-art-research`, `templates/planning/charter.md` | That project's own ADR of the same number, if it has one |

Two findings shape the decision.

**The discriminator is direction, not form.** `docs/planning/scope.md` in
`project-planning`, and `docs/designs/docs-as-code-workflow.md` in `design`
Step 1, have the same shape as the defects, but they tell the reader what to
find or create in its own repository, and they are correct. The same path
can be either: `design` says *look for* the workflow document, while
`CLAUDE.md:71` cites it as if it were always there.

**The broken form is mandated.** ADR 003 decision 4 says "cite `path
§section` and stop" — right inside this repository, wrong in a file that
leaves it — which is why the defect recurred in every file written under it.
`templates/planning-index.md` is the one file that already gets this right:
"Name a document; do not link to it", and "ADR 002 of the sandbox project".

`CLAUDE.md:71` is the severe instance. The others carry their claim inline
and lose only provenance. Line 71 delegates the Case-selection criteria that
gate the commit-confirmation rules directly above it, so a session in another
project has the Case names in context and the criteria nowhere.

## Decision

**1. ADR 003 decision 4 is qualified for files under `global-claude/`.**
ADR 003 is not rewritten, and decision 4 holds unchanged for documents inside
this repository. In a file under `global-claude/`, a citation must resolve in
every repository the file is injected into, or be recognisably a name rather
than a path:

- A path is written only when it is target-relative — something the reader's
  repository is told to create or find (`docs/planning/…`,
  `docs/adr/00N-<slug>.md`) — or a path inside the injected layer itself
  (`~/.claude/templates/…`). A path the reader's repository may lack is
  written only with that condition stated in the same sentence.
- Anything that exists only in this repository is named by document and
  project, never by path: "ADR 003 of the claude-sandbox project". That phrase
  is canonical so that the qualifier is greppable;
  `templates/planning-index.md`'s "of the sandbox project" is brought to it.
- The claim is carried inline. The citation is provenance, not the delivery
  mechanism.

**2. Where behaviour depends on the cited text, cite a carrier that is
injected too.** `CLAUDE.md:71` becomes a pointer to the `design` skill's
Step 2, which carries the same decision tree, is present in every session,
and already defers to a project's own workflow document where one exists.

**3. D-9 in `tests/test_docs_integrity.bats` enforces decision 1.** Engine-free
and tagged `hostonly`, like the rest of that file. For every `*.md` under
`global-claude/` it reports:

- a repo-relative path (`docs/`, `tests/`, `base/`, `squid/`,
  `global-claude/`, `templates/`) that exists in this repository, unless
  allowlisted;
- an `ADR NNN` not followed by "of the claude-sandbox project".

The allowlist is data, in the style of `_NOT_SKILL_NAMES`, in two parts:
path prefixes that are target-relative by construction (`docs/planning/`,
and the bare directories `docs/adr/`, `docs/designs/`, `docs/plans/`), and
file-and-path pairs for conditional citations (`design` with the workflow
document; `swe-prior-art-research` with `tests/test_planning_artifacts.bats`,
whose sentence already states the condition). The failure message names this
ADR.

D-9 lands before the fixes and must be observed reporting the instances
above. Only then are they fixed.

**4. No repo-local `CLAUDE.md`.** The rule applies only when authoring under
`global-claude/`, which happens only here, and #104 proposed a repo-local
`CLAUDE.md` to carry it. D-9's failure message carries it instead, at the
moment it is broken.

## Consequences

A session in any project gets either a citation it can follow or a named
source it cannot mistake for one of its own files, and an ADR-number
collision stops being possible for a qualified citation. Recurrence becomes
observable: the next unqualified citation fails D-9 when it is written,
rather than being found in another project later.

Against that:

**ADR 003 cannot show its own qualification.** ADRs are never rewritten, and
D-3's Status vocabulary has no "qualified by". A reader of ADR 003 alone
still sees the unqualified rule; discovery depends on D-9's message pointing
here.

**The allowlist is judged by hand.** Direction cannot be inferred from a
path — the workflow document is right in `design` and wrong in
`CLAUDE.md:71` — so each exemption is a decision, visible in a diff, and a
surface to maintain.

**D-9 sees existing paths and ADR numbers, nothing else.** A citation by title
alone, or of a file not yet created, passes. Accepted: both are rarer than
the forms D-9 catches, and a check with false positives gets switched off.

**The canonical phrase ties every qualifier to the project's name.** A rename
is one grep and one allowlist edit. Provenance becomes a name to search for
rather than a path to open.

## Alternatives considered

**Chose:** name by document and project, with the claim inline.
**Rejected:** scope injected files to what the reader can see — cite only
injected files and target-relative paths, and drop provenance to this
repository's documents altogether.
**Why the rejected option is attractive:** it is the simplest rule, fully
mechanical, with no canonical phrase to maintain, and it is the shape the
AGENTS.md ecosystem uses; the Planning run's prior-art research flagged it as
a genuine alternative.
**What breaks if you try it anyway:** a maintainer can no longer trace why an
injected rule exists, and ADR 003 decision 4's purpose — cite the carrier
instead of restating it — degrades into restating or silence.

**Chose:** point `CLAUDE.md:71` at the `design` skill's Step 2.
**Rejected:** inline the Case-selection tree into `CLAUDE.md`.
**Why the rejected option is attractive:** the criteria then sit next to the
commit rules they gate, always loaded, and ten lines fit well under D-6's
ceiling.
**What breaks if you try it anyway:** a third copy of a tree that already
exists twice, in the workflow document's §4 and in `design` Step 2, whose
wordings already differ — the restatement defect ADR 003 decision 4 exists to
prevent, in the file it most wants to protect.

**Chose:** fix citations at the source.
**Rejected:** resolve them at injection — have the entrypoint copy the cited
documents into `~/.claude`, so the paths resolve literally.
**Why the rejected option is attractive:** no citation needs rewriting, and
the reader gets the full source.
**What breaks if you try it anyway:** it changes the entrypoint, a Case E
file; it ships this repository's design history into every project's
context; and unqualified ADR numbers still collide with the project's own.

**Chose:** D-9 in `tests/test_docs_integrity.bats`.
**Rejected:** G-11 in `tests/test_global_layer.bats`, as #104 proposed.
**Why the rejected option is attractive:** that file owns the global layer,
and G-10 already asserts what arrives in `~/.claude`.
**What breaks if you try it anyway:** its `setup()` requires a container
engine and a built image for every test, so a static text scan would inherit
that dependency and drop out of the engine-free CI run.

**Chose:** no repo-local `CLAUDE.md`.
**Rejected:** a repo-local `CLAUDE.md` carrying the authoring rule, as #104
proposed.
**Why the rejected option is attractive:** the author sees the rule before
breaking it, and it costs nothing in other projects, because it loads only
here.
**What breaks if you try it anyway:** its one rule is already enforced by a
check whose failure message states it, and the file becomes a second
instruction surface with no admission test — ADR 003's ladder governs the
injected layer, not a repo-local file — so it grows unchecked.

## References

- [ADR 003](003-where-a-behavioural-rule-goes.md) — decision 4, qualified here
- Issue #104 — the instances and the proposed rule
- [`docs/planning/charter.md`](../planning/charter.md) — the Go this
  implements; §Open questions on the repo-local `CLAUDE.md`
- [`docs/planning/prior-art.md`](../planning/prior-art.md) §Findings — the
  scoping alternative
- `global-claude/templates/planning-index.md` — the one file already following
  the rule
