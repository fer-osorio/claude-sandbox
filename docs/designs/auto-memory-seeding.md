# Curated Auto-Memory Seeding — Software Design Document

> **Document type:** Software Design Document (SDD)
> **Status:** Accepted — approved for implementation 2026-09-03
> **Classification:** Case E (container security control) + Case C (multi-component feature)
> **Relates to:** `auto-memory-seeding-step-zero.md` (evidence base),
> `global-layer-injection.md` (the mechanism this extends),
> `docs/claude_code_security_plan.md` (STRIDE coverage map)
> **Audience:** The engineer maintaining this sandbox — assumes the global
> layer's copy-on-start model and the existing STRIDE coverage map are known.

---

## 1. Purpose and Scope

### 1.1 What this designs

Seeding operator-authored Auto Memory content into every sandbox session:
curated, git-tracked, delivered read-only at session start, destroyed with the
container. This is "Option A" from `injecting_memories_into_containers.md` — the
one-way seed, not round-trip persistence.

The empirical groundwork is `auto-memory-seeding-step-zero.md`. Findings are
cited here by their identifiers (F-1, Q-4, R-2, …) and **not restated**; that
document is the record, this one is the decision.

### 1.2 Why the design changed from the informal proposal

The informal proposal predates the research pass and predates a close reading of
the entrypoint. Two of its components turn out to be unnecessary:

- It proposed a dedicated `/run/claude-memory` readonly mount and a matching
  `cp` block. `entrypoint.sh:26` already copies `/run/claude-global/.` into
  `~/.claude/`, so a `global-claude/memory/` directory arrives at
  `~/.claude/memory/` with no new mount and no new copy code.
- It proposed entrypoint logic to *write* `~/.claude/settings.json`. A
  `global-claude/settings.json` file rides the same copy and needs no logic.

What the entrypoint does gain is the one thing static files cannot provide: a
check that the seed is loadable. Q-4 established that an oversized `MEMORY.md`
loses its tail silently, and Q-3 that malformed frontmatter is silently tolerated
and never self-corrects. Both failure modes are invisible from inside the
session, which is precisely the case for a startup check.

### 1.3 Non-goals

- **No write-back or memory promotion** (Option B). The standing decision in
  `global-layer-injection.md` §9 holds, for the reasons in §5.4.
- **No rule enforcement.** Per step-zero's Scope decision, seeded content is
  advisory. Guardrails remain `permissions.deny`, Squid, and the container
  posture. Nothing in this design makes memory a control.
- **No claude.ai account or project memory ingestion.** No bridge exists in
  either direction; any such content arrives by the operator reading and
  transcribing it, as a content edit.
- **No consolidation step** ("Auto Dream" and equivalents).
- **No per-image memory overlay.** Deferred — see §9.
- **No Claude Code version pin.** A stated precondition (§6.3), not scope; it is
  a dependency-management decision meriting its own ADR.

---

## 2. Current Structure

```
host                          container (ephemeral)
────                          ─────────────────────
global-claude/  ──readonly──► /run/claude-global
  CLAUDE.md                        │  cp -r  (entrypoint.sh:26)
  skills/                          ▼
  hooks/                      ~/.claude/
  templates/                    CLAUDE.md, skills/, hooks/, templates/

                              ~/.claude/projects/-workspace/memory/
                                MEMORY.md          ← written by Claude
                                <topic>.md            during the session,
                                                      destroyed on --rm
                              ~/.claude/settings.json   ← does not exist
```

Auto Memory is active by default (F-1) and writes to a path derived from the
workspace mount (F-2). Nothing seeds it: every session begins with no memory and
accumulates from zero for the container's lifetime. `~/.claude/settings.json` is
absent in a `start.sh` container, and nothing in this repository writes it.

This is not a defect. It is the ephemerality guarantee working as designed — it
is simply also the reason a session cannot start from operator-curated context
the way it does for `CLAUDE.md`.

**Why not just put the content in `CLAUDE.md`.** `CLAUDE.md` is loaded eagerly
and in full, every session. Memory topic files are read on demand (Q-2), so a
corpus that grows past what is worth spending context on every turn belongs in
memory rather than in `CLAUDE.md`. That difference is the entire reason this
feature exists; if the seed stays small enough to live in `CLAUDE.md`, it should.

