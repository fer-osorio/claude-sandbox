# Planning Skill Output Routing

## Status

Draft

## Context

### What exists today

[ADR 002](../adr/002-planning-artifact-contract.md) defines a file-based
handoff for the Planning phase: one owner per path under `docs/planning/`,
frontmatter carrying `status`, ceilings declared in template files. Phase 1
of #69 built that contract — four templates in
`docs/planning/templates/`, the index at `docs/planning/README.md`, and
`tests/test_planning_artifacts.bats` to enforce it.

Nothing yet writes an artifact. `grep -rn "docs/planning" global-claude/`
returns nothing. The contract is enforced against templates only; P-2 and
P-4 iterate over an empty artifact set and pass trivially, which
`tests/test_planning_artifacts.bats:14-19` states plainly.

Phase 2 closes that gap by routing the first writer,
`swe-prior-art-research`, to `docs/planning/prior-art.md` — the path
ADR 002 decision 2 already assigns it, and which
`docs/planning/templates/prior-art.md:3` names in its `owner:` key.

### The problem the plan did not account for

The Phase 2 change was scoped as output routing: add an output section to a
SKILL.md, touch no reasoning logic. That describes the diff accurately and
the blast radius inaccurately.

`swe-prior-art-research` lives in `global-claude/skills/`. `start.sh:240-242`
mounts `global-claude/` readonly at `/run/claude-global` for every session,
and `base/entrypoint.sh:26` copies the whole tree into `~/.claude`. The
mount is not conditioned on the project. A rule written into that skill
therefore applies in every repository the sandbox is ever pointed at, not
only in this one.

`docs/planning/templates/` is a repository-local directory. A skill
instructed to follow a template at that path behaves correctly here and
incorrectly everywhere else, and the incorrect behaviour is the expensive
kind: no file is missing in a way that stops the run, so the skill invents a
format instead. The result is an artifact that does not satisfy the contract,
written into a repository that has no `test_planning_artifacts.bats` to
notice. That is `docs/engineering-principles-by-lifecycle-phase.md` §Part I.1
in its purest form — not a gate that never fires, but a contract with no
gate at all outside one repository.

### What ADR 002 left open

ADR 002 decision 5 requires templates to be files rather than advice inside
a SKILL.md. It does not say where those files live.
`docs/planning/README.md:33-37` answered that question — `templates/`,
alongside the artifacts — and is explicit that it is recording an
implementation choice ADR 002 left open, decided for this repository.

That choice was correct when the only reader was a human and the only
repository was this one. Phase 2 introduces a reader that is neither.

## Decision

### 1. Templates move to the global layer

`docs/planning/templates/` moves to `global-claude/templates/planning/`,
reaching a session at `~/.claude/templates/planning/<artifact>.md` by the
same entrypoint copy that delivers every other global file. This mirrors the
existing precedent: `global-claude/templates/docs-as-code-workflow-template.md`
is already consumed by the `design` skill from its runtime path.

The contract then travels with the capability. A skill that is present in
every session can cite a template that is present in every session, and the
citation resolves wherever the skill fires.

Artifacts do not move. `docs/planning/` keeps `README.md` and the four
artifact paths exactly as ADR 002 decision 2 specifies. Only the templates —
which are inputs to authorship, not artifacts — relocate.

Cost: 199 lines added to a global layer currently at 1820 of the 3000-line
ceiling asserted by `tests/test_docs_integrity.bats` D-7. No line is added
to `global-claude/CLAUDE.md`, so the always-on budget is unchanged; these are
rung-1 carriers in [ADR 003](../adr/003-where-a-behavioural-rule-goes.md)
decision 1 terms, loaded only when an artifact is authored.

### 2. Routing is conditioned on the project opting in

The skill writes to `docs/planning/prior-art.md` when `docs/planning/`
exists in the current project, and behaves exactly as it does today when it
does not. Presence of the directory is the opt-in signal.

