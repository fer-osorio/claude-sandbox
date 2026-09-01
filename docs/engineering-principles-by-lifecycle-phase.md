# Engineering Principles by Lifecycle Phase

Extracted from three audits of a family of related production pipelines
(`architecture-comparison.md`, `guiding-rules-and-enforcement.md`,
`library-extraction-roadmap.md` — sibling-project documents, not present in
this repository) and restated so they apply anywhere. The evidence is specific because that is what makes a
principle memorable; the principle is general because that is what makes it
portable.

Where a claim in the source documents was checkable against the actual code, it was
checked. Findings marked *verified* below were confirmed directly.

---

## The habit underneath all of it

One question generated most of what follows:

> **Is this thing load-bearing, or merely present?**

A rule nothing enforces. A test that cannot fail. A feature nothing reads. A green
CI check on a machine missing the dependency it exists to test. All four look like
engineering. None of them are. Most of this document is that single question asked
at a different point in the lifecycle.

## How to read this

Each principle carries four things:

- **Trigger** — what you notice that means it applies
- **Action** — what to actually do
- **Prevents** — the failure it insures against
- **Cheap window** — the phase where doing it is nearly free

The **cheap window** is why this is organized by lifecycle instead of by topic.
Almost nothing here is technically hard. Most of it is only hard *late*. Dependency
caps take one line at project setup and a bisection through a major version bump
afterward. The reasoning behind a rejected design is free to write down the day you
reject it and unrecoverable six months later. Knowing which window you are in is
most of the skill.

---

## Part I — Four ideas that cut across every phase

### 1. The enforcement ladder

Every rule sits on a rung. Weakest to strongest:

1. Tribal knowledge — nothing written
2. Prose in a document (README, wiki, contributing guide)
3. A comment at the site it governs
4. Review convention — a human is supposed to catch it
5. An automated check that can fail the build
6. A design where violation is unrepresentable — types, API shape, no public setter

**The test:** *if I violate this rule at 2am on a Friday, what stops me?* Answer
honestly and you have your rung.

Two corollaries matter more than the ladder:

- **Emphasis does not change rungs.** "This is a hard invariant, not a default —
  re-verify explicitly if you touch this function" is rung 2 no matter how firmly
  it's phrased. Rung 2 is genuinely better than rung 1. Just know what you bought.
- **Most rules don't need rung 6.** Deciding a rule stays at rung 2 is a legitimate
  engineering decision. *Believing* a rung-2 rule is a rung-5 rule is what causes
  damage — you'll skip the review that was actually holding the line.

*Verified:* all three repos documented `ruff` and `mypy` as the expected local dev
loop. Zero CI jobs in the family ran either one.

### 2. The fresh-clone test

**Anything not committed to the repo does not exist for the next person.**

Three traps, all verified in the source family:

- A `commit-msg` hook that rejected a forbidden trailer — real, working, and
  installed by the *environment*, not the repo. Untracked, so it travels with
  nothing. It looks like enforcement until you run `git ls-files`.
- Governance that reached two of three repos only through a user-level global config
  file. A plain `git clone` in a different tool shows no such rule exists.
- A documented convention citing `docs/angular_commit_convention.md` — a file that
  was never written.

**Action:** periodically clone into a clean environment, or read `git ls-files`, and
ask what a newcomer actually sees. Every dangling reference is a rule that has
already quietly stopped working.

### 3. Load-bearing vs. vestigial

Presence is not function. The family shipped a Spanish email template *and* parsed a
`language` field into a dataclass — and nothing anywhere read that field to select
between templates. The capability was complete at every level except the one that
mattered.

**Action:** to test whether something is real, grep for **readers**, not
definitions. Better: delete it locally and see what fails. If nothing fails you have
found either dead weight or a missing test, and both are worth knowing.

Generalizes well past features: feature flags nothing branches on, config keys
nothing consumes, error types nothing raises, abstract methods with exactly one
implementation, metrics nothing alerts on.

### 4. Value is knowledge density, not line count

Thirteen lines of COM setup encoded four rejected alternatives and a library
compatibility patch — knowledge discovered by failure, invisible in a line count.
Meanwhile roughly 95% of a config module was domain field lists: many lines,
near-zero knowledge.

**Action:** when deciding what to centralize, protect, test hardest, or comment, ask
*what does this code know that isn't obvious from reading it?* Code that knows
things learned the hard way earns one home, real tests, and a note about the paths
that don't work. Bulk that is merely long earns none of that.

