# Curated Auto-Memory Seeding — Step Zero

## Status

Draft — research pass completed 2026-08-31; round-trip pass completed
2026-09-03 (Q-8, Q-7, Q-3, Q-9 resolved, run in Environment 2 — see
"Environment caveat"). Q-10 also resolved 2026-09-03, confirmed directly
by the operator against a real `start.sh`-launched container — the
workspace-trust gate is live. All ten numbered questions from the research
pass are now closed except Q-5, Q-6 (resolved as a recommendation rather
than an empirical answer), and Q-11.
This document is the empirical groundwork for a future SDD, not the SDD
itself. Findings are marked **Confirmed**, **Reported**, or **Inferred**;
open questions carry their current state and what would resolve them.

Two grades of confirmation appear below and are not interchangeable:

- **Confirmed (observed)** — established by direct observation of a
  running container.
- **Confirmed (documented)** — established from Anthropic's primary
  documentation, read from outside the sandbox network boundary.

Neither is the round-trip test — seeding known content, running a session,
and confirming what actually loaded. Where a finding is load-bearing for
the design, that test is still owed. See "Remaining round-trip tests".

## Purpose

The proposal this supports (curated auto-memory seeding, "Option A" —
inject operator-authored memory content read-only at session start, no
write-back) depends on a file format that was, at first, only partially
documented from inside this project's own network boundary. The canonical
documentation is not reachable from a sandbox session, so the format was
initially assembled from a search-engine summary plus direct inspection of
a live container.

That is the wrong footing to design a validator on. This document
separates what has actually been established from what has been guessed,
and enumerates the questions whose answers would change the design rather
than merely confirm it. It exists so findings land next to the questions
that motivated them, instead of in conversation scrollback.

## Scope decision — 2026-09-03

Option A's seeded content is scoped to **advisory content only**: project
facts and operator preferences the model should be aware of. It is
explicitly **not** a vehicle for rule enforcement — guardrails and
behavioral constraints are handled by separate, more effective mechanisms
already established elsewhere (e.g. `permissions.deny` in `settings.json`,
`PreToolUse` hooks where needed), not by memory content the model reads
and reasons over.

This narrows what the no-write-back invariant needs to protect. The
concern it exists for — a session silently corrupting curated content and
then relying on the corrupted version for the rest of its own run, with no
way to detect the change after Q-7 killed the provenance-marker approach —
only matters for content meant to function as an enforced rule for the
session's duration. Advisory content has no such property: a session
drifting from a seeded project fact mid-run is a quality question, not a
Tampering one, and is no different in kind from ordinary in-context
reasoning drift that seeding didn't introduce.

**Consequence:** given this scope, Option A does not need a write-block
mechanism. The session can read and write its own memory freely for the
container's lifetime, exactly matching Auto Memory's existing default
behavior (F-1) — the only addition is the curated seed at session start.
See Q-8's revised consequence below. If a future use case wants to seed
policy-class content into memory, that content would need the write-block
(or, more likely, shouldn't live in mutable memory at all — CLAUDE.md and
`settings.json` already occupy that role and are already read-only-mounted
for exactly this reason).

## Classification

Case E, deferred. The eventual implementation touches `base/entrypoint.sh`
and introduces a user-scope `settings.json` write, so it carries a STRIDE
impact obligation per `docs-as-code-workflow.md` §3. **This document itself
changes no code and no container control** — it is research notes. The
STRIDE analysis belongs in the SDD that follows it.

The research below surfaced one item that belongs in that STRIDE analysis
regardless of whether seeding is ever implemented. See "Pre-existing
exposure surfaced by this research".

## Method

`check-auto-memory.sh` (repo root) is the diagnostic used for the
observational findings. Three subcommands: `version` (CLI version against
the feature gate), `config` (whether the CLI recognizes auto-memory
concepts), `behavior` (inspects a live container's memory directories and
dumps every `.md` found). It starts no sessions itself — `behavior`
requires a session the operator has already run, because auto-memory
content only exists after real work has happened.

