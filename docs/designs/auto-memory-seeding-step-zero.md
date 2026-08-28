# Curated Auto-Memory Seeding — Step Zero

## Status

Draft — research in progress. This document is the empirical groundwork
for a future SDD, not the SDD itself. Findings are marked **Confirmed**,
**Reported**, or **Inferred**; open questions carry an empty answer slot
to be filled in as they are resolved. Nothing here is settled until it is
marked Confirmed.

## Purpose

The proposal this supports (curated auto-memory seeding, "Option A" —
inject operator-authored memory content read-only at session start, no
write-back) depends on a file format that is only partially documented
from inside this project's own network boundary. The canonical
documentation is not reachable from a sandbox session, so the format was
initially assembled from a search-engine summary plus direct inspection of
a live container.

That is the wrong footing to design a validator on. This document
separates what has actually been established from what has been guessed,
and enumerates the specific questions whose answers would change the
design rather than merely confirm it. It exists so that findings land next
to the questions that motivated them, instead of in conversation
scrollback.

## Classification

Case E, deferred. The eventual implementation touches `base/entrypoint.sh`
and introduces a user-scope `settings.json` write, so it carries a STRIDE
impact obligation per `docs-as-code-workflow.md` §3. **This document itself
changes no code and no container control** — it is research notes. The
STRIDE analysis belongs in the SDD that follows it.

## Method