**Consequence:** lines-saved is a bad objective function for refactoring. It
systematically undervalues the dangerous code and overvalues boilerplate.

**The same test applies to prose, and is failed more often.** A commit message,
a PR description or a comment earns its length the same way code does — by
carrying something the reader cannot get from the diff. A rejected alternative
that looks better than the chosen one. A trap a future cleanup would walk into.
Everything else is restating what is already visible.

The failure mode is specific: **uniform verbosity destroys the signal that
verbosity carries.** If every message is long, length stops meaning "this one has
something in it", and the message that records a real trap gets skimmed with the
four before it that could have been subject lines. Padding does not merely waste
the reader's time; it spends the attention the important message needed. This is
the same shape as a gate that cannot fail, or a test that cannot catch a change —
a signal that is always on is not a signal.

**Action:** default to the shortest form that works — subject only, no comment,
no description. Spend length when the diff genuinely cannot carry the reason, and
spend it there only. And calibrate to the actual reader: an explanation written
for reviewers who lack context is worth little when the reviewer is the person
who asked for the work.

---

## Part II — By lifecycle phase

### Inception & setup

The cheapest phase in the lifecycle and the one most often skipped, because nothing
feels at risk yet. Everything here costs minutes now and days later.

**Cap your dependencies.** `pandas>=2.0.0` with no upper bound and no lockfile
resolved, in live virtual environments, to pandas 3.0.3 — a major version the code
was never written against (*verified*). Pin an upper bound or commit a lockfile on
day one. Retrofitting after a silent major bump means bisecting behavior changes
with no known-good baseline to bisect against.

**Declare one runtime version and make every surface agree.** In the family:
`requirements.txt` said "Tested on Python 3.9+", `pyproject.toml` said `>=3.11`, one
CI ran 3.12, another ran 3.11 (*verified*). Four sources, three answers.
Contradictory version claims are how "works on my machine" becomes structural rather
than anecdotal.

**Stand up CI before there is anything to run in it.** A repo that ships without CI
rarely gains it later — one of the three never did, and its absence became a
blocking prerequisite in a roadmap written a year on. Adding CI to a young repo is a
chore. Adding it to a mature one means confronting every accumulated failure at once,
which is why it doesn't happen.

**Put governance in the repo, not in your environment.** See the fresh-clone test.

**Keep machine-specific build artifacts out of shared trees.** A virtualenv,
`node_modules`, a compiled cache — each records absolute paths from the machine
that created it. Put one inside a directory that is bind-mounted, synced, or
network-shared between two machines and it can only ever be correct for one of
them.

The failure mode is what makes this worth a principle rather than a footnote.
Repairing the artifact on one machine rewrites those paths and breaks the other.
Each repair genuinely succeeds for whoever ran it, so nobody sees a contradiction
— it presents as *flakiness* ("the environment keeps breaking") rather than as
two consumers of one artifact that cannot serve both. Two people running the same
repair tool will alternate which side is broken, indefinitely, each convinced
they fixed it.

**Action:** before repairing anything that "keeps breaking", establish how the
directory is shared — `/proc/mounts`, or your sync tool's configuration. A bind
mount (one copy, two names) and a sync tool (two copies kept in step) look
identical from a single shell and need opposite remedies. Then give each machine
its own copy of the artifact by *masking the path per-machine* rather than
relocating it, so shared scripts and documentation keep working unchanged.

**Cheap window:** when you decide where the artifact lives. Afterwards it costs a
diagnosis session per affected machine, and the diagnosis is unusually hard
because every individual observation looks like success.

### Design

**Record rejections, not just decisions.** The most valuable ADR in the family
documents four *failed* approaches to injecting an email signature through COM. Its
worth isn't the decision it reached — it's the four paths a future engineer no
longer has to walk. A second repo recorded an idea as explicitly declined, so it
could not be re-litigated from scratch by the next person who found it obvious.

A format that works:

> **Chose:** … **Rejected:** … **Why the rejected option is attractive:** … **What
> breaks if you try it anyway:** …

That third line is the one people skip and the one that does the work. An option
recorded without its appeal will simply be reinvented.

*Cheap window: the moment of decision.* The reasoning evaporates in weeks. Nobody
successfully reconstructs "why didn't we just…" a year later.

**Name the anti-pattern, not only the rule.** "This function stays a display
formatter, never a rounding authority — anything needing other precision must arrive
already rounded," plus a pointer to the specific bug that prompted it, is durable in
a way "round consistently" is not. Rules written by someone who has been burned once
read differently, and they survive longer.

