# Project Planning Skill

## Status

Draft

## Context

### What is missing

[ADR 002](../adr/002-planning-artifact-contract.md) decision 2 assigns two
paths to a skill called `project-planning` — `docs/planning/scope.md` as the
opening step and `docs/planning/charter.md` as the closing one. Both
templates name that owner in their frontmatter. The skill does not exist.

`tests/test_planning_artifacts.bats:186` carries
`_UNBUILT_OWNERS="project-planning"` for exactly this reason, and those two
template rows are the whole of what it exempts. Phase 4 retires the other
half of the exemption Phase 3 halved, and P-7 goes from covering two of four
template owners to four of four with no edit to the check.

This is the last unchecked box on #69. Everything else in the Planning set
is merged: the four templates, the index, the two sub-skills, and the
enforcement suite.

### The orchestrator owns two artifacts with opposite relationships to the human

`project-feasibility` owns one path and has one relationship to its reader:
it assembles evidence and stops short of the verdict. The orchestrator
brackets the run instead, and its two steps face opposite directions.

The opening step takes dictation. Everything in `scope.md` — the problem,
the constraints, the non-goals — originates with a person, and the skill's
job is to get it into the template's shape without adding to it.

The closing step reserves a section from itself. `charter.md` is written by
the skill except for `## Decision`, which
[ADR 001](../adr/001-agentic-sdlc-scope.md) decision 4 names as the anti-goal
the whole phase is built around.

A design that treats the orchestrator as "one more artifact-writing skill"
gets both ends wrong in the same way: by letting the model supply content
that is reserved to a person.

### What ADR 004 settles, and the three seams it leaves

[ADR 004](../adr/004-planning-to-design-handoff.md) closed #70 with eight
decisions, and this document reopens none of them. Gates at both ends,
human-only scope intake, straight-through execution with a conditional early
stop, the charter as an optional input to `design`, `status` as lifecycle
rather than outcome, and an orchestrator-only Phase 4 are all settled.

What it does not answer is how the orchestrator behaves at three seams,
because each is a question about the skill rather than about the interface:

1. Decision 2 says the orchestrator "refuses to run **headless** without
   `docs/planning/scope.md`." The word *headless* is load-bearing and
   undefined, and the rejected alternative next to it is *generated* intake,
   not *assisted* intake. Whether the skill ever writes the file it owns is
   left open.
2. Decision 3 gives the early-stop rule and not the criterion. Neither
   `swe-prior-art-research` nor `project-feasibility` emits anything an
   orchestrator could branch on — no exit status, no sentinel, and
   deliberately no outcome field, since decision 7 keeps outcome out of
   `status`.
3. [`planning-skill-output-routing.md`](planning-skill-output-routing.md)
   §Decision 5 assigns scaffolding `docs/planning/` to Phase 4, while
   §Decision 2 makes the presence of that directory the opt-in signal every
   Planning skill reads. A skill that creates the directory grants the opt-in
   to its two peers in that repository, silently.

Seams 1 and 3 change the shape of the skill. The rest change what it is
honest about.

## Decision

### 1. One skill, one file, inheriting the Phase 2 boundary

`global-claude/skills/project-planning/SKILL.md`. No `references/`
subdirectory: the orchestrator's body is control flow over two skills that
already carry their own reasoning, and there is no second loadable mode.

The global/per-project boundary is settled and not re-derived here —
templates in the global layer, artifacts per-project, routing gated on
`docs/planning/` existing. See
[`planning-skill-output-routing.md`](planning-skill-output-routing.md)
§Decision 1 and §Decision 2, and
[`project-feasibility-skill.md`](project-feasibility-skill.md) §Decision 1
for the precedent this follows.

The sequence is scope → prior-art → feasibility → charter, delegating the
middle two. It runs inside one context window. ADR 001 decision 2 gates L2
on two written triggers, neither of which has been observed, so "the
orchestrator should delegate to isolated subagents" is not available as a
design move here.

### 2. Intake: the skill transcribes, it does not derive

The skill writes `scope.md`, and that is what keeps the template's `owner:`
honest. The alternative leaves a template naming an owner that never writes
it, which P-7 would pass on happily — it resolves a path, not a behaviour.