This is deliberately self-detecting rather than configured. A flag in
`settings.json` or an environment variable would be a second thing to keep
in sync with the first, and a project that has the directory but not the
flag would fail in the silent-invention mode this design exists to remove.

### 3. The index row is the skill's own, and only its own

On writing its artifact the skill updates its row in
`docs/planning/README.md`: the status cell, and the artifact name from a
code span to a markdown link. `docs/planning/README.md:25-29` already
specifies this, including why the names start as code spans — D-1 in
`tests/test_docs_integrity.bats` fails on a link to a file that does not
exist yet.

### 4. The enforcement test follows the templates

`tests/test_planning_artifacts.bats:41` resolves `TEMPLATE_DIR` from
`PLANNING_DIR`. If the templates move and that line does not, `_templates()`
returns an empty set and P-1, P-3, P-5 and P-6 all pass over nothing — four
checks that carry real weight today silently becoming vacuous, in a commit
whose stated purpose is to make the contract more enforceable.

`TEMPLATE_DIR` is therefore repointed to
`${SANDBOX_DIR}/global-claude/templates/planning` in the same commit that
moves the files.

The verification cannot be "observe the tests fail first", because they do
not fail — that is the whole hazard. With `_templates()` empty, P-1, P-5 and
P-6 emit nothing and pass, and P-3 has no template-declared path left to
check. A broken pointer is indistinguishable from a clean run by exit status
alone. The observable that does discriminate is the size of the set: the
checks must see four templates after the move, as they do before it, and
that count is what gets asserted rather than inferred.

A negative control is run for all six checks separately, since P-2 and P-4
have never been observed failing and the other four are about to be moved
out from under their own pointer.

### 5. What Phases 3 and 4 inherit

`project-feasibility` and `project-planning` are also global skills writing
to per-project paths, so both face the identical boundary. This document
settles it once: templates global, artifacts per-project, routing
conditioned on `docs/planning/` existing. Those phases cite this section
rather than re-deriving it.

The orchestrator gains one responsibility this implies — scaffolding
`docs/planning/` in a project that does not have it, since under decision 2
a project with no directory is a project where the capability stays dormant.
That work belongs to Phase 4 and is out of scope here.

### Case classification (docs-as-code-workflow.md)

Case C. §4 question 1: the change crosses the boundary between the injected
global layer and per-project artifacts, and decision 5 constrains Phases 3
and 4. Not Case E — `global-claude/skills/` and `global-claude/templates/`
are not container security controls as §6 enumerates them, and nothing here
alters what a container process may do, read, or write.

Recorded against #69. No ADR: ADR 002 decision 5 delegated the location
question rather than deciding it, so answering it amends nothing. If a later
change moves artifacts as well as templates, that is an ADR.

## Consequences

The capability becomes portable. A skill injected into every project can now
follow the contract in any of them, which is the property Phase 2 was assumed
to have and did not.

The failure mode changes shape usefully. Under decision 2 a project without
`docs/planning/` gets today's behaviour rather than a malformed artifact —
the skill's output goes to the conversation, as it does now.

Enforcement coverage does not regress, because decision 4 moves the test
pointer with the files and asserts the template count rather than the exit
status.

Four citations in [ADR 003](../adr/003-where-a-behavioural-rule-goes.md) go
stale, across three lines: line 30 cites both
`docs/planning/templates/scope.md:36-40` and `templates/charter.md:20` as
existing carriers for "name anti-goals", line 77 cites `templates/scope.md`
again in the placement table, and line 126 cites it once more in the
alternatives. ADRs are never rewritten, so all four paths stay wrong
permanently. This is accepted rather than mitigated — ADR 003's decision, the
three-rung ladder, is untouched; only the evidence for one row moved, and the
alternative is either forking the rule into two locations or leaving the
templates where a global skill cannot reach them. Nothing catches this
automatically: D-1 resolves markdown links, and every one of the four is a
code span.

Against that: the templates now live further from the artifacts they govern.
A reader of `docs/planning/scope.md` who wants to know its ceilings must
follow a path out of `docs/` and into `global-claude/`, and nothing in the
artifact itself names the template it came from. The index is the mitigation,
and it is a weak one.