---

## 3. Target Structure

```
host                          container (ephemeral)
────                          ─────────────────────
global-claude/  ──readonly──► /run/claude-global
  CLAUDE.md                        │  cp -r  (UNCHANGED)
  skills/                          ▼
  hooks/                      ~/.claude/
  templates/                    CLAUDE.md, skills/, hooks/, templates/
  settings.json   ← NEW         settings.json   {"autoMemoryDirectory":
  memory/         ← NEW                            "~/.claude/memory"}
    MEMORY.md                   memory/
    <type>_<topic>.md             MEMORY.md      ← seed, then writable
                                  <type>_<topic>.md

                              ~/.claude/projects/-workspace/memory/
                                (shadowed — left in place, not consulted; Q-9)

entrypoint.sh  + inspect-and-warn block (§4.3)
start.sh       UNCHANGED
base/Dockerfile UNCHANGED
```

Three changes, in descending order of significance:

1. **`global-claude/memory/`** — the curated seed corpus. Authored and reviewed
   exactly like `global-claude/CLAUDE.md`; no Claude-authored content ever enters
   the host source.
2. **`global-claude/settings.json`** — a user-scope settings file whose only key
   is `autoMemoryDirectory`, pointing at `~/.claude/memory`.
3. **`base/entrypoint.sh`** — a validation block that reports, and never blocks.

---

## 4. Component Design

### 4.1 The seed corpus — authoring contract

`global-claude/memory/` holds a `MEMORY.md` index and topic files, following the
format established in F-3, F-4 and R-2. What the corpus must and must not assert
is settled by step-zero's validator table; the operator-facing rules are:

| Rule | Source |
|---|---|
| `MEMORY.md` ≤ 200 lines **and** ≤ 25KB | Q-4 — silent truncation on read |
| Topic frontmatter must parse as YAML | F-3, Q-3 — never self-corrects |
| `metadata.type` ∈ `user`/`feedback`/`project`/`reference` | R-2 |
| Do **not** author `metadata.node_type` | Q-6 — undocumented internal |
| Do **not** author `metadata.originSessionId` | Q-7 — backfilled regardless |
| Do **not** rely on the index-line grammar as a contract | Q-1 — not parsed |
| Do **not** encode a filename convention | F-5 — Inferred, n=2 |

Two content rules are this document's own, not inherited:

- **No secrets, credentials, or host paths outside `/workspace`.** Seed content
  is loaded into the model's context on every session and is therefore subject to
  the same discipline as `CLAUDE.md` (§5.3).
- **Advisory phrasing only.** Content that reads as an enforced rule invites
  exactly the misplaced reliance the Scope decision rules out. Constraints belong
  in `settings.json`'s `permissions` block or in Squid.

### 4.2 `global-claude/settings.json`

```json
{
  "autoMemoryDirectory": "~/.claude/memory"
}
```

**Why override rather than seed the default path.** The default is derived from
the workspace mount, and `/workspace` is fixed in this project — so seeding
`global-claude/projects/-workspace/memory/` would work today. It is nonetheless
the wrong choice: F-2 is an `n=1` observation of an undocumented derivation rule,
and step-zero's Standing Risk consequence #1 is to assert only what is Confirmed.
`autoMemoryDirectory` is a documented contract with a confirmed value form
(Q-9), so the design depends on the documented mechanism rather than on an
inferred internal convention. Q-9 also confirmed the shadow semantics: the
default directory is left in place and simply not consulted, so no stale content
competes with the seed.

**Ownership.** The entrypoint does not merge this file; the copy overwrites
whatever is at the destination, which in a `start.sh` container is nothing. This
is adequate *only* while `autoMemoryDirectory` is the sole user-scope key. The
moment a second consumer wants one, this becomes a real merge and needs JSON
handling — flagged here so it is a known limit rather than a discovered one.

**Name collision, stated to prevent confusion.** The repository root already
contains a `settings.json`. That is the *project-scope* permissions file for
this repo, is not mounted into any container, and is untouched by this design.
The new file is a distinct, user-scope file inside `global-claude/`.