Three branches, and the skill states all three:

- **`scope.md` exists and carries `status: Approved`** — read it, never
  rewrite it, proceed to prior-art.
- **`scope.md` is absent or still `Draft`, and a person is present** — the
  skill conducts intake, writes what that person supplies, and stops for
  approval. The run does not continue on a `Draft`.
- **`scope.md` is absent and nobody is present** — refuse and stop, naming
  the missing file. This is ADR 004 decision 2 unchanged.

The discriminator between transcription and derivation is one sentence, and
it belongs in the skill verbatim: **every substantive claim in `scope.md`
traces to something the operator said in this session; the skill may format,
it may not infer.** An unanswered field is written as an explicit gap, not
filled with a plausible guess. This does not reopen ADR 004's rejected
alternative 4, which rejected the *generated* path — transcription invents
nothing, and the failure that alternative describes is invention.

**The entry gate gets a machine-readable form: `status: Approved` on
`scope.md`.** ADR 004 decision 1 describes the gate as "an artifact that
must already exist", and decision 7 already reads `status` as document
lifecycle rather than decision outcome, so `Approved` here means intake is
finished and nothing else. This costs no new vocabulary, widens nothing P-2
checks, and gives #82's trigger a precondition it can test rather than
assume.

Enforcing the refusal in a headless run is not this skill's mechanism to
build. Issue #82 already assigns the precondition to the trigger — "The
trigger is responsible for establishing that precondition, not for working
around it" — and a prose rule inside the skill is what that trigger will be
written against.

### 3. Scaffolding is granted by a human and executed by the skill

The orchestrator creates `docs/planning/` **only on an explicit request to
begin planning for this project, and it says what that means** — that the
directory opts the whole repository into the Planning contract, for every
Planning skill in it, not just for this run. It never scaffolds as a side
effect of another task, and it never scaffolds headless.

The last clause falls out of decision 2 rather than needing its own rule: a
headless run requires `scope.md` to pre-exist, which requires the directory
to pre-exist. **Scaffolding and headless execution are mutually exclusive by
construction**, so the case where a switch gets flipped with nobody watching
does not arise.

This keeps the opt-in something the operator grants and the skill merely
executes. The peers' rule is unchanged and correct for them:
`project-feasibility` and `swe-prior-art-research` still must never create
the directory to satisfy their output sections.

Scaffolding produces two things, not one:

- `docs/planning/` itself.
- `docs/planning/README.md`, from a template. P-3 resolves an artifact by
  grepping the index for its basename, and the contract has every skill
  update "its own row" — with no index there are no rows to update, and the
  first skill to write would have to invent the file it is forbidden to own.

**The index is scaffolded with all four rows in their initial state.** This
is the one place the orchestrator legitimately writes rows it does not own,
and the distinction is creation versus update: it creates the table ADR 002
decision 2 specifies, then touches only its own two rows for the rest of the
run.

The template goes at **`global-claude/templates/planning-index.md`** — a
sibling of `templates/planning/`, deliberately not inside it.
`_templates` (`tests/test_planning_artifacts.bats:100`) globs `*.md` at
maxdepth 1 inside `TEMPLATE_DIR`, so a fifth file dropped in that directory
becomes a template as far as P-1 and P-6 are concerned, and would have to
declare `artifact:`, `owner:` and a `ceiling-*` key it has no business
carrying.

**The scaffolded index carries no relative links out of `docs/planning/`.**
This repository's own index links to `../adr/002-...` and to
`../designs/planning-skill-output-routing.md`; neither path exists in an
arbitrary project, and D-1 would not catch it, because D-1 walks
`git ls-files` in *this* repository only. The template names ADR 002 in
prose and links to nothing. This is the same global-layer / per-project
boundary error that reclassified Phase 2, in its third variant.

### 4. A disqualifying finding is one the artifact says out loud

The orchestrator judges, from the artifacts it can read. No structured
signal is added to the two sub-skills: that would edit two committed global
skills to serve a third, widening Phase 4 past ADR 004 decision 8, and the
signal would itself be prose that nothing checks.