Documentary findings were researched by the operator from the host, where
`code.claude.com` is reachable.

### Environment caveat — read before trusting any observational finding

Two distinct environments produced the observations here, and they are not
equivalent:

- **Environment 1** — a container the operator inspected with
  `check-auto-memory.sh behavior`.
- **Environment 2** — the container an authoring Claude Code session was
  itself running in. This one is *not* launched by `start.sh`: `/workspace`
  is a block device rather than a bind mount, and `~/.claude/settings.json`
  exists with TUI/theme/model preferences that `entrypoint.sh` does not
  write. It is a long-lived development container, not a canonical
  claude-sandbox session.

Findings from Environment 2 are reproducible and controlled, but transfer
to a real `start.sh` session by analogy, not by proof. Any finding the SDD
leans on should be re-confirmed in a `start.sh`-launched container before
it is treated as load-bearing.

An earlier reading of these observations concluded that memory content
persisted across container boundaries. That was wrong — the two
environments are independent, and the session transcript belonging to the
memory file seen in Environment 1 is absent from Environment 2's
`projects/` directory. **No evidence of cross-container memory persistence
has been found.** Recorded here because the error is an easy one to repeat.

## Confirmed findings — observed

### F-1 — Auto Memory is active by default in the current build
**Confirmed (observed).** `claude-base` ships Claude Code `2.1.227`. A real
session created `~/.claude/projects/-workspace/memory/` and wrote
`MEMORY.md` into it with no seeding, no override, and no prompting.

Does *not* establish that it will remain active: `base/Dockerfile` installs
`@anthropic-ai/claude-code` unpinned, so version and default behavior can
both change on any rebuild with no Dockerfile diff to signal it. See
"Standing risk".

### F-2 — The default memory path is derived from the workspace path
**Confirmed (observed).** Observed at `~/.claude/projects/-workspace/memory/`
— the mount target `/workspace` with separators replaced, not a random or
session-scoped identifier.

Does *not* establish the derivation rule in general (one sample, one path
shape). It does establish the path is stable and predictable enough that
the `autoMemoryDirectory` override is a convenience for determinism, not a
strict necessity.

### F-3 — Claude Code parses and rewrites topic-file frontmatter
**Confirmed (observed), by controlled test.** A memory file was authored
with the `Write` tool carrying exactly:

```yaml
name: no-claude-session-link-in-pr
description: Omit the claude.ai/code session URL from GitHub PR bodies by default
metadata:
  type: feedback
```

The file subsequently on disk read:

```yaml
name: no-claude-session-link-in-pr
description: Omit the claude.ai/code session URL from GitHub PR bodies by default
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d455b2a6-c51c-4b08-b76a-166761328a4f
  modified: 2026-08-26T20:08:58.830Z
```

Three fields were added that the author never wrote. A second file authored
the same way received the same treatment, and additionally had its
`description` re-emitted in double quotes because the value contained a
comma — the mark of a YAML parse-and-reserialize cycle, not a textual
append.

This establishes that:

- `metadata.node_type`, `metadata.originSessionId`, and `metadata.modified`
  are **writer-stamped, not author-required**. A hand-authored seed may
  omit all three.
- Frontmatter is genuinely parsed, so it must at minimum be **valid YAML**.
  Validity is a real constraint, not a style preference.
- Content placed in the memory directory by other means is adopted and
  normalized rather than ignored.

Scope limit, identified during the documentary pass: this test observed
only the **first-ever** write to a file. It did not test what happens when
Claude touches a file that already carries author-supplied frontmatter but
deliberately lacks `originSessionId` — which is precisely the seed-file
case. See Q-7.

### F-4 — Index format, as observed
**Confirmed (observed).** `MEMORY.md` is a flat list of one-line entries:

```markdown
- [No Claude session link in PRs](feedback_no_claude_session_link_in_pr.md) — omit claude.ai/code session URL from PR bodies by default
```