The global layer grows by 199 lines against a 3000-line ceiling that D-7
describes as a bound on unnoticed growth rather than a target. Phases 3 and 4
add no templates, so this is the whole cost of the Planning contract.

Decision 2 makes the capability invisible until a project opts in, and there
is currently no message telling an operator that `docs/planning/` is what
they are missing. Until Phase 4 scaffolds the directory, discovering the
capability requires reading this document or the skill.

This design assumes the entrypoint keeps copying the global tree wholesale
(`base/entrypoint.sh:26`). A future change that copies selectively — skills
but not templates, say — breaks decision 1 silently, in exactly the way
decision 1 exists to prevent. Nothing currently asserts that templates arrive
in a session — that gap predates this design, covers skills as well as
templates, and is tracked as #71.

## Alternatives considered

**Chose:** templates in the global layer, artifacts per-project.
**Rejected:** templates stay in `docs/planning/templates/`; the skill routes
only where that directory exists and reads the template from it.
**Why the rejected option is attractive:** it costs zero global-layer lines,
changes no file location, leaves `tests/test_planning_artifacts.bats:41`
untouched, and keeps each template next to the artifacts it governs — which
is genuinely the better arrangement for a human reader.
**What breaks if you try it anyway:** every project that wants the capability
must first copy four template files in, with no mechanism to tell it that or
to check the copies match. The contract is then defined by whatever version
of the templates a given repository happens to hold, which is the drift
problem ADR 002 decision 6 exists to prevent, distributed across repositories
instead of within one.

**Chose:** a single canonical copy in the global layer.
**Rejected:** canonical in the global layer, copied into each project on
first use.
**Why the rejected option is attractive:** every project gets a local,
diffable copy that its own test suite can check, which is the arrangement the
enforcement test already assumes and the one that keeps the templates beside
the artifacts.
**What breaks if you try it anyway:** two copies with no reconciliation is
drift with extra steps. Making it honest requires a check that the local copy
matches the canonical one, which is a new mechanism whose only purpose is to
undo the duplication it introduced.

**Chose:** condition routing on `docs/planning/` existing.
**Rejected:** route unconditionally — the skill always writes
`docs/planning/prior-art.md`.
**Why the rejected option is attractive:** it is one fewer branch in the
skill, needs no opt-in concept, and makes the capability available everywhere
with no setup.
**What breaks if you try it anyway:** the skill creates a `docs/planning/`
tree in every repository it is invoked in, including ones with an unrelated
directory layout, and a general-purpose research skill silently acquires a
side effect on the working tree. The opt-in costs one existence check.

## Implementation plan

1. Negative-control all six checks against the current layout, before
   anything moves: a template with `owner:` removed (P-1), an artifact with
   an invalid `status` (P-2), an artifact absent from the index (P-3), a
   section over its ceiling (P-4), two templates claiming one path (P-5), a
   `ceiling-` key naming no section (P-6). Each must be seen reporting.
   Discard the fixtures; the point is the observation, not a committed test.
2. Move `docs/planning/templates/` to `global-claude/templates/planning/`
   and repoint `TEMPLATE_DIR` in `tests/test_planning_artifacts.bats` in the
   same commit. Confirm the checks still see four templates afterwards — an
   empty set passes silently, so the count is the assertion, not the exit
   status.
3. Update `docs/planning/README.md:33-37` — the recorded location choice
   changes, and the paragraph should cite this document rather than restate
   it.
4. Add the output-routing section to
   `global-claude/skills/swe-prior-art-research/SKILL.md`: the opt-in
   condition, the template path, the artifact path, the index-row update.
   No change to the skill's reasoning steps.
5. Update the #69 checklist: Phase 2 done, owner-existence tightening still
   pending Phases 3 and 4.

Steps 1 and 4 require `bats` on the host — `BUILDING.md:215`. Neither can be
run from inside a sandbox session.