The rule that keeps this away from ADR 001's autonomous go/no-go anti-goal
is a citation requirement rather than a judgment standard:

**A stop must quote the sentence, from the artifact the step just wrote,
that makes the next step pointless, and cite it as `path §Section`. If no
such sentence can be quoted, the run continues.**

This converts a judgment into a citation, which is the move ADR 002
decision 6 already makes everywhere else in the contract. It also bounds the
failure: the orchestrator cannot stop on an impression, and a reader can
check the stop by reading one quoted line.

**An early stop writes no charter.** It writes the artifact of the step that
stopped and updates that row — ADR 004 decision 3's resumability half — and
the `charter.md` row stays "not yet written". A stop is an incomplete run,
not a no-go. A no-go is a person filling in `## Decision` on a charter that
was written, which is why decision 7 can keep outcome out of `status` at
all.

### 5. The charter is written from disk, not from memory

ADR 002 decision 6 forbids re-derivation, and a single-context run is the
condition under which that rule is hardest to hold: all three preceding
artifacts are in the conversation, and restating what is already in view is
cheaper than citing it.

The skill therefore **re-reads each artifact from disk before writing the
charter**, and **every line under `## Evidence` carries a
`docs/planning/<file> §Section` citation**. The template already says the
charter aggregates and does not re-derive; this makes the instruction
operational rather than aspirational, and it is the same discipline
`project-feasibility` applies to its own two inputs.

### 6. The Decision section is a copy operation, not a judgment

Both existing Planning skills carry the instruction "Delete the template's
authoring comments from the output." Applied naively to `charter.md`, that
strips the comment at `charter.md:50-56` — the one that tells a person what
to write in the section reserved for them — and leaves a bare heading under
a document that has just made a recommendation.

So the skill carries an explicit exception: **for `## Decision`, emit the
heading and the template's authoring comment verbatim, and nothing else.**

