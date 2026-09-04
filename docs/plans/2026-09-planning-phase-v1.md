# Planning Phase — State and Open Decisions

> **Document type:** Implementation plan / session handoff
> **Companion documents:** `docs/adr/001-agentic-sdlc-scope.md`,
> `docs/adr/002-planning-artifact-contract.md`,
> `docs/designs/planning-skill-output-routing.md`,
> `docs/designs/project-feasibility-skill.md`
> **Tracking:** #69 (phases), #70 (handoff decision), #71 (injection coverage)
> **Audience:** Whoever picks up Phase 4. Written 2026-09-04, at the point
> where Phases 1–3 are done and Phase 4 is blocked on decisions rather than
> on work.

---

## 1. What this feature is

An agentic Planning phase: a set of skills that take a project idea and
produce the four artifacts a human needs to decide go or no-go, under a
contract strict enough that the handoff survives having no conversation to
rely on.

ADR 001 bounds the ambition. Levels 0 and 1 are committed — L0 is a manual
session, L1 is the same control flow fired by an event rather than by a
person typing. L2 (orchestrator delegating to context-isolated subagents)
is explicitly *not* committed and has a written trigger; L3 is out of
scope. Both committed levels are workflows rather than agents: the control
flow belongs to us, and the model fills in steps.

ADR 002 defines how steps hand off — file-based, one owner per path,
because under `claude -p` there is no conversation for a later step to
read.

## 2. Document map

Read in this order if you are cold:

| Document | Settles |
|---|---|
| [ADR 001](../adr/001-agentic-sdlc-scope.md) | Scope: L0/L1 only, the L2 trigger, phase mapping for one operator, anti-goals |
| [ADR 002](../adr/002-planning-artifact-contract.md) | The artifact contract: paths, owners, frontmatter, ceilings, enforcement |
| [ADR 003](../adr/003-where-a-behavioural-rule-goes.md) | Where a rule lives: template / skill / `CLAUDE.md`, ranked by precision |
| [planning-skill-output-routing.md](../designs/planning-skill-output-routing.md) | Templates global, artifacts per-project, routing gated on `docs/planning/` |
| [project-feasibility-skill.md](../designs/project-feasibility-skill.md) | How the feasibility owner behaves, and the trigger collision |
| [docs/planning/README.md](../planning/README.md) | The artifact index and the choices ADR 002 left open |

## 3. What is built

**Phase 1 — contract infrastructure.** Merged. Four templates, the index,
and `tests/test_planning_artifacts.bats`.

**Phase 2 — routing the first writer.** Merged as PR #72. Templates moved
from `docs/planning/templates/` to `global-claude/templates/planning/`;
`swe-prior-art-research` writes `docs/planning/prior-art.md` and updates
its own index row, gated on `docs/planning/` existing.

Reclassified Case A → Case C during design. The original scoping missed
that the skill is injected into every project while the templates were
repository-local, so the skill would have cited a path that resolves only
here — and outside this repository it would not have failed, it would have
invented a format.

**Phase 3 — the feasibility owner.** PR #73, open, CI green.
`global-claude/skills/project-feasibility/SKILL.md`. Declines without
`docs/planning/scope.md`; tolerates a missing `prior-art.md` and names the
absence in Confidence by dimension; Financial bounded to effort and
opportunity cost with no currency; runs no research pass of its own.

**Phase 4 — the orchestrator.** Not started. Blocked on §5.

`industry-research-analyst` is deliberately unrouted. ADR 002 decision 2
gives `prior-art.md` a single owner, and routing both skills there would
break the rule P-5 protects.

## 4. Enforcement as it stands

`tests/test_planning_artifacts.bats` carries P-0 through P-7, all tagged
`hostonly` so CI runs them.

| Check | Asserts |
|---|---|
| P-0 | The template set is non-empty |
| P-1 | Every template declares `artifact`, `owner`, and ceilings |
| P-2 | Every artifact carries a valid `status` |
| P-3 | Every artifact path has a row in the index |
| P-4 | No artifact section exceeds its template's ceiling |
| P-5 | No artifact path is claimed by more than one template |
| P-6 | Every declared ceiling names a section that exists |
| P-7 | Every template `owner:` resolves to a committed skill, except `_UNBUILT_OWNERS` |

Three things worth knowing before trusting these:

**P-0 exists because the others degrade to silence.** Every check
iterates over a set, and an empty set is reported as a pass. Moving the
templates without moving `TEMPLATE_DIR` produced six passes over zero
templates — a fully broken contract reporting green. P-0 is the guard;
`.github/workflows/ci.yml:48-55` applies the same one to `--filter-tags`
selecting zero tests.

**All eight have been negative-controlled**, each observed reporting
against a deliberately broken fixture. P-2 and P-4 had never been seen to
fail before 2026-09-04. `_UNBUILT_OWNERS` was verified load-bearing:
emptying it reports exactly the two `project-planning` templates.

**P-2 and P-4 are still vacuous in practice.** No artifact exists yet, so
they iterate over nothing. They bind automatically the first time a skill
writes to `docs/planning/`.

**`bats` is not in the sandbox image** (`BUILDING.md:215`). From inside a
session, the helper functions can be extracted and called directly, which
exercises the awk/sed logic but not the bats wiring. Real verification is
either a host run or CI on a pushed branch.

## 5. Decisions required before Phase 4

In dependency order. The first is the only one that needs an ADR.

### 5.1 The Planning-to-Design handoff — blocking, Case D (#70)

Phase 0 of the original plan named two gating decisions. The first became
ADR 002. The second was never written down, and it gates Phase 4's exit.

Four sub-questions:

- Is `docs/planning/charter.md` an explicit input to the `design` skill,
  cited by path, or does the operator carry the outcome across manually?