Title, relative link to a topic file in the same directory, em-dash, hook.
Q-1 has since established that this structure is **not machine-parsed** —
it is a convention the model reads, not a contract the harness enforces.

### F-5 — Topic-file naming, as observed
**Inferred, n=2.** Filenames are snake_case
(`feedback_no_claude_session_link_in_pr.md`) while the `name:` field is
kebab-case. R-2's confirmation of the four `type` values gives the
type-prefix pattern stronger circumstantial support, but no documentation
states a filename convention. **Remains Inferred; still not suitable to
assert in a validator.**

### F-6 — The documentation is unreachable from a sandbox session
**Confirmed (observed).** `WebFetch` against `code.claude.com` fails with
"Socket is closed" — the domain is absent from `squid/squid.conf`'s
default-deny allowlist. `WebSearch` still works, being mediated
server-side rather than issued from the container's network stack. Tracked
as issue #32.

This is why the questions below were addressed to the operator, who reads
them from the host, rather than resolved in-session.

## Previously reported — now confirmed

All five items previously carried as second-hand are now **Confirmed
(documented)** against `code.claude.com/docs/en/memory`:

- **R-1.** `MEMORY.md`'s first 200 lines *or* first 25KB, whichever comes
  first, load at session start; content past that threshold does not. The
  two ceilings are evaluated together, not sequentially. See Q-4 for the
  read/write asymmetry.
- **R-2.** `metadata.type` takes exactly one of `user`, `feedback`,
  `project`, `reference`.
- **R-3.** `modified` is written whenever Claude writes a memory file
  beginning with YAML frontmatter — **including backfill**: any
  frontmatter-bearing file gets the field the next time Claude writes it,
  whether or not it had one before. Requires v2.1.214+.
- **R-4.** The index/topic-file split exists to keep `MEMORY.md` concise
  and avoid truncation. Confirmed in as many words.
- **R-5.** Auto Memory shipped in v2.1.59. Corroborated by three
  independent secondary sources; the live docs page does not version-tag
  the feature's introduction, only later refinements.

## Resolved questions

### Q-1 — Is `MEMORY.md` parsed, or loaded as text? — **Answered**

**Loaded as text.** The harness loads the raw file into context the way it
loads a CLAUDE.md; the model itself follows the markdown links via ordinary
file reads. No mechanism parses the index's link structure. The only real
parsing is topic-file *frontmatter*, a separate mechanism.

**Consequence:** index-link resolution is a **usefulness** property, not a
**validity** one. A validator need not assert the
`- [Title](file.md) — hook` grammar as a hard contract, because nothing
downstream enforces it as one. Malformed index markdown would presumably
degrade the model's ability to find topic files rather than raise an error
— though that specific degradation is inference, tied to Q-3.

*Source: `code.claude.com/docs/en/memory`, "How it works".*

### Q-2 — How are topic files loaded? — **Answered**

**On-demand ordinary file reads**, documented explicitly: topic files are
not loaded at startup; Claude reads them with its standard file tools when
it needs them. No frontmatter-parsing retrieval or `description`/`type`
matching at the harness level.

**Consequence:** `description` is not *programmatically* load-bearing, but
it is the text the model reads off the index line when deciding whether to
open a file. It matters for **recall quality**, not validity — degrading
through model judgment the way a vague CLAUDE.md instruction does, not
through a broken lookup.