**Interaction verified — gate cleared 2026-09-03.** Introducing a user-scope
`settings.json` does not disturb project-scope `permissions.deny`. Confirmed by
round-trip test, recorded as Q-12 in step-zero: with the deny rule at
`.claude/settings.json`, the rule fired identically with and without a
user-scope file carrying only `autoMemoryDirectory`, and a negative-control arm
established that the probe was capable of *not* denying — without which the two
matching results would have licensed the conclusion while testing nothing.
`check-auto-memory.sh deny-scope` is the instrument, and re-running it in a
`start.sh` container remains owed: the confirming run was Environment 2 and
non-interactive.

**Second interaction, deliberately not gated.** Claude Code may itself write
`~/.claude/settings.json` during a session (theme, model). Whether such a write
preserves `autoMemoryDirectory` or replaces the file wholesale is unknown, and
is **accepted as a documented risk rather than verified**, for three reasons:

- The blast radius is small and bounded. The seed has already loaded at session
  start — that value is banked. What a wholesale replace costs is where *later*
  writes land and whether the seeded corpus stays consulted: a quality
  degradation, ephemeral, contained by `--rm`.
- It is not cheaply testable. There is no `config` subcommand in the CLI
  (verified against v2.1.259), so a settings write cannot be forced from the
  command line; observing one needs an interactive TTY session and a manual
  `/config` change.
- The answer would not keep. This is an implementation detail of an unpinned
  binary (§6.3), so a confirmed result expires on the next rebuild with no diff
  to signal it, leaving a manual test to re-run indefinitely for a fact that
  decays.

**Detection instead of verification.** `check-memory-seed.sh diff` (§4.4) dumps
the seed beside its live state in a running container, so a reverted
`autoMemoryDirectory` shows up as the seeded corpus sitting unconsulted while
memory accumulates at the default path. That is a byproduct of a tool this design
already builds, it observes rather than remembers, and it stays true across
version drift. A confirmed instance gets recorded in step-zero and reopens this
decision; until then the risk is carried, not chased.

### 4.3 The entrypoint validation block

Placed after the existing copy blocks, before `exec "$@"`, following the shape of
the commit-msg drift check (`entrypoint.sh:110-170`):

```
[entrypoint] Checking seeded Auto Memory content
[entrypoint] OK: MEMORY.md is 41 lines, 2114 bytes (limits: 200 lines, 25600 bytes)
[entrypoint] OK: frontmatter delimiters present in 3 topic file(s)
[entrypoint] Seeded Auto Memory check complete
```

Checks performed:

1. **Size**, against both ceilings independently — `wc -l` and `wc -c` on
   `~/.claude/memory/MEMORY.md`. Exact, not approximate. This is the one
   step-zero marks Mandatory.
2. **Frontmatter structure** on each topic file — leading `---`, a closing `---`,
   and balanced quoting on `description`. This deliberately is *not* a YAML
   parse.
3. **Absent seed** — reports "no seeded memory content" and continues. Seeding is
   optional; a session without a seed is the current behavior and stays valid.

**Why not a real YAML parse.** Verified during design: neither the image nor the
host has a YAML parser (`python3 -c 'import yaml'` → `ModuleNotFoundError`; only
`python3` and `node` are present). Getting one means adding a package to
`base/Dockerfile` — widening the image and the Case E surface — to run a
pre-filter that step-zero already says is not the authoritative check. The
structural check catches the failure Q-3 actually exercised (an unterminated
quoted string) at zero dependency cost. Its limits are stated in the log and in
§6.2 rather than papered over; a structurally valid file that is invalid YAML
will pass this check and fail silently in the session.

**Why warn and never block.** Every existing entrypoint check warns. Fail-closed
is correct for Squid, which is a security control; a malformed advisory seed is a
quality defect, and aborting a session over it would be disproportionate and
would make a broken seed more damaging than no seed. The operator sees the
warning at the top of every session until it is fixed.

### 4.4 `check-memory-seed.sh` — host-side diagnostic

A repo-root script mirroring `check-auto-memory.sh`'s conventions (same
`config.sh` precedence, same subcommand shape, same "starts nothing it does not
have to" posture):