The point is to replace a judgment the model must exercise ("leave it
blank") with a copy it can either perform or fail visibly. It does not make
the anti-goal enforceable — see Consequences — but it removes the reading
under which a helpful model fills the section in because the surrounding
instruction told it to delete the comment that said not to.

### 7. Sequence enforcement (#88): decided here, built there

#88 argues that sequencing is cheaper to design before the orchestrator
exists than to retrofit onto whatever it happens to do — the argument
ADR 002 made for defining the contract before the first skill. Phase 4
settles the mechanism and does not build it.

**The mechanism is a citation-coverage check on the charter's `## Evidence`
section**: assert that it cites `scope.md`, `prior-art.md` and
`feasibility.md`. It converts a property of a *run* into a property of a
*file*, which is #88's hard constraint — sequence is a runtime property and
CI has no Claude session. It needs no engine, fits the suite's existing awk
idiom, and lives on the one artifact Phase 4 owns, so it requires no edit to
either sub-skill.

**What it does not cover, stated plainly:** it proves the terminal step
consumed all three inputs. It does not prove prior-art ran before
feasibility. #88 stays open for that remainder rather than being closed on a
partial result.

It is not built in Phase 4 because it would be vacuous on the day it landed
— no artifact has ever been written, so it would iterate an empty set and
report a pass, which is the exact failure P-0 exists to catch and which this
suite has already paid for once.

### Case classification (docs-as-code-workflow.md)

Case C. §4 question 1: an orchestrator over two existing skills is a new
abstraction, it crosses the global-layer / per-project boundary in three
places (decision 2, decision 3, and the index template), and it constrains
#82, which will be written against the precondition decision 2 defines.

Not Case E — nothing here touches `base/Dockerfile`, `base/entrypoint.sh`,
`squid/squid.conf`, or the `permissions` block in `settings.json`.

Recorded against #69. No ADR: ADR 002 decided the paths and the owner,
ADR 004 decided the phase boundary and the gates; this document decides how
the owner behaves, which is design rather than architecture.

## Consequences

The Planning phase becomes complete as a sequence. All four artifact paths
have a committed owner, `_UNBUILT_OWNERS` empties, and P-7 covers every
template owner with no edit to the check — the property the exemption was
built as data rather than prose to get.

**Nothing enforces the blank Decision section, and nothing can, statically.**
This is ADR 001's strongest anti-goal carried entirely by prose in a
template and a skill. `ceiling-decision: 8` bounds the section's length, not
its authorship, and a model-authored decision inside eight lines passes
every check in the suite. No static check distinguishes "the skill left it
blank" from "a person filled it in", because the file looks the same either
way at the moment it is read. Decision 6 lowers the odds of an accident; it
does not create a gate. Rung 2, and the violation is least visible in
exactly the artifact where it matters most.

**The early-stop criterion is prose, and fails silently in both
directions.** A run that continues past a real blocker produces a charter
built on an artifact that said not to; a run that stops on a soft finding
produces a partial set that looks like a blocked project. The citation
requirement in decision 4 makes a wrong stop auditable after the fact — the
quoted sentence is either there or it is not — but nothing catches it at
write time.

**Phase 4 produces a charter that nothing reads.** #89 implements ADR 004
decisions 4–5 in the `design` skill, and until it lands the handoff has a
sender and no receiver. Anyone expecting an end-to-end Planning → Design
flow at the end of this phase will be disappointed, and the phase is still
worth landing first because the receiver needs something to receive.

**Nothing fires the orchestrator.** #82 is the L1 trigger, and a skill is
invoked inside a session, which is L0 — better-organised L0, still L0. The
`status: Approved` precondition in decision 2 is written for a trigger that
does not exist yet.

**The entry gate can block a well-intentioned operator.** Requiring
`status: Approved` on `scope.md` means a hand-written scope with
`status: Draft` stops the run over a frontmatter field the operator may not
know is load-bearing. The mitigation is that the refusal names the field and
the value it wants; the cost is real and is the price of a gate that a
machine can check.

**P-2 and P-4 stay vacuous.** Phase 4 builds the skill; it does not run it
in this repository. No artifact is written here, all four index rows stay
"not yet written", and the two checks that iterate artifacts continue to
pass over an empty set. Phase 4 does not de-vacuify them, and saying
otherwise would be the exact overstatement the suite's header was rewritten
to prevent.

**A fifth template contradicts a statement in a Draft design.**
`planning-skill-output-routing.md:190` records that "Phases 3 and 4 add no
templates, so this is the whole cost of the Planning contract." Decision 3
adds one. That document is Draft, not an ADR, so the statement is
changeable — but it is changed here explicitly rather than left to be
discovered by someone reconciling the two.

## Alternatives considered

**Chose:** the orchestrator writes `scope.md` by transcription.
**Rejected:** the orchestrator never writes `scope.md` and only requires it.
**Why the rejected option is attractive:** it is the strictest possible
reading of ADR 004 decision 2, it makes the L0 and L1 paths identical, and
it removes any possibility of the skill contributing content to the one
artifact every later step is measured against. One control flow is easier to
verify than two, in a mode that is verified least.
**What breaks if you try it anyway:** the `scope.md` template names an owner
that never writes it, and P-7 passes on that because it resolves a path
rather than a behaviour. The capability also becomes unreachable from a cold
start — a fresh project needs a scope artifact in the contract's exact
shape, and nothing in the tree would produce one, so the operator hand-writes
frontmatter and five headed sections from a template they have to go find.

**Chose:** the orchestrator judges disqualifying findings under a citation
requirement.
**Rejected:** each sub-skill emits a structured signal the orchestrator
branches on.
**Why the rejected option is attractive:** it puts the judgment where the
evidence is. `project-feasibility` knows whether its own verdict blocks
continuing far better than a caller re-reading its output does, and a
declared signal is checkable in a way a re-read is not.
**What breaks if you try it anyway:** it edits two committed global skills
to serve a third, which ADR 004 decision 8 scopes Phase 4 out of, and the
signal needs somewhere to live. `status` is closed to it by decision 7, so
it means a new frontmatter key across templates — widening the vocabulary
ADR 002 decision 3 fixed and the set P-2 checks, for a value that is still
model-authored prose that nothing verifies.

**Chose:** scaffold only on an explicit request, and announce what it grants.
**Rejected:** scaffold whenever the orchestrator runs in a project without
the directory.
**Why the rejected option is attractive:** it is the obvious reading of
routing §Decision 5, it makes the capability self-installing, and it fixes
the discoverability gap that document names — today, finding out that
`docs/planning/` is what you are missing requires reading the design.
**What breaks if you try it anyway:** the opt-in becomes something a skill
grants itself. Directory presence is how *both* peers decide whether to
write to disk, so one invocation of the orchestrator silently converts every
future prior-art question in that repository into a committed artifact. The
opt-in cost routing §Decision 2 priced at "one existence check" was priced
on the assumption that a person did the opting in.

**Chose:** the index template as a sibling at
`global-claude/templates/planning-index.md`.
**Rejected:** a fifth file inside `global-claude/templates/planning/`.
**Why the rejected option is attractive:** every other Planning template
lives there, the skill would resolve all its templates from one runtime
directory, and a sibling file is a special case a later reader has to
explain to themselves.
**What breaks if you try it anyway:** `_templates` globs that directory, so
the index becomes a template as far as the suite is concerned. P-1 demands
`artifact:`, `owner:` and at least one `ceiling-` key; P-6 demands every
ceiling name a real section. The index has no ceilings and, per ADR 002
decision 2, no single owner — its row rule is that every skill updates its
own. Satisfying P-1 would mean writing frontmatter that contradicts the ADR
to keep a test quiet.

**Chose:** citation coverage on the charter's Evidence section as #88's
mechanism.
**Rejected:** an `inputs:` frontmatter key on every artifact, listing what
that step read.
**Why the rejected option is attractive:** it covers the full sequence
rather than just the terminal step, and it reads like provenance metadata
that would be independently useful — a reader could see what each artifact
was built from without opening anything else.
**What breaks if you try it anyway:** it widens ADR 002 decision 3's
frontmatter vocabulary, requires editing both sub-skills to emit it, and
records a claim rather than a fact — a step can list an input it never
opened, and nothing distinguishes the two. It also spreads the sequence
across five files, which is the second-place-to-drift problem #88 names as a
constraint on any resolution.

## Implementation plan

1. Write `global-claude/skills/project-planning/SKILL.md`: description with
   the reciprocal tie-breaker against both sub-skills, the input contract
   and its three branches, the scaffolding rule and what it announces, the
   delegating workflow, the early-stop citation requirement, the charter
   output with the `## Decision` exception, and the two index rows it owns.
2. Write `global-claude/templates/planning-index.md`: the four-row table
   from ADR 002 decision 2, the two row-update rules, no relative links.
3. Empty the exemption in `tests/test_planning_artifacts.bats` — line 186
   becomes `_UNBUILT_OWNERS=""`, and the two comment blocks that name
   `project-planning` as a live exemption (lines 45-49 and 181-185) are
   rewritten to match. The space-padded match at line 194 handles an empty
   value, matching the `_NOT_SKILL_NAMES=""` idiom already in
   `tests/test_docs_integrity.bats:77`.
4. Verify: markdown links resolve (D-1), every backticked kebab-case token
   in the new global-layer files resolves to a committed skill (D-2), the
   new skill directory carries a `SKILL.md` (D-4), `global-claude/CLAUDE.md`
   unchanged (D-6), the global-layer line ceiling (D-7, currently 2207 of
   3000), the description parses (D-8), and P-0 through P-7 green.
5. Negative-control P-7 rather than trusting a green run: the discriminating
   observable is that it now resolves four owners rather than two, not its
   exit status, which was green before this change. With the new `SKILL.md`
   moved aside, P-7 must fail naming both `scope.md` and `charter.md`.
6. Update #69 — tick Phase 4 and the owner-existence follow-on. Record the
   decided mechanism and its stated gap on #88. Open the follow-on issue for
   the Evidence-citation check from decision 5.
7. Delete `docs/plans/2026-09-planning-phase-handoff.md`. It is untracked
   and self-declared disposable, and its durable content is now in ADR 004,
   this document, and the test header.

Steps 4 and 5 require `bats` on the host — `BUILDING.md:215`. Neither can be
run from inside a sandbox session, so the evidence for them comes from a
host run or from CI on the pushed branch.