- Does an approved charter constrain Case A–E classification, or does
  `design` classify independently as it does today?
  `global-claude/skills/design/SKILL.md` Steps 1–3 currently assume a
  human arrives with a change in mind; nothing tells it a charter exists.
- Where does the second approval gate sit relative to the boundary?
- What is the terminal state on a recorded no-go? ADR 002 calls a no-go
  with its reasoning the most reusable output the phase produces, so the
  handoff needs a defined failure path, not only a success path.

### 5.2 Does Phase 4 deliver L1, or only the orchestrator skill?

Not currently tracked anywhere, which is why it is easy to miss.

ADR 001 line 38 records L1 — `claude -p` fired by a client signal — as the
**committed target**. Nothing in the tree implements it: grepping for
`claude -p` outside the ADRs finds only the auto-memory research document,
and no issue covers it.

But a `SKILL.md` is invoked inside a session, which is L0. Phase 4 as
planned ships an orchestrator skill — better-organised L0, still L0. So
either Phase 4 is scoped to the skill and L1 stays unbuilt and untracked,
or Phase 4 also delivers the trigger. As things stand the project has
committed to something no work item covers.

### 5.3 Scope-intake is interactive; L1 is headless

The orchestrator's opening step is scope-intake, described in the original
plan as a short interactive clarification pass. Under `claude -p` there is
nobody to clarify with.

Resolutions available: two modes (interactive intake, or refuse headless
without a pre-written `scope.md`); or intake always requires a human and
an L1 run starts at prior-art with `scope.md` supplied as input. This
wants deciding rather than discovering during implementation.

### 5.4 Where the approval gate sits

ADR 001 flagged this against itself in its own Consequences:

> L1 means an agent begins work without a human present at the start, so
> the approval gate moves entirely to the end of a run — worth watching,
> because a gate at only one end catches less than a gate at both.

Phase 4 is where that becomes concrete. Does the orchestrator stop between
steps, or run all four and stop once at the charter?

§5.2, §5.3 and §5.4 are the same question seen from three sides. One ADR
can settle all three, and probably should.

### 5.5 Mechanics for the SDD to settle

Smaller, and answerable with a proposal rather than a decision from cold:

- **Does the orchestrator invoke `industry-research-analyst`?** The
  original plan said yes. Phase 2 decided it stays unrouted with findings
  folded in by the owning skill. Who invokes it, and who writes its output
  into `prior-art.md`, is unspecified — and only `swe-prior-art-research`
  may write that path.
- **Scaffolding `docs/planning/`.** Assigned to Phase 4 by
  `planning-skill-output-routing.md` §Decision 5. Silently, on
  confirmation, or refuse? Templates are global now, so scaffolding means
  the directory and the index, not copying templates.
- **Stop-early and resumability.** ADR 002 promises that a disqualifying
  prior-art finding stops the run with partial output still readable. What
  aborts a run, and does re-invoking resume from the index or restart?
- **Enforcement for the orchestrator.** `_UNBUILT_OWNERS` empties when
  Phase 4 lands, which widens P-7 to all four owners with no edit to the
  check. Nothing would assert the *sequence*. That is likely another
  rung-2 gap to record honestly rather than pretend away.

## 6. Settled — do not reopen

- Templates in the global layer, artifacts per-project, routing gated on
  `docs/planning/` existing — `planning-skill-output-routing.md`
  §Decision 1–2.
- `scope.md` and `charter.md` are both owned by `project-planning`, as its
  opening and closing steps — ADR 002 decision 2.
- The charter's Decision section is left blank by the skill and filled by
  a person — charter template, and ADR 001's autonomous go/no-go anti-goal.
- A no-go artifact stays in the tree with its `status` set — ADR 002
  Consequences.
- Scope-intake and charter generation live inside the orchestrator rather
  than as separate skills, until one earns its own file.
- `industry-research-analyst` stays unrouted.
- Skill trigger collisions are resolved by what the answer must conclude,
  never by keyword — `swe-prior-art-research` changelog 0.3 records the
  keyword form failing.

## 7. Known gaps carried forward

- **Nothing asserts the right skill fires.** P-7 resolves a path; whether
  a feasibility question routes to `project-feasibility` rather than
  `swe-prior-art-research` is prose in two always-loaded descriptions.
  Rung 2, silent failure, and this clause class has already failed once.
  No mechanism proposed. Tracked on #69.
- **Nothing asserts the injected layer arrives** beyond `CLAUDE.md`
  (#71). The whole Planning contract depends on
  `base/entrypoint.sh:26` copying templates into a session, and that is
  untested.
- **Four ADR 003 citations are permanently stale**, across lines 30
  (`docs/planning/templates/scope.md:36-40` and `templates/charter.md:20`),
  77 and 126. All point into `docs/planning/templates/`, which moved in
  Phase 2. ADRs are never rewritten, so they stay wrong. D-1 does not catch
  it — every one is a code span, not a link.

  Note: `planning-skill-output-routing.md` §Consequences records this as
  two citations on lines 30 and 77. That count was taken before line 126
  was found and is an undercount; the design document is a Draft SDD rather
  than an ADR, so it can be corrected.
- **The Financial ruling is local; the skill is global.** ADR 001 scopes
  budget exclusion to a single-operator project, but `project-feasibility`
  is injected everywhere. A project with a real spend line gets a document
  that refuses to cost it and will not say why.

## 8. Suggested next step

Write the §5.1 ADR, and let it settle §5.2–§5.4 at the same time. They are
one decision about where the human sits in an event-triggered run, and
splitting them produces three documents that have to agree.

Phase 4's SDD follows from that, then the orchestrator itself.