`check-auto-memory.sh` (repo root) is the diagnostic used throughout. Three
subcommands: `version` (CLI version against the feature gate), `config`
(whether the CLI recognizes auto-memory concepts), `behavior` (inspects a
live container's memory directories and dumps every `.md` found). It starts
no sessions itself — `behavior` requires a session the operator has already
run, because auto-memory content only exists after real work has happened.

### Environment caveat — read before trusting any finding below

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
to a real `start.sh` session by analogy, not by proof. Any finding that the
SDD leans on should be re-confirmed in a `start.sh`-launched container
before it is treated as load-bearing.

An earlier reading of these observations concluded that memory content
persisted across container boundaries. That was wrong — the two
environments are independent, and the session transcript belonging to the
memory file seen in Environment 1 is absent from Environment 2's
`projects/` directory. **No evidence of cross-container memory persistence
has been found.** Recorded here because the error is an easy one to repeat.

## Confirmed findings

### F-1 — Auto Memory is active by default in the current build
**Confirmed.** `claude-base` ships Claude Code `2.1.227`. A real session
created `~/.claude/projects/-workspace/memory/` and wrote `MEMORY.md` into
it with no seeding, no override, and no prompting to do so.

Does *not* establish that it will remain active: `base/Dockerfile` installs
`@anthropic-ai/claude-code` unpinned, so version and default behavior can
both change on any rebuild with no Dockerfile diff to signal it. See
"Standing risk" below.

### F-2 — The default memory path is derived from the workspace path
**Confirmed.** Observed at `~/.claude/projects/-workspace/memory/` — the
mount target `/workspace` with separators replaced, not a random or
session-scoped identifier.

Does *not* establish the derivation rule in general (one sample, one
path shape). It does establish that the path is stable and predictable
enough that the `autoMemoryDirectory` override is a convenience for
determinism, not a strict necessity.

### F-3 — Claude Code parses and rewrites topic-file frontmatter
**Confirmed by controlled observation.** A memory file was authored with
the `Write` tool carrying exactly:

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
in the same way received the same treatment, and additionally had its
`description` re-emitted in double quotes because the value contained a
comma — the mark of a YAML parse-and-reserialize cycle, not a textual
append.

This is the single most useful finding here. It establishes that:

- `metadata.node_type`, `metadata.originSessionId`, and `metadata.modified`
  are **writer-stamped, not author-required**. A hand-authored seed may
  omit all three.
- Frontmatter is genuinely parsed, so it must at minimum be *valid YAML*.
  Validity is a real constraint, not a style preference.
- Content placed in the memory directory by other means is adopted and
  normalized rather than ignored — relevant to how a seeded file will be
  treated.

Does *not* establish what happens when frontmatter is **invalid** — that is
Q-3, and it is the question that determines whether validation is
load-bearing.

### F-4 — Index format, as observed
**Confirmed (observed).** `MEMORY.md` is a flat list of one-line entries:

```markdown
- [No Claude session link in PRs](feedback_no_claude_session_link_in_pr.md) — omit claude.ai/code session URL from PR bodies by default
```

Title, relative link to a topic file in the same directory, em-dash, hook.
Does *not* establish that this structure is *parsed* — see Q-1.

### F-5 — Topic-file naming, as observed
**Inferred, n=2.** Filenames are snake_case (`feedback_no_claude_session_link_in_pr.md`)
while the `name:` field is kebab-case. Whether the two must correspond, and
whether the type prefix is required, is unestablished. **Not currently
suitable to assert in a validator.**

### F-6 — The documentation is unreachable from a sandbox session
**Confirmed.** `WebFetch` against `code.claude.com` fails with "Socket is
closed" — the domain is absent from `squid/squid.conf`'s default-deny
allowlist. `WebSearch` still works, being mediated server-side rather than
issued from the container's network stack. Tracked as issue #32.

This is why the questions below are addressed to the operator, who reads
them from the host, rather than resolved in-session.

## Reported but unverified

Sourced from a `WebSearch` summary of the official documentation page, not
from the page itself. Reliable enough to design around provisionally,
not reliable enough to encode in a test.

- **R-1.** `MEMORY.md`'s first 200 lines or first 25KB, whichever comes
  first, are loaded at session start; content past that threshold is not.
- **R-2.** `metadata.type` takes one of four values: `user`, `feedback`,
  `project`, `reference`.
- **R-3.** `modified` is recorded by Claude Code as an ISO 8601 timestamp
  when it writes a file beginning with YAML frontmatter. (Consistent with
  F-3.)
- **R-4.** Topic files exist so `MEMORY.md` stays concise and avoids
  truncation — i.e. the index/detail split is deliberate design, not
  incidental.
- **R-5.** Auto Memory shipped in Claude Code v2.1.59.

## Open questions

Ordered by how much the answer would change the design. Fill in **Answer**
and flip **Status** as each is resolved.

### Tier 1 — would restructure the design

---
**Q-1. Is `MEMORY.md` parsed, or loaded as text?**

Does anything consume the `- [Title](file.md) — hook` structure, or is the
file placed into context verbatim with Claude following links as ordinary
file reads?

*Unblocks:* whether index-link resolution is a **validity** property or
merely a **usefulness** one. If the file is just text, the validator
shrinks to the size cap alone and most of the proposed structural checking
is unjustified.

*Where:* `code.claude.com/docs/en/memory` (and its `.md` raw variant).

**Answer:** _(pending)_ · **Status:** Open

---
**Q-2. How are topic files loaded?**

On-demand ordinary file reads, or a retrieval mechanism that parses
frontmatter and selects by `description`/`type`?

*Unblocks:* whether `description` quality affects retrieval (making it
semantically load-bearing) or is documentation for humans. F-3 proves
frontmatter is parsed *on write*; this asks whether it is parsed *on read*.

*Where:* same page; also anything describing how memories are surfaced
into context.

**Answer:** _(pending)_ · **Status:** Open

---
**Q-3. What happens to malformed input?**

Silent skip, logged warning, hard error, or partial load — for (a) invalid
YAML frontmatter, (b) missing required fields, (c) an index entry linking
to a file that does not exist.

*Unblocks:* **whether validation is load-bearing at all.** Silent skip is
the case that justifies the entire exercise, because a seed that never
loads is indistinguishable from a seed that loaded and had no effect. A
hard error means Claude Code validates on our behalf and a host-side
validator is redundant.

*Where:* documentation, plus any diagnostic/verbose flag that reports what
was loaded.

**Answer:** _(pending)_ · **Status:** Open

---
**Q-4. Is the 200-line/25KB cap truncation or refusal?**

And is it evaluated lines-first or bytes-first?

*Unblocks:* whether an oversized index silently loses entries. Silent
truncation is the same detection problem as Q-3 and would make a hard size
assertion mandatory rather than advisory.

*Where:* documentation; confirm against R-1.

**Answer:** _(pending)_ · **Status:** Open

---

### Tier 2 — would settle open design decisions

---
**Q-5. The frontmatter field contract.**

Which of `name`, `description`, `metadata.type` are required versus
optional; whether `name` must correspond to the filename; whether the
kebab-case/snake_case split seen in F-5 is meaningful or incidental.

*Unblocks:* every assertion a structural validator would make, and whether
F-5 can be promoted from Inferred to enforceable.

**Answer:** _(pending)_ · **Status:** Open

---
**Q-6. What is `metadata.node_type`?**

Is `memory` the only value? Are there sibling node types? Is it consumed on
read, or purely a write-side artifact?

*Unblocks:* whether seeds should author it. F-3 shows it is stamped
automatically, so omitting it is safe — but if it discriminates between
node kinds, authoring it explicitly may matter for correctness rather than
tidiness.

**Answer:** _(pending)_ · **Status:** Open

---
**Q-7. Are `originSessionId` and `modified` tolerated when absent?**

F-3 establishes they are stamped on write. This asks the read-side
question: is a file lacking them valid, and is a file whose
`originSessionId` refers to no known session treated differently?

*Unblocks:* the provenance proposal — that **absence of `originSessionId`
marks a file as operator-authored rather than session-derived**. That
distinction is exactly the trust boundary a future write-back design
("Option B") would need, so it is worth establishing early. If Claude Code
backfills the field on first touch, the marker is destroyed on contact and
provenance needs a different carrier.

**Answer:** _(pending)_ · **Status:** Open

---
**Q-8. Can auto-memory writes be disabled while reads remain?**

`claude --help` shows `--bare` disables auto-memory wholesale alongside
hooks, LSP and CLAUDE.md discovery — too blunt. Is there a setting for
read-only memory, or for disabling write-back specifically?

*Unblocks:* potentially the largest simplification available. If writes can
be disabled by configuration, Option A's "no write-back" invariant becomes
**enforced** rather than merely conventional, seeded files stay pristine by
construction, and Q-3's silent-corruption risk narrows sharply.

*Where:* settings reference and CLI reference.

**Answer:** _(pending)_ · **Status:** Open

---

### Tier 3 — needed for the entrypoint work regardless

---
**Q-9. `autoMemoryDirectory`'s exact contract.**

Canonical spelling; accepted value form (absolute path, `~` expansion,
relative — and relative to what); and whether pointing it elsewhere
*migrates*, *shadows*, or *duplicates* relative to the default
project-keyed path of F-2.

*Unblocks:* the entrypoint injection design. A duplicate-copy outcome would
mean two divergent memory stores per session.

**Answer:** _(pending)_ · **Status:** Open

---
**Q-10. Settings-scope enforcement.**

Confirm `autoMemoryDirectory` is settable only from user or policy scope
and genuinely **rejected** from project scope — not merely discouraged.
The security rationale for this (an untrusted cloned repo must not be able
to redirect memory writes to an arbitrary host path) is currently
second-hand.

*Unblocks:* whether a project-scope `settings.json` under
`/workspace/.claude/` can interfere with the injected user-scope file, and
whether that is a threat the SDD must address or one the platform already
closes.

**Answer:** _(pending)_ · **Status:** Open

---
**Q-11. Format stability commitment.**

Any documented versioning or stability guarantee for the memory format,
and when it last changed.

*Unblocks:* how aggressively the validator should assert. See "Standing
risk".

*Where:* release notes at `github.com/anthropics/claude-code`; also issue
#28276, cited as the `autoMemoryDirectory` feature request.

**Answer:** _(pending)_ · **Status:** Open

---

## Standing risk — validating against a moving target

`base/Dockerfile` installs Claude Code unpinned. The memory format is
therefore free to change on any rebuild with no diff in this repository to
signal it. A structural validator built on the findings above would then
assert confidently against a stale specification — **worse than no
validator**, because it converts drift into false confidence.

Two consequences for the eventual design, recorded here so they are not
rediscovered later:

1. Assert only what is **Confirmed**, never what is **Inferred**. F-5
   (filename convention) is the concrete example: plausible, unverified,
   and not worth encoding.
2. The authoritative check is a **round-trip observation** — seed a known
   canary, run a session, confirm the content was loaded and survived —
   because it tests the implementation rather than our notes about it.
   Host-side structural checks are a fast pre-filter, not the gate.

This is also the strongest available argument for pinning the Claude Code
version in `base/Dockerfile`, which is a pre-existing, separately-tracked
concern this feature makes newly relevant rather than one it introduces.

## What this document does not decide

- Whether to seed at all, and with what content.
- The validator's mechanism (bats structural test, entrypoint check,
  standalone script) — deferred until Q-1 through Q-4 are answered, since
  those answers determine whether a validator is warranted.
- Anything about write-back or memory promotion ("Option B"), which
  remains out of scope and retains the objection recorded in
  `global-layer-injection.md` §9.
- The STRIDE impact of the entrypoint and `settings.json` changes, which
  belongs in the SDD.

## References

- `injecting_memories_into_containers.md` (repo root) — the informal
  proposal this supports, exported from an earlier session.
- `docs/designs/global-layer-injection.md` §9 — the standing decision
  against write-back persistence.
- `docs/designs/docs-as-code-workflow.md` §3 — Case E obligations.
- `check-auto-memory.sh` (repo root) — the diagnostic used here.
- Issue #32 — Squid allowlist gap that makes the documentation unreachable
  from a session.