**Name your anti-goals.** The strongest roadmap in the family has an explicit
"Explicitly not a phase" section. Stating what you are deliberately *not* doing, and
why, controls scope better than silence — because silence reads as "not yet."

**Put a human in the loop on irreversible actions.** Every pipeline in the family
composes an email draft and calls `.Save()`. None call `.Send()`. The invariant
isn't "be careful" — it's that the irreversible call does not appear in the codebase
at all. Generalizes to deletes, migrations, payments, outbound notifications, and
anything that reaches a customer: make the destructive path require a separate,
deliberate act rather than a correct parameter.

**Prefer narrowing to accumulating.** Each generation of the family deliberately
*shed* generality it didn't need — dropped attachment support, collapsed its CLI to
two flags, removed an entire export module — while adding one narrow correctness
mechanism. Removal is a design outcome, not a failure to be sufficiently general.

### Implementation

**Validate at the boundary; fail loud and early.** Check every expected input field
up front and report the missing name, rather than dying with a `KeyError` deep in a
transform three hundred lines later. The error should name the thing and appear at
ingestion.

**Route bad data; don't drop it and don't crash on it.** All three repos send
unparseable rows to a dedicated error export. The run completes, the problem is
visible, nothing is silently lost. That is the difference between a system that
degrades and one that fails whole — and between a bug you find today and one you
find in a quarterly reconciliation.

**No string literals for external names in logic.** Every source column name is a
config field. When upstream renames a header you edit one line, not fifteen call
sites — and a typo is caught by the boundary validator instead of at runtime.

**Inject the clock.** Every date-dependent function takes `today: date | None =
None`. Ambient time is the most common untestable dependency in ordinary business
code and the fix costs one parameter. Same treatment for randomness, UUIDs,
filesystem roots, and network clients.

**Use presence-based checks, not truthiness, wherever absence and emptiness
differ.** `style["font"] if "font" in style else default` honors an explicit `""` as
"no font." `style.get("font") or default` silently overrides the user. Every config
layer, override mechanism, and merge function has this bug latent in it, and it
surfaces as "the system ignores my setting" — reported by users, never by tests.

**Get backward compatibility by construction where you can.** Adding new options as
keyword-only parameters, each defaulting to the exact literal that was previously
hardcoded, makes "existing callers get byte-identical output" a property you can
*see* in the signature rather than one you have to test for. Prefer designs where
the compatibility claim is structural.

### Verification

The phase where the source family was weakest, which makes these the sharpest
findings in the set.

**Test count is not test strength.** One repo carried 228 tests and asserted that a
generated chart was `bytes` beginning with the PNG magic number — a completely wrong
chart passes. Another asserted only that the substring `"Category"` appeared in the
rendered HTML. A refactor changing whitespace, tag order, attribute order, column
order, or row striping would have passed all three suites cleanly.

**Know your assertion ladder:**

| Rung | Assertion | Catches |
|---|---|---|
| 1 | It ran without raising | Crashes |
| 2 | A substring appears | Gross omission |
| 3 | A structural property holds | Shape errors |
| 4 | An exact fragment matches | Local regressions |
| 5 | The whole artifact matches a stored reference | Anything that changed |

Every rung is legitimate. The failure is believing you're higher than you are.
Write down, explicitly, what your suite would *not* catch.

**Characterization tests are a precondition for refactoring, not a nice-to-have.**
If you cannot detect the output changing, you cannot refactor the code that produces
it — you can only hope. Pin current output *before* touching anything, even when
the current output has known bugs: you are pinning behavior, not blessing it. Then
every intentional change shows up as a deliberate diff to a reference file, which is
exactly the review you want.

**Codify incidents into tests.** The family's one serious output-corruption incident
was diagnosed by manually diffing XML against real Excel, fixed, and written up as a
postmortem — and never turned into a test. The postmortem is good practice. Stopping
there means the same class of bug is still undetectable today.

> A postmortem without a regression test is a story, not a control.

**Verify that your gate can fail.** A CI job ran end-to-end Outlook tests on a
runner with no Outlook installed — the job's own inline comment admits it
(*verified*). It passed on every pull request, meaninglessly. Once, deliberately
break the thing a check protects and confirm the check goes red. **A gate never
observed failing is not known to be a gate.**