- `validate [dir]` — the full authoring contract from §4.1 against
  `global-claude/memory/`, including the checks the entrypoint cannot cheaply
  make (`metadata.type` membership, `node_type`/`originSessionId` absence, index
  links resolving). Runs on the host, before a session, with no container needed.
- `diff <container>` — dumps the seed as authored beside the same files as they
  stand in a live container, so in-session drift is observable. This is the
  operator-facing answer to informal-proposal step-zero item 4.

Splitting the thorough check onto the host and the cheap check into the
entrypoint is deliberate: the host check can be run and fixed before a session
exists, which is where a seeding mistake is cheapest to correct.

### 4.5 Test plan

New tests in `tests/test_global_layer.bats`, continuing the `G-` numbering. G-4
stays as it is — it asserts non-leakage of arbitrary writes and is not a seeding
test.

| Test | Asserts |
|---|---|
| G-10 | A seeded `global-claude/memory/` arrives at `~/.claude/memory/` in a session |
| G-11 | `~/.claude/settings.json` is present and declares `autoMemoryDirectory` |
| G-12 | The project-scope `permissions.deny` rules G-6 asserts are still declared with the user-scope file present |
| G-13 | An oversized `MEMORY.md` fixture is reported as a warning by the entrypoint |
| G-14 | A malformed-frontmatter fixture is reported as a warning by the entrypoint |
| G-15 | A container with no seed reports "no seeded memory content" and starts normally |

G-13/G-14/G-15 assert on entrypoint stdout, following G-7/G-8's precedent where
the log line *is* the control's observable output. Fixtures go under
`tests/fixtures/`, alongside `global-overlay-fixture`.