**Adjacent risk surfaced during research:** an open upstream issue (#46050)
reports Claude often does not proactively read topic files even when
clearly relevant and correctly indexed. This is a second failure mode a
validator cannot catch — a correctly formatted, correctly loaded seed can
still go unread. Worth naming in the SDD's consequences section, because it
bounds how much seeding can be expected to achieve.

*Source: `code.claude.com/docs/en/memory`, "How it works"; upstream issue
#46050 (community-reported, unresolved).*

### Q-4 — Is the cap truncation or refusal? — **Answered**

**Silent truncation on read.** Content past 200 lines / 25KB is simply not
loaded. On the write side there is a distinct, softer behavior: after
Claude writes `MEMORY.md`, Claude Code checks both limits — near a limit it
nudges Claude to shorten; over a limit the write still lands on disk but an
error tells Claude to rewrite the index. **Hard refusal happens nowhere.**

**Consequence:** the worry this question was written to test is the actual
behavior. An oversized seeded `MEMORY.md` silently loses its tail entries
at session start, undetectably from inside the session. **A host-side size
assertion is warranted and mandatory, not advisory** — this is the single
firmest validator requirement established so far.

*Source: `code.claude.com/docs/en/memory`, "How it works".*

### Q-10 — Settings-scope enforcement — **Answered; overturns the premise**

The question assumed `autoMemoryDirectory` was settable only from user or
policy scope, and asked whether that was genuinely enforced. **That premise
is false.** The setting "is read from any settings scope: user, project,
local, policy, or `--settings`." When set from a project's
`.claude/settings.json` or `.claude/settings.local.json`, it is honored
**only after the workspace-trust dialog for that folder has been accepted**
— the same gate that governs project-defined hooks.

So the real boundary is **workspace trust, not settings scope**. An
untrusted clone *can* carry a project-scope `autoMemoryDirectory` entry; it
does not take effect until a human trusts that workspace.

**Discrepancy, named deliberately:** several secondary sources describe the
setting as user/policy-only "so a shared repo can't redirect your memory" —
exactly the premise this question was written under. Primary documentation,
fetched directly and corroborated by an independent crawl of the same
official domain, is unambiguous and internally consistent, so it is treated
as authoritative. The secondary claim reads as stale or simply wrong. Given
how central this is to the threat model, it is flagged for round-trip
re-confirmation rather than asserted outright.

*Source: `code.claude.com/docs/en/memory`, "Storage location" — fetched
directly and corroborated by an independent search-index crawl of the same
official domain. Contradicted by `dev.to/isray_notarray` and `codecook.dev`,
both secondary and both of unclear vintage relative to the docs page.*

### Q-9 — `autoMemoryDirectory`'s contract — **Answered except one part**

- **Spelling:** `autoMemoryDirectory`. Confirmed.
- **Value form:** must be an absolute path or start with `~/`. Documented
  as a hard requirement, not a convention. The failure mode for a malformed
  value was not found — same open shape as Q-3.
- **Scope:** any (see Q-10 — this turns out to be the same underlying fact
  the two questions approached separately).
- **Migrate / shadow / duplicate:** **Answered, round-trip confirmed
  2026-09-03 — shadow.** Method: a scratch project accumulated memory at
  its default path (canary A). A second `claude -p` turn, same project,
  same cwd, with `autoMemoryDirectory` pointed at a fresh absolute path via
  `--settings`, wrote a second canary (B). Verified directly on disk
  afterward: the default directory still contained only canary A (no
  deletion, no addition); the new directory contained only canary B
  (`grep` for each canary string against the other's directory tree came
  back empty in both directions). Old content is neither migrated nor
  duplicated — it is simply left in place and no longer consulted. This
  upgrades the prior inference from silence to a direct observation, one
  environment, not yet re-confirmed in a canonical `start.sh` session.

*Source: `code.claude.com/docs/en/memory`, "Storage location".*

## Still open

### Q-3 — What happens to malformed input? — **Answered, round-trip confirmed 2026-09-03**

**Silent tolerance at the file-I/O level; silent skip at the parse/stamp
level — never a hard error at either.** Method: a topic file was seeded
with an unterminated quoted string in `description:`, then touched via the
ordinary `Read`/`Edit` tools inside a `claude -p` turn (same mechanism as
Q-7's test, run against invalid instead of valid YAML).

- `Read` returned the raw text verbatim — no parser rejected it, the model
  just noted in its own prose that the content looked malformed.
- `Edit` appended a line and saved successfully, exit code 0, no warning
  anywhere in the harness output or session transcript.
- The frontmatter came back **byte-for-byte identical** to what was
  seeded — no reserialization, and critically, **no `node_type`,
  `originSessionId`, or `modified` stamping**, in direct contrast to Q-7's
  result on valid frontmatter touched the same way.

**Consequence:** the stamping mechanism (F-3, R-3) is a distinct code path
from ordinary file I/O, and it silently no-ops when the YAML fails to
parse rather than erroring or corrupting the file. This confirms the
sibling-subsystem pattern this question originally reasoned from (silent
skip / soft degradation, not hard error) — now **Confirmed (observed)**
for memory specifically, not just inferred by analogy. It also means
malformed frontmatter is not self-correcting: a bad seed stays bad
indefinitely unless something else flags it, which is the strongest
argument yet for the host-side YAML-validity check already marked
"Warranted" below.

Not exercised: what a *first-ever* write of malformed frontmatter does
(this test touched a pre-existing file). Low priority — the failure mode
observed is already the conservative one a validator should guard against.

### Q-5 — Frontmatter field contract — **Not addressed this pass**

Which of `name`, `description`, `metadata.type` are required versus
optional, and whether `name` must correspond to the filename. Would benefit
from a dedicated look at the skills-frontmatter reference, which describes
an analogous — not identical — contract that may not transfer.

### Q-6 — What is `metadata.node_type`? — **Open, with a negative data point**

The memory documentation describes `type` thoroughly (R-2) and does not
mention `node_type` anywhere. Given how detailed that page is about other
frontmatter fields and even the 200-line cap's internals, the omission is
notable: it suggests an internal or reserved field rather than a documented,
stable part of the schema.

**Consequence, and a reversal:** an earlier recommendation in discussion
was to author `node_type: memory` in seeds on the grounds that it was cheap
to match observed output. The research argues the opposite — public docs do
not omit stable schema fields by accident, F-3 shows it is stamped
automatically anyway, and authoring an undocumented internal field couples
seeds to an implementation detail for no gain. **Seeds should omit it.**

### Q-7 — Are `originSessionId` and `modified` tolerated when absent? — **Answered, round-trip confirmed 2026-09-03**

`modified`: **yes**, tolerated when absent, and backfilled the next time
Claude writes the file (R-3).

`originSessionId`: **also backfilled on first touch — the provenance
proposal does not hold.** Method: a topic file was seeded with valid
frontmatter (`name`, `description`, `metadata.type`) and deliberately no
`originSessionId`/`node_type`/`modified`. A `claude -p` turn opened the
file and appended one line to the body via the `Edit` tool. The file on
disk afterward (verified directly, not just via the session's self-report)
carried all three fields:

```yaml
metadata:
  node_type: memory
  type: reference
  originSessionId: 9832e6dc-040d-4448-a971-8708a245d916
  modified: 2026-09-03T03:51:33.432Z
```

**Consequence:** the provenance proposal — *absence of `originSessionId`
marks a file as operator-authored rather than session-derived* — is
**dead**. The marker is destroyed the instant Claude writes to the file at
all, identically to `modified`, not just on files Claude itself
originated. This matters beyond Option A: any future write-back or memory
promotion design needs a different provenance carrier entirely, since this
one does not survive first contact.

### Q-8 — Can writes be disabled while reads remain? — **Answered, round-trip confirmed 2026-09-03**

**No — symmetric disablement confirmed, community guide (signal 1) was
right.** Method: `MEMORY.md` was seeded in an isolated scratch project with
a distinctive canary line. A `claude -p` baseline turn confirmed the canary
loads into context with no tool calls (proving the seed mechanism itself
works). A second turn, identical seed, with `autoMemoryEnabled: false`
passed via `--settings` — the canary did **not** appear anywhere in
context. Repeated with `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` as the env-var
alternative lever — same result, canary absent.

**Consequence:** read-without-write is **not achievable by configuration**
— `autoMemoryEnabled` alone cannot give it. This was originally read as
meaning the SDD must add a `PreToolUse` hook to enforce no-write-back.
**Revised per the Scope decision above:** Option A's seeded content is
advisory-only, and advisory content doesn't need that enforcement — a
session overwriting or extending a project-fact seed mid-run is a quality
concern, not a security one. So this finding is no longer load-bearing for
the SDD as currently scoped. The `PreToolUse`/`permissions.deny` option
remains documented here as a mechanism this pass identified, available if
a future use case seeds policy-class content into memory instead.

Not exercised: whether upstream issue #63903's reported preamble-still-
loads bug is present in this build (v2.1.259, newer than the 2.1.227 both
issues were likely filed against). Moot for this design either way — the
question this pass needed answered (can config alone give read-without-
write) is settled in the negative regardless of that bug's current status.

### Q-11 — Format stability commitment — **Open**

No versioning or stability guarantee found. One concrete data point cuts
against stability: `modified` is itself version-gated at v2.1.214+, which
is evidence the format has changed at least once in a version-visible way.
No changelog category tracks memory-format changes the way, for instance,
hook matcher changes are tracked. Continues to argue for treating the
format as unstable-by-default and pinning the Claude Code version.

## Pre-existing exposure surfaced by this research

Q-10's finding has a consequence specific to this project that is worth
stating separately, because it exists **today, independent of whether
seeding is ever implemented.**

`autoMemoryDirectory` is honored from project scope after workspace trust
is granted. In claude-sandbox, `/workspace` is an arbitrary bind-mounted
project directory — potentially an untrusted clone, which is the threat
model the sandbox exists to contain. If a session inside a container trusts
its workspace non-interactively (plausible: the container launches straight
into `claude`, and there is no operator at a trust dialog), then a
`.claude/settings.json` inside a mounted repo could redirect memory writes
to any absolute path the container process can reach.

The blast radius is bounded by the container — no host path is writable
beyond the bind mounts — so this is not an escape. But it is a Tampering
surface that belongs in the STRIDE analysis, and it is **not introduced by
seeding**; seeding merely makes it relevant enough to notice.

**Verified 2026-09-03 — the gate is live.** Confirmed directly by the
operator against a real `start.sh`-launched container (this could not be
produced from Environment 2, where the rest of this pass's tests ran — see
"Environment caveat"). The workspace-trust dialog presents and requires a
human decision; it is not auto-accepted. The existing mechanism already
closes this exposure: an untrusted clone's project-scope
`autoMemoryDirectory` entry does not take effect without that human
accepting the trust prompt. No additional control is needed for this
specific surface, though it remains worth naming in the SDD's STRIDE
section as a control that already exists and that seeding must not
bypass.

## Standing risk — validating against a moving target

`base/Dockerfile` installs Claude Code unpinned. The memory format is free
to change on any rebuild with no diff in this repository to signal it, and
Q-11 confirms the format has already changed once in a version-visible way.
A structural validator built on the findings above would then assert
confidently against a stale specification — **worse than no validator**,
because it converts drift into false confidence.

Consequences for the design, recorded so they are not rediscovered:

1. Assert only what is **Confirmed**, never what is **Inferred**. F-5
   (filename convention) is the concrete example: plausible, unverified,
   not worth encoding. Q-6 (`node_type`) is the second: do not author it.
2. The authoritative check is a **round-trip observation**, because it
   tests the implementation rather than notes about it. Host-side
   structural checks are a fast pre-filter, not the gate.
3. Documentation describes *current* behavior, not the behavior of whatever
   version a given container is running. The version check in
   `check-auto-memory.sh` is what ties a documentation snapshot to a
   running container; nothing in this document substitutes for it.

This remains the strongest available argument for pinning the Claude Code
version in `base/Dockerfile` — a pre-existing, separately-tracked concern
this feature makes newly relevant rather than one it introduces.

## What the validator design now looks like

Q-3, Q-7, Q-8, Q-9, and Q-10 are all now resolved by round-trip test, so
this table is no longer provisional on any of them.

| Check | Status | Basis |
|---|---|---|
| `MEMORY.md` ≤ 200 lines **and** ≤ 25KB | **Mandatory** | Q-4 — silent truncation on read |
| Topic-file frontmatter is valid YAML | **Mandatory** | F-3 + Q-3 — parsed/stamped when valid, silently un-stamped (not corrected) when not; malformed seeds do not self-heal |
| `metadata.type` ∈ four known values | **Warranted** | R-2 |
| Index links resolve to existing files | **Advisory only** | Q-1 — usefulness, not validity |
| Index line grammar | **Do not assert** | Q-1 — not a contract |
| Filename convention | **Do not assert** | F-5 — Inferred, n=2 |
| Seeds omit `node_type` | **Warranted** | Q-6 — undocumented internal |
| Seeds omit `originSessionId` | **Warranted** (not merely blocked) | Q-7 — confirmed backfilled on first touch regardless; authoring it is pointless, not just unproven |
| No-write-back enforcement | **Not required for this scope** | Scope decision — advisory content only; Q-8 confirms it isn't achievable via `autoMemoryEnabled` alone, but the Scope decision means nothing needs to enforce it |

Whether this belongs in bats, the entrypoint, or a standalone script is no
longer blocked on an open question — it can be decided in the SDD.

## Remaining round-trip tests, in priority order

Q-8, Q-7, Q-3, and Q-9 were run 2026-09-03 against Claude Code v2.1.259 in
Environment 2 (see "Environment caveat") using isolated scratch projects
under a sandbox's scratchpad directory, driven by nested non-interactive
`claude -p` subprocesses — never against this project's own memory or
settings. Results are folded into each question's section above.

1. ~~**Q-8**~~ — **Done.** Symmetric disablement confirmed; read-without-
   write is not configurable.
2. ~~**Q-7**~~ — **Done.** `originSessionId` backfilled on first touch;
   provenance proposal is dead.
3. ~~**Q-3**~~ — **Done.** Silent tolerance (file I/O) / silent skip
   (stamping), never a hard error.
4. ~~**Q-10 / trust posture**~~ — **Done, 2026-09-03.** Could not be
   produced from Environment 2, so verified separately by the operator
   against a real `start.sh`-launched container. Gate is live, not
   auto-accepted. See "Pre-existing exposure."
5. ~~**Q-9 remainder**~~ — **Done.** Confirmed shadow: old content
   untouched but no longer consulted; new writes do not duplicate back.

All five round-trip tests originally listed here are now resolved.

## What this document does not decide

- Whether to seed at all, and with what content.
- The validator's mechanism — deferred pending Q-3.
- Anything about write-back or memory promotion ("Option B"), which remains
  out of scope and retains the objection recorded in
  `global-layer-injection.md` §9.
- The STRIDE impact of the entrypoint and `settings.json` changes, which
  belongs in the SDD — including the pre-existing exposure noted above.

## References

- `injecting_memories_into_containers.md` (repo root, gitignored) — the
  informal proposal this supports, exported from an earlier session.
- `docs/designs/global-layer-injection.md` §9 — the standing decision
  against write-back persistence.
- `docs/designs/docs-as-code-workflow.md` §3 — Case E obligations.
- `check-auto-memory.sh` (repo root) — the diagnostic used here.
- `code.claude.com/docs/en/memory` and `.../settings-reference` — primary
  documentation, read 2026-08-31.
- Upstream issues #46050 (topic files not read proactively), #63903 and
  #44829 (memory preamble loads when disabled), #13905 and #17204
  (adjacent frontmatter failure modes).
- Issue #32 — Squid allowlist gap making the documentation unreachable
  from a session.
- Round-trip test pass, 2026-09-03 — Q-8, Q-7, Q-3, Q-9, run against
  Claude Code v2.1.259 in Environment 2 via nested `claude -p`
  subprocesses in isolated scratch projects. Not preserved as durable
  artifacts; results are recorded inline above.
- Q-10 trust-gate verification, 2026-09-03 — operator confirmation against
  a real `start.sh`-launched container, outside this session's own testing.