**Excluded-by-default suites need an owner and a trigger.** All three repos excluded
their COM/Office tests by default and documented "run manually before a release."
Nothing anywhere automates that (*verified*). That is an honor system, which is a
fine thing to choose deliberately and a dangerous thing to mistake for a gate.

### Release & deployment

**Smoke-test the launcher, not just the application.** A ~17-line flag that checks
only that the virtual environment resolves, exits 0 or 1, and is wired into CI. It
catches the "deployment is broken in a way no unit test can see" class of failure
for almost nothing.

**Count your deployment multiplicities before proposing shared code.** Three
independent checkouts, three virtual environments, editable installs by path: one
library change means three pulls and three reinstalls, and an editable path install
breaks silently if the directories aren't laid out as siblings. That recurring cost
is what any one-time savings has to beat.

**Server-side controls are part of the system and are invisible in the repo.** No
CODEOWNERS, no branch protection as code, no required status checks anywhere in the
family — so even where CI ran, nothing forced it to pass before a merge. Enforcement
that lives only in a web console is unreviewed, unversioned, and unrestorable. Check
it explicitly; prefer config-as-code wherever the platform allows it.

### Operations & maintenance

**Enumerate every side effect before claiming idempotency.** The family's outputs
were described as "naturally idempotent — dated, overwritable files." True of the
files, false of the system: each run also created a draft in a mail client over COM,
so a rerun produced a *second* duplicate draft. Overwriting a file protects the
file, not the mailbox.

> Idempotency is a per-effect property, not a per-run one — and the unprotected
> effect is usually the one that reaches a human.

List every externally visible effect of a run — files, emails, database rows,
webhooks, notifications, ticket comments — and check them one at a time.

**Give bypass flags an explicit contract.** One repo's `--force-compose`
deliberately bypasses two independent guards at once and says exactly that in its
help text. A bypass whose scope is documented is a tool; an undocumented one is a
trap that someone will spring during an incident.

**Derive dedup keys from content, and write them only after success.** A stable key
built from the fields that define "the same notification," checked against an
append-only log, appended *only after* the side effect actually succeeded. The
ordering is the whole design: log before success and a mid-run crash permanently
suppresses a real notification.

### Evolution — refactoring, extraction, reuse

The richest phase, and the one with the most counterintuitive findings.

**Measure before extracting; classify, don't eyeball.** Diff each candidate across
consumers and label it: byte-identical / cosmetic only / minor behavioral drift /
genuinely different. This takes an afternoon and routinely inverts your intuitions.

**Extract what has converged, not what looks similar.** The single most transferable
sentence in the source material. The function that looked most obviously shared — an
HTML table renderer present in all three repos — was the *worst* candidate. Each
consumer had grown a different **extension axis** over a ~12-line skeleton: one a
styling callback plus row truncation, one seven keyword-only style parameters plus a
column subset, one no extension point at all. Three incompatible extension models is
not shared code wearing three hats. It is three functions with a similar silhouette.

The diagnostic generalizes, and it's visible *before* you commit:

> The pieces that stayed extractable are the ones nobody needed to extend.
> Divergent extension points are the reliable signal that a shared abstraction will
> fail.

**Be honest about ROI, then relocate the argument.** Measured purely as
deduplication, the extraction saved ~3% net — not worth a new repository, a
distribution channel, and three-way version coordination. Publishing that number
didn't kill the project; it moved the justification to where it was actually strong:
change propagation (one home for hard-won platform knowledge) and time-to-build-the-
next-one. If your headline metric doesn't justify the work, say so out loud and find
the real reason — or stop.

**Separate "best implementation" from "safest to touch first."** The most
generalized version of every candidate lived in the newest repo, which was also the
least safe to migrate: no CI, no virtual environment, thinnest assertions, and a
live client pilot. Correct answer: seed the shared library *from* it, migrate it
*last*. These are different axes, and conflating them is how migrations end up
starting with the riskiest consumer.

**Sequence so early work isn't wasted if you abandon.** The roadmap's Phase 0 was
golden tests, CI, lint enforcement, and dependency caps — every item valuable
standalone. If the library is never built, none of it is wasted. Front-load work
whose value doesn't depend on the project completing.

**Build scaffolding last.** A project template generated before the API has survived
real migrations bakes in guesses. Templates encode assumptions permanently and
cheaply, which is precisely why they belong after the assumptions have been tested.

**Don't converge architectures as a prerequisite.** Reshaping working systems toward
a common shape spends the most refactoring risk of any available work while
producing nothing shippable — and erases divergences that were often deliberate and
documented. Convergence is a *side effect* of adoption where extraction forces it,
not a phase you schedule.