**What these tests cannot cover.** SDD §7.2 forbids `ANTHROPIC_API_KEY` in the
suite, so no bats test can drive a live turn. Everything here asserts delivery
and detection; that the model *loads* and *uses* the seed is confirmed by
round-trip observation (step-zero's method), recorded in the doc, not automated.
This is the same documented residual G-6 already carries, and is stated rather
than left implicit.

---

## 5. STRIDE Impact

Case E obligation. Delta against the coverage map in
`docs/claude_code_security_plan.md` §5.

### 5.1 Surfaces changed

| Surface | Change |
|---|---|
| `global-claude/` content | New content type (memory seed). Same trust model as `CLAUDE.md`: operator-authored, git-reviewed, readonly-mounted, non-root copy. |
| `~/.claude/settings.json` | **New.** First time anything in this repository writes a user-scope settings file. |
| Auto Memory write path | Redirected from `~/.claude/projects/-workspace/memory/` to `~/.claude/memory/`. Both are inside the ephemeral home the entrypoint already owns. |
| `base/entrypoint.sh` | One read-only inspection block. Reads two locations under `$HOME`; writes nothing; changes no control. |

No mount is added, no capability is granted, no network path changes, and
`start.sh`, `base/Dockerfile`, `squid/squid.conf` and the `permissions` block are
all untouched.

### 5.2 Controls added

| Threat | Control |
|---|---|
| **Denial of Service (D)** | The size check closes Q-4's silent-truncation path. Prior to it, an oversized index loses its tail with no signal anywhere; this is a availability-of-context defect, and the check is the only thing that surfaces it. |
| **Repudiation (R)** | The entrypoint logs what was seeded and whether it was loadable, so a session's starting memory state is recorded in container logs rather than inferred. `check-memory-seed.sh diff` extends this to in-session drift. |
| **Tampering (T)** | The seed source is readonly-mounted and git-tracked, so the corpus that reaches a session has a review trail — the same Repudiation/Tampering pairing the global layer already relies on. |

### 5.3 Risks accepted, with reasoning

**Tampering — the session may rewrite its own seed.** `~/.claude/memory/` is
writable, and Q-8 confirmed that read-without-write is not achievable by
configuration. A session can therefore overwrite seeded content mid-run. This is
accepted, not mitigated, per the Scope decision: for advisory content, divergence
between the seed and the file twenty minutes in is a quality question
indistinguishable in kind from ordinary reasoning drift. It is bounded by the
container — the host source is readonly and unreachable (G-3, G-4) — and dies
with `--rm`. Were policy-class content ever seeded, this would stop being
acceptable and would need `permissions.deny` on that path; that is why §1.3 rules
such content out rather than leaving it to judgment.

**Information disclosure — seed content is context, permanently.** Anything in
the corpus is in the model's context every session, and would appear in any
transcript or bug report. The §4.1 no-secrets rule is the control, and it is a
review-time human control, not an enforced one — the same standing as the
equivalent rule for `CLAUDE.md`.

**Tampering — `autoMemoryDirectory` is settable from project scope.** Q-10
overturned the informal proposal's premise here: the setting is honored from any
scope, so a mounted untrusted repository *can* carry one. This is **pre-existing
and not introduced by this design** — it is true today, with no seeding. The
control is workspace trust, verified live against a real `start.sh` container: an
untrusted clone's entry does not take effect until a human accepts the trust
prompt. Recorded here because this design is what makes the surface worth
naming, and because seeding must not be built in a way that bypasses that gate —
it does not, since it operates entirely in user scope.

**The trust gate is narrower than step-zero recorded it.** `claude --help`
states, for `-p`, that "the workspace trust dialog is skipped when Claude is run
in non-interactive mode (via `-p`, or when stdout is not a TTY, e.g. piped or
redirected output)", and that settings files failing validation are silently
ignored in that mode with no error shown. Step-zero's verification exercised the
interactive path, which is the path `start.sh` takes — it runs `-it`, so
production is correctly gated and that finding stands for production. It does
**not** generalise to every invocation inside the container: a `claude -p` run,
or any run whose stdout is piped or redirected, skips the dialog, and a mounted
repository's project-scope settings — `autoMemoryDirectory` among them — take
effect with no human in the loop.

Consequences, in order of importance:

- The exposure §5.3 describes as closed is closed *for the interactive session
  `start.sh` starts*, not for arbitrary in-container use. Anyone scripting
  `claude -p` against an untrusted mounted repository is outside the control.
- `check-auto-memory.sh deny-scope` drives non-interactive turns and therefore
  runs on the ungated path by construction. Its result transfers to a real
  session by analogy, not proof — the same standing as step-zero's Environment 2
  findings, and stated in the script itself.
- This qualification belongs in step-zero's "Pre-existing exposure" section as a
  correction, since that is where the original conclusion is recorded. §8 step 2
  carries it.

### 5.4 Why no write-back, restated as a control decision

Option B remains closed, and the reason is now citable rather than intuitive.
Memory poisoning is a named threat class (OWASP ASI06), and the published
attacks bear directly on this shape: MINJA reports high injection success through
ordinary interaction with no privileged access, and MemoryGraft — the closest to
this architecture — shows benign-looking ingested artifacts, of exactly the kind
a coding agent reads from `/workspace` as normal work, inducing durable
fabricated "experience" that resurfaces in later, unrelated tasks. A write-back
path would carry that across the container boundary the ephemerality guarantee
exists to hold. Independent defense work converges on separating untrusted
candidate memory from trusted memory behind mediated promotion, which is the
human review gate `global-layer-injection.md` §9 already prescribes.

No other STRIDE category is affected. Spoofing and Elevation of Privilege are
untouched: no identity, credential, capability, or privilege boundary changes.

### 5.5 Residual, not closed

- The structural frontmatter check is not a YAML parse (§4.3). A file that is
  structurally plausible but invalid YAML passes and then fails silently in the
  session.
- No test drives a live turn, so "the seed is delivered" is automated while "the
  seed is loaded and used" stays a manual round-trip observation (§4.5).
- Upstream issue #46050 — topic files are often not read proactively even when
  correctly indexed. A correct seed can still go unread. Nothing in this design
  can fix that; it bounds what seeding achieves (§6.1).
- The memory format is unversioned (Q-11) and Claude Code is unpinned (§6.3).
- Whether Claude Code preserves `autoMemoryDirectory` when it rewrites
  `~/.claude/settings.json` is unverified and deliberately so (§4.2). Detected
  by `check-memory-seed.sh diff`, not prevented.
- Workspace trust does not gate non-interactive invocations inside the container
  (§5.3). Not introduced here and not closed here; `start.sh`'s own path is
  interactive and unaffected.

---

## 6. Consequences

### 6.1 What this buys, honestly bounded

A session starts knowing what the operator curated, with the lazy-loading
property `CLAUDE.md` lacks. It does not guarantee the model reads any given topic
file (#46050), and it enforces nothing. The realistic claim is *fewer wasted
turns rediscovering established context*, not *the agent now behaves correctly*.

### 6.2 What gets harder

- A second reviewed corpus to keep current. Stale memory content is worse than
  none — it is confidently wrong context, and unlike `CLAUDE.md` it is read
  selectively, so staleness surfaces unpredictably.
- The 200-line/25KB budget is a hard ceiling shared by all seeded index content.
- `~/.claude/settings.json` now has an owner, and the next key added to it turns
  a file copy into a merge (§4.2).

### 6.3 Precondition, not scope

`base/Dockerfile:66` installs `@anthropic-ai/claude-code` unpinned. Q-11 confirms
the memory format has already changed once in a version-visible way, so the
authoring contract in §4.1 can drift with no diff in this repository to signal
it. This design mitigates rather than solves that: the entrypoint check asserts
only size and structure — the two properties least likely to move — and §4.1
asserts nothing marked Inferred. Pinning is the real answer and is deliberately
out of scope, as a dependency-management decision that constrains the project
beyond this feature and merits its own ADR.

---

## 7. Alternatives Considered

**Chose:** static seed files riding the existing copy, plus an entrypoint check.
**Rejected:** static files with no check at all.
*Why the rejected option is attractive:* it is a pure content change — no shell
code, no Case E code obligation, the smallest possible diff, and the existing
`cp -r` already does the work.
*What breaks if you try it anyway:* Q-4's truncation and Q-3's malformed
frontmatter are both silent and both invisible from inside the session. The
corpus would appear to work while its tail entries were never loaded. Step-zero
marks the size assertion Mandatory precisely because nothing else surfaces it.

**Chose:** files ride `/run/claude-global`.
**Rejected:** a dedicated `/run/claude-memory` mount with its own merge block
(the informal proposal).
*Why the rejected option is attractive:* explicit and symmetric with the overlay
mount; a reader sees memory injection called out by name in `start.sh`.
*What breaks if you try it anyway:* nothing breaks — it duplicates working
plumbing. It adds a mount, a `start.sh` conditional and a copy block that must
each be maintained and tested, to achieve what `entrypoint.sh:26` already does.

**Chose:** `autoMemoryDirectory` override.
**Rejected:** seeding the default derived path, `~/.claude/projects/-workspace/memory/`.
*Why the rejected option is attractive:* it removes the settings.json surface
entirely — the only genuinely new surface in this design — and the path is stable
in this project because `/workspace` is fixed.
*What breaks if you try it anyway:* it hardcodes an undocumented derivation rule
observed once (F-2), against step-zero's own rule to assert only what is
Confirmed. If the rule changes, the seed lands somewhere nothing reads, and the
entrypoint check would pass on a file the session never loads.

**Chose:** structural frontmatter check.
**Rejected:** adding a YAML parser to `base/Dockerfile` for a real parse.
*Why the rejected option is attractive:* a one-line apt addition buys a correct
check instead of an approximation, and closes §5.5's first residual.
*What breaks if you try it anyway:* it widens the image and the Case E surface to
strengthen a pre-filter that step-zero explicitly says is not the authoritative
gate — the round-trip observation is. The correctness gained is real but small;
the dependency is permanent.

**Chose:** memory seed.
**Rejected:** putting the content in `global-claude/CLAUDE.md`.
*Why the rejected option is attractive:* zero new mechanism, zero new surface,
one corpus instead of two, and it is the path `global-layer-injection.md` §9
already prescribes for insights worth keeping.
*What breaks if you try it anyway:* nothing, for a small corpus — and for a small
corpus it remains the right answer (§2). It stops scaling when the corpus exceeds
what is worth loading eagerly every turn, which is the condition this design
exists to serve.

---

## 8. Implementation Plan

One logical change per commit, on a branch, referencing the issue.

1. **`docs: design for curated auto-memory seeding (#65)`** — this document.
2. **Verification gate — cleared 2026-09-03, re-confirmation owed.** The
   settings-scope question passed in Environment 2 (step-zero Q-12), so the work
   below is unblocked. Re-run `./check-auto-memory.sh deny-scope` in a
   `start.sh` container before step 3 lands, since the confirming run was
   non-interactive and outside a canonical session. Two documentation commits
   fall out of this step and may land independently of the rest:
   `docs: record the settings-scope probe result` and
   `docs: narrow the trust-gate finding to interactive sessions` — both already
   written into step-zero, both true today and neither dependent on seeding
   shipping.

   **On a separate track:** the probe's arm D established that this repository's
   `permissions.deny` rules sit at a path Claude Code does not read (step-zero,
   "Project-scope settings at the wrong path"). That is a Case E defect in an
   existing control, not a seeding concern — tracked as issue #64. It does not
   block seeding, but it should not queue behind it either.
3. **`feat: seed curated auto-memory content into every session (#65)`** —
   `global-claude/settings.json` and `global-claude/memory/` with a minimal,
   genuinely useful seed. Small on purpose: the mechanism is what is under test.
4. **`feat: check seeded auto-memory content at session start (#65)`** — the
   entrypoint block (§4.3). Case E code change.
5. **`feat: add check-memory-seed.sh authoring validator (#65)`** — §4.4.
6. **`test: cover auto-memory seeding and its startup checks (#65)`** — G-10
   through G-15 plus fixtures.
7. **`docs: record auto-memory seeding as Change 22 (#65)`** — the §5 STRIDE delta
   into `docs/claude_code_security_plan.md`, in the established Change format.
8. **`docs: document memory seeding for operators (closes #65)`** — `user_guide.md`
   and `ARCHITECTURE.md`.

Steps 3–6 are each independently revertible. Step 2 gates all of them.

**Separately, not on this branch:** restore the "Identity and scope" section to
`global-claude/CLAUDE.md`, which the original global-layer plan drafted and the
shipped file lost. It is a plain content edit, Case A/B, and bundling it here
would inflate a trivial change with process it does not need.

---

## 9. Open Questions and Non-Decisions

**Q: Should per-image memory overlays exist (`global-crypto/memory/`, …)?**

Deferred, same posture as the per-image overlays themselves: empty until a real
need appears. Worth recording that the path is free — `entrypoint.sh:33` already
copies `/run/claude-overlay/.` into `~/.claude/`, so `global-<image>/memory/`
would be delivered today with no code change. Adopting it later is a content
decision plus a collision-semantics decision (does an overlay `MEMORY.md` replace
the base one, or are they merged), not a mechanism decision. The collision
question is real and is the reason not to do it speculatively.

**Q: Should the entrypoint block a session on an invalid seed?**

No, decided in §4.3. Recorded because the opposite instinct is reasonable and
will recur: every other fail-closed decision in this project (Squid) concerns a
security control, and this is not one.

**Q: What content should actually be seeded?**

Not decided here beyond the §4.1 rules. Step 3 ships a minimal seed to exercise
the mechanism; growing the corpus is ordinary reviewed content work.

**Q: Does seeding change how Option B should be designed?**

No. Step-zero's Q-7 already killed the `originSessionId` provenance marker, so a
future promotion design needs a different provenance carrier regardless. Nothing
in this design creates or forecloses one.

---

## Changelog

### Version 1.1 — 2026-09-03
Downgraded the `autoMemoryDirectory`-preservation question from a blocking gate
to a documented risk with a detector (§4.2), on the grounds that its blast radius
is a quality degradation, it is not cheaply testable (no `config` subcommand
exists in v2.1.259), and the answer decays with every unpinned rebuild. Added the
`deny-scope` probe to `check-auto-memory.sh` as the instrument for the one gate
that remains. Narrowed step-zero's trust-gate conclusion to interactive sessions
(§5.3): `-p`, and any run whose stdout is not a TTY, skips the workspace trust
dialog.

### Version 1.0 — 2026-09-03
Initial design document. Supersedes the informal proposal in
`injecting_memories_into_containers.md` on three points: no dedicated mount, no
entrypoint-written settings file, and `autoMemoryDirectory`'s scope enforcement
(Q-10 overturned the user/policy-only premise the proposal was written under).