**Distinguish porting a capability from converging a design.** Moving a
self-contained, independently valuable feature into another codebase is cheap,
additive, and revertible. Reshaping a codebase to resemble its siblings is none of
those three. The two get confused constantly, and the confusion always runs in the
expensive direction.

---

## Part III — Patterns worth stealing verbatim

| Pattern | Shape | Pays off when |
|---|---|---|
| Layered config precedence | `defaults ← committed file ← local override ← CLI flags`, each layer partial | Environments differ but the schema doesn't |
| Boundary validation | One `validate_inputs()` mapping field → expected name, called before any transform | Inputs come from outside your control |
| Error-row routing | Bad records to a dedicated export; run completes | Partial success beats total failure |
| Injectable `today` | `def f(..., today: date \| None = None)` | Anything date-dependent, i.e. most business logic |
| Keyword-only additive params | New options keyword-only, defaulting to the old hardcoded literal | Extending a function with existing callers |
| Presence-based merge | `d["k"] if "k" in d else fallback` | Any override layer where empty ≠ absent |
| Append-only dedup log | Content-derived key, written after success | Any effect that can't be safely repeated |
| Launcher smoke test | Verify the entry point resolves; exit 0/1; run in CI | Deployment differs from development |
| ADR with rejections | Chose / rejected / why it's attractive / what breaks | Any non-obvious decision |
| Postmortem → regression test | Every incident writeup ends in a failing-then-passing test | Always |

---

## Part IV — Smell catalogue

| You observe | Suspect | Check it with |
|---|---|---|
| A doc cites another doc | The target doesn't exist | Open the path |
| A rule stated emphatically | Nothing enforces it | Grep CI config for the command |
| A green CI job | It passes trivially | Read the job's own comments; confirm its dependency is installed |
| A high test count | Weak assertions | Read the tests for the most complex output |
| A postmortem | No regression test exists | Search tests for the incident's keywords |
| A hook in `.git/hooks` | Untracked, or installed by tooling | `git ls-files`; read the header comment |
| Two files that look alike | Different extension axes | Diff them; list each one's parameters |
| A `>=` dependency with no cap | Already resolved past a major version | Compare declared vs. installed |
| A config key, flag, or template | Nothing reads it | Grep for readers, not definitions |
| "It's idempotent" | Only one of its side effects is | Enumerate every externally visible effect |
| A version claimed in several places | They disagree | Grep all of them at once |
| A manual pre-release step | Nothing triggers it | Search automation for the command |
| Every commit message is long | Length no longer marks the ones that matter | Check whether the last five bodies could have been subjects |
| A fix that has to be reapplied | Two consumers of one artifact, not a flaky fix | Establish how the directory is shared: `/proc/mounts`, sync-tool config |
| Two people report opposite results from one directory | It is one directory under two paths | Compare absolute paths; check for a bind mount |

---

## Part V — An audit protocol for an unfamiliar codebase

Ordered so that each step is cheap and the early ones inform the later ones.

1. `git ls-files` — establish what actually ships, before reading anything.
2. Read the CI configuration end to end and list every command it runs. List every
   command the docs say to run. **The difference is your enforcement gap.**
3. For each gate, ask what would make it fail. Any gate you can't answer for,
   treat as decorative until proven otherwise.
4. Read the most complex output-producing function, then read its tests. Write down
   what a refactor could change without failing anything.
5. Grep for dependency specs with no upper bound; compare declared against installed.
6. Grep every place a language or runtime version is claimed. They should agree.
7. Follow every documentation cross-reference and confirm the target exists.
8. Pick three config keys, flags, or templates and grep for **readers**.
9. Enumerate the side effects of one run; ask which are individually idempotent.
10. Read the ADRs and postmortems; for each, check whether a test encodes it.

Steps 2 and 3 are the highest yield in almost every codebase, and take under an hour.

---

## The one-sentence version

**Ask what's load-bearing, act inside the cheap window, and prefer mechanisms to
intentions.**

The source family's own trajectory is the cautionary tale the rest of this document
is built around: across three generations, documentation rigor rose steadily while
enforcement stayed flat at roughly zero. Each generation wrote its rules more
precisely than the last rather than building anything that made them stick. Writing
rules precisely is a real improvement and worth doing — and it is not a substitute
for making them mechanical. A rule a reader cannot misunderstand is still a rule a
reader can ignore.
