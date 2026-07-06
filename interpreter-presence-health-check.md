# Interpreter-Presence Health Check — Software Design Document

> **Document type:** Software Design Document (SDD)
> **Status:** Draft
> **Relates to:** `claude_code_security_plan.md` (Phase 5, Audit Logging; STRIDE coverage map),
> `global_layer_injection_sdd.md` / `global_layer_injection_impl.md` (entrypoint mechanism this
> design extends), `ARCHITECTURE.md` (Strategy A / Strategy B dependency management)
> **Audience:** The engineer maintaining this sandbox — assumes familiarity with the entrypoint
> injection mechanism, the Strategy A/B distinction in `ARCHITECTURE.md`, and the STRIDE framework
> used throughout this project's documentation.
> **Trigger incident:** `store-transfer-report`, 2026-06-22 (see `environment.md`) — a Python
> 3.12 venv persisted to `/workspace` during a Strategy B session broke when the next session's
> container started from the unmodified base image (Python 3.11 only).

---

## 1. Purpose and Scope

This document designs a narrow, deterministic check that detects — at session start, before
Claude begins working — when a Python virtual environment in `/workspace` references an
interpreter that does not exist in the current container's filesystem namespace.

### 1.1 What this is not

This is not a confidentiality, integrity, or privilege-boundary control. It does not touch the
network, filesystem isolation, or non-root-user layers that carry the actual security burden in
this architecture. It is closest to a **Repudiation (R)** control in the narrow sense of
converting a silent state mismatch into a logged one at a deterministic point — the same
principle already governing why `entrypoint.sh` logs the global-layer merge to stdout.

### 1.2 Scope of this document

This document covers:

- A venv-interpreter presence check added to `base/entrypoint.sh`
- A policy rule encoded as operator instruction, injected via `global-claude/CLAUDE.md`
- A corresponding addition to the Strategy A/B decision tree in `ARCHITECTURE.md`
- The warn-only behavior decision and its trade-offs against a hard-fail alternative
- STRIDE framing of the new surface, consistent with the existing coverage map

This document does **not** cover:

- Generalizing the check to non-venv path-dependent artifacts (compiled binaries linked against
  ephemeral shared libraries, build caches referencing ephemeral toolchain paths). See §9.
- Closing the Strategy B audit gap (ephemeral `docker exec -u root` installs falling outside
  Claude Code's session log and the entrypoint's stdout trace). That is a separate, unsolved
  problem, noted here only where it intersects with this design (§9).
- Changes to the Squid proxy, `permissions.deny`, or any other existing layer.

---

## 2. Context

### 2.1 The incident, restated structurally

A venv was created in `/workspace` during a session in which Python 3.12 had been installed
via Strategy B (`docker exec -u root ... apt-get install python3.12`, per the pattern documented
in `ARCHITECTURE.md`). The venv's `bin/python3.12` is a symlink chain terminating at
`/usr/bin/python3.12`. When that container exited (`--rm`, by design), the next session started
a fresh container from the unmodified `claude-base` image, which has only Python 3.11. The
symlink target no longer existed. Every command inside the venv failed with "cannot execute:
required file not found" — a diagnosis that took three failed attempts to localize.

### 2.2 Why the existing architecture didn't catch this

Two design properties combined to produce a silent failure mode:

- **Containers are ephemeral; `/workspace` is the one persistent surface.** This is correct and
  intentional — it's the control that prevents cross-session contamination (Phase 6,
  `claude_code_security_plan.md`: "Ephemeral containers cannot carry contamination between
  sessions"). But it means anything written to `/workspace` that encodes an assumption about the
  container's installed state outlives the container that made that assumption true.
- **Strategy B is correct policy, with an unstated boundary.** `ARCHITECTURE.md` correctly scopes
  ephemeral installs as disposable: "When the container exits, the installation disappears. If it
  was useful, add it to the appropriate Dockerfile and rebuild." What's missing is the corollary: if anything
  in `/workspace` was *built against* the ephemeral tool in the meantime, that artifact now
  carries a dependency Strategy A would have made durable, and Strategy B's "it just disappears"
  framing no longer holds for that artifact.

No control in the current architecture surfaces this gap. `entrypoint.sh` already runs
deterministically at every session start (per its own header comment) but currently only handles
global-layer injection — it has no awareness of `/workspace` contents at all.

---

## 3. Design Principles

Inherited from the existing security plan and global-layer-injection design, applied here:

**Warn, don't gate.** A broken venv is a recoverable, visible-once-you-look-at-it state, not an
unrecoverable or actively dangerous one. This control surfaces the mismatch loudly; it does not
block the session. This mirrors the existing entrypoint contract: "Must exit non-zero only on
unrecoverable errors (not on missing optional mounts)." A missing or broken venv is the same
class of "degraded, not fatal" condition as a missing global layer.

**Deterministic, not exhaustive.** The check runs identically on every session start and costs
effectively zero time for the common case (no venv, or a healthy venv). It does not attempt to
detect every class of path-dependent artifact — only the one class that has actually caused an
incident (§9 discusses scope).

**No new privilege, no new mount.** The check reads `/workspace`, which `claude-agent` already
has read access to as the bind-mount owner (via `HOST_UID` matching). It requires no `chown`, no
elevated capability, and no new mount point. It runs entirely within the existing
`--cap-drop=ALL` / `--no-new-privileges` / non-root posture.

**Policy lives where policy already lives.** The "don't build against an unpromoted interpreter"
rule is operator instruction, not code. It belongs in `global-claude/CLAUDE.md` — the existing,
already-injected channel for cross-session operator instructions — not as a new mechanism.

---

## 4. Architecture Overview

### 4.1 Current architecture (relevant slice)

```
entrypoint.sh (runs as claude-agent, at every session start)
        │
        ├─ merge global-claude/ + global-<image>/ into ~/.claude/
        └─ exec claude
                │
                ▼
        Claude Code session begins
        /workspace contents are never inspected by anything before this point
```

### 4.2 Target architecture

```
entrypoint.sh (runs as claude-agent, at every session start)
        │
        ├─ merge global-claude/ + global-<image>/ into ~/.claude/
        ├─ scan /workspace for .venv directories (new)
        │       └─ for each: verify bin/python3* resolves and executes
        │               ├─ OK            → log "[entrypoint] OK: <path>"
        │               └─ broken         → log WARNING + remediation hint
        │                                   (does not abort)
        └─ exec claude
                │
                ▼
        Claude Code session begins
        Any interpreter mismatch is already visible in the startup log
```

No new mount points, no new images, no new files outside `base/entrypoint.sh` and the two policy
documents in §6.

---

## 5. Component Design

### 5.1 `entrypoint.sh` — interpreter-presence check

**Location:** appended to the existing global-layer-injection logic in `base/entrypoint.sh`,
after the merge steps and before `exec "$@"`.

**Logic:**

```bash
echo "[entrypoint] Checking /workspace for interpreter-path mismatches"

check_venv_interpreter() {
    local venv_python="$1"
    if "$venv_python" -c "" 2>/dev/null; then
        echo "[entrypoint] OK: $venv_python"
    else
        echo "[entrypoint] WARNING: broken interpreter reference detected"
        echo "[entrypoint]   $venv_python -> $(readlink -f "$venv_python" 2>/dev/null || echo unresolvable)"
        echo "[entrypoint]   Likely cause: venv built against a Strategy B (ephemeral)"
        echo "[entrypoint]   interpreter that was never promoted to the Dockerfile."
        echo "[entrypoint]   Fix: rm -rf $(dirname "$(dirname "$venv_python")") && rebuild the venv"
    fi
}

while IFS= read -r -d '' venv_dir; do
    # Use nullglob locally so an empty match produces no iterations rather than
    # passing the literal glob string to check_venv_interpreter.
    ( shopt -s nullglob; for py in "$venv_dir"/bin/python3*; do
        check_venv_interpreter "$py"
    done )
done < <(find /workspace -maxdepth 3 -type d -name '.venv' -print0 2>/dev/null)

echo "[entrypoint] Interpreter check complete"
```

**Behavior contract:**

- Never exits non-zero on a detected mismatch. Logs a `WARNING` block and continues.
- Never modifies `/workspace`. Read-only inspection (`-c ""` is a no-op interpreter invocation
  used purely to test that the binary executes).
- Scoped to `.venv` directories up to three levels below `/workspace`. Projects nesting venvs
  deeper than that are not covered — a known, documented limitation, not a silent gap (see §9).
- Runs as `claude-agent`, same as the rest of the entrypoint. No privilege change anywhere in
  this addition.

**Why `-c ""` rather than `--version`:** a syntactically empty program forces the interpreter to
fully initialize (load its standard library paths) without depending on output formatting that
could change across Python minor versions. A binary that's merely missing or non-executable
fails this identically to one that's present but functionally broken in some other way — both
are conditions worth surfacing, and the check doesn't need to distinguish them for an operator
reading the log.

**Known false-negative — version-mismatch with a live symlink target.** If the symlink inside
the venv resolves to an existing binary (e.g., `python3` → `/usr/bin/python3.11` exists in the
new container), `-c ""` succeeds even though the venv was compiled against a different minor
version. The installed packages remain version-locked to the build-time interpreter; `pip` or
the packages themselves may fail at runtime despite the check passing. This is an accepted
limitation: the check is designed to surface the hard-fail case (missing interpreter) reliably,
not to perform full venv integrity verification. See §7.2.

### 5.2 `global-claude/CLAUDE.md` — policy rule

Addition to the existing "Git Workflow" / general instructions structure:

```markdown
## Interpreter discipline
- Before creating a venv or any build artifact in /workspace, verify the
  interpreter or toolchain version is already baked into the image
  (check the relevant Dockerfile), not installed ephemerally via
  Strategy B (docker exec -u root).
- If the needed version isn't in the image, stop and tell the operator
  to rebuild via Strategy A rather than installing it ephemerally and
  building a persistent artifact against it.
- If entrypoint logs a "broken interpreter reference" warning at session
  start, treat it as a signal to rebuild the venv before proceeding with
  any task that depends on it.
- Note: the entrypoint check only scans .venv directories up to three
  levels below /workspace (maxdepth 3). A venv nested more deeply than
  that is not inspected — apply this policy uniformly regardless of
  nesting depth.
```

This reaches every session automatically via the existing global-layer mount — no new
infrastructure, consistent with `global_layer_injection_sdd.md` §4.1's framing of what belongs in
the base layer ("instructions that apply to all projects regardless of domain").

### 5.3 `ARCHITECTURE.md` — Strategy A/B decision tree addition

Addition to the "Strategy B — Ephemeral Install" section (currently ends at the "Security note"
paragraph; append the following block immediately after it):

```markdown
**Boundary with Strategy A:** Strategy B is for *evaluating* a tool, not for building anything
durable against it. If a venv, compiled binary, or any other artifact persisted to /workspace
will depend on the ephemerally-installed tool's exact path or version, promote it via Strategy A
first. An artifact built against a Strategy B install silently inherits a dependency the image
itself does not have — the artifact will outlive the container, the tool will not.
```

### 5.4 Documentation trail

A changelog entry follows the existing convention in `docs/claude_code_security_plan.md`
(the next entry is Change 13 — the file currently ends at Change 12), recording: what changed,
why, STRIDE mapping. There is no separate `security_plan_changelog.md`; all entries go directly
into `docs/claude_code_security_plan.md`. Drafted at implementation time per §8, not duplicated
here.

---

## 6. Threat Model

### 6.1 Why this is framed as Repudiation, not Tampering or EoP

No new attack surface is introduced. The check reads files the container could already read,
executes no new privileged operation, and writes nothing. Framing it under STRIDE is mostly for
consistency with house documentation style rather than because it closes a meaningful gap in
**S/T/I/D/E**. The honest framing:

| STRIDE category | Relevance |
|---|---|
| Spoofing (S) | None. No identity claim is involved. |
| Tampering (T) | None. Read-only; no write path introduced. |
| **Repudiation (R)** | **Primary.** Converts a silent, multi-step-diagnosis failure into a one-line, timestamped log entry at a deterministic point, same logging posture as the existing global-layer merge. |
| Information Disclosure (I) | None. No data leaves the container; the warning is local stdout, captured by the existing `json-file` Docker log driver. |
| Denial of Service (D) | Slightly negative, by design choice: the check costs a `find` over `/workspace` (bounded, `maxdepth 3`) plus one subprocess spawn per venv found. Negligible for normal project sizes. Explicitly **not** escalated to a hard fail (see §6.2) to avoid turning a recoverable state into a self-inflicted availability incident. |
| Elevation of Privilege (E) | None. Runs as `claude-agent`, same user, same capability set, no `chown`. |

### 6.2 Warn-only vs. hard-fail — decision record

Two options were considered for what happens when a mismatch is detected:

- **Warn-only (selected):** log the warning, continue to `exec "$@"`. The session starts
  normally; the operator or Claude sees the warning in the startup log and can choose to rebuild
  the venv before doing anything that depends on it.
- **Hard-fail:** exit non-zero, refuse to start the session.

**Decision: warn-only.** Rationale: a broken venv is not a security-relevant condition — it's an
environment-correctness condition, and the existing entrypoint contract already reserves
non-zero exit for *unrecoverable* errors. A hard fail here would be a deterministic, self-inflicted
availability hit on every session against that project until the venv is manually rebuilt,
which is a disproportionate response to a problem that's fully diagnosable from the log and does
not block most tasks (only ones that need the venv). This also keeps the addition consistent with
the existing missing-global-layer behavior, which warns and proceeds rather than aborting.

This is documented as a decision, not an oversight — escalating to hard-fail later is a one-line
change (replace the `WARNING` echo path with `exit 1`) if experience shows operators are ignoring
the warning in practice.

### 6.3 Updated STRIDE coverage map (delta only)

| Threat (STRIDE) | Controls — pre-existing | Controls — added by this design |
|---|---|---|
| **Repudiation (R)** | Docker + Squid + Claude logs; entrypoint stdout logs for global-layer merge | Entrypoint stdout log for interpreter-path mismatches, surfaced at the same deterministic point as the rest of session-start logging |

No other row in the existing coverage map changes.

---

## 7. Interface Contract

### 7.1 Entrypoint behavior

- Runs unconditionally on every session start, after global-layer merge, before `exec "$@"`.
- Never causes a non-zero exit. (If this changes in the future per §6.2, this contract section
  must be updated and the change recorded as a new SDD revision, not a silent behavior change.)
- Scope: directories named exactly `.venv`, up to 3 levels below `/workspace`. Anything outside
  that pattern (differently-named venvs, deeper nesting, non-venv path-dependent artifacts) is
  out of scope and not silently handled — it is simply not checked.
- Output: one `OK` or `WARNING` block per discovered `.venv`, plus a completion line, all
  prefixed `[entrypoint]` consistent with existing log lines.

### 7.2 Non-goals (explicit)

- Does not modify, rebuild, or offer to rebuild the venv automatically. Remediation is a manual
  step the warning points to.
- Does not distinguish "interpreter version mismatch" from "interpreter altogether absent" from
  "interpreter present but otherwise broken" — all three produce the same warning, since the
  remediation (rebuild the venv with the available interpreter) is identical regardless.
- Does not detect the false-negative case where a venv's symlink resolves to a live but
  wrong-version interpreter (e.g., the container has `python3.11` and the venv's `python3`
  symlink happens to point there, but the venv was compiled against `python3.12`). Full
  package-level integrity verification is out of scope. See §5.1 for the accepted limitation.
- Does not close the Strategy B audit/repudiation gap for *who* or *when* the ephemeral install
  happened — only that the resulting artifact is currently broken (see §9).

---

## 8. Implementation Plan

Each step maps to a single commit, consistent with project convention.

1. **Add the interpreter-presence check to `base/entrypoint.sh`** — the logic in §5.1, appended
   after the existing global-layer merge block and before `exec "$@"`.
2. **Rebuild images** — `./build.sh`. The check lives in `claude-base`; all child images inherit
   it automatically, same inheritance path as the original entrypoint addition.
   > **Operator-only step.** Cannot be executed by Claude Code in this session: Docker is not
   > accessible from within the sandbox filesystem namespace — `docker` is not on the container's
   > PATH and the Docker socket is not mounted. Must be run by the operator on the host machine.
3. **Smoke test** — manually create a `.venv` in a test project directory with a symlink pointing
   at a nonexistent interpreter path; run `start.sh` against it; confirm the `WARNING` block
   appears and the session still reaches the `claude` prompt.
   > **Operator-only step.** Cannot be executed by Claude Code in this session for the same
   > reason as Step 2: `start.sh` launches a Docker container, which requires access to the
   > Docker daemon. Additionally, the smoke test requires observing the container's startup log
   > interactively — an out-of-band action relative to the Claude Code session itself.
4. **Add the policy rule to `global-claude/CLAUDE.md`** — the "Interpreter discipline" block in
   §5.2. **Do this in the same commit as Steps 1–3 or immediately after**, before the updated
   image is used in any real session. There is a window between Step 2 and Step 4 where the
   entrypoint check is live but the policy instruction has not yet been injected — keep that
   window as short as possible (ideally: squash Steps 1–4 into one commit, or run them
   back-to-back in a single sitting).
5. **Add the Strategy A/B boundary note to `ARCHITECTURE.md`** — the addition in §5.3.
6. **Add a changelog entry** to `docs/claude_code_security_plan.md` as Change 13, recording
   this change in the established format: what changed, why, STRIDE mapping — using §6 of this
   document as source material.

---

## 9. Open Questions and Non-Decisions

**Q: Should this generalize beyond venvs to other path-dependent artifacts (compiled binaries
linked against ephemeral shared libraries, build caches referencing ephemeral toolchain paths)?**

Not decided, and deliberately out of scope for this revision. The incident that motivated this
design was venv-specific; generalizing now risks designing against hypothetical failure modes
rather than an observed one. If a second, structurally different incident occurs, it should
inform a targeted extension rather than a speculative one written now.

**Q: Does this close the Strategy B audit gap (ephemeral installs invisible to Claude Code's
session log and the entrypoint trace)?**

No. This design detects *symptoms* of an unpromoted Strategy B install (a broken artifact); it
does not record *who* ran the ephemeral install or *when*. That gap requires capturing
`docker exec -u root` activity itself — a different control, against a different STRIDE
category (closer to true Repudiation, since it's about attributing an action, not detecting a
state). Noted here as related but explicitly not addressed by this SDD.

**Q: Should the warning escalate to hard-fail after some grace period or repeat-offense count?**

Not decided. Would require persisting state across ephemeral containers, which conflicts with the
session-isolation principle this whole architecture is built on (`global_layer_injection_sdd.md`
§2: "Each container gets its own copy of the global layer, fully independent"). If this becomes
a recurring problem despite the warning, the simpler fix is escalating to hard-fail outright
(§6.2), not building cross-session state tracking.

---

## Changelog

### Version 1.2 — 2026-07-04
Stale reference pass following operator clarification that `docs/AGENTS.md` was renamed and
merged into `ARCHITECTURE.md` at the repo root. Changes:

1. **All `docs/AGENTS.md` / `AGENTS.md` references updated to `ARCHITECTURE.md`** throughout
   (frontmatter, §1.2, §2.1, §2.2, §5.3 heading, §8 Step 5). The Strategy B section title
   ("Strategy B — Ephemeral Install") is unchanged in the target file; §5.3's addition target
   was clarified to name the exact insertion point (end of the "Security note" paragraph).
2. **Stale changelog references fixed (§5.4):** removed the nonexistent
   `docs/security_plan_changelog.md` reference; corrected to `docs/claude_code_security_plan.md`
   and noted that the next entry is Change 13 (file currently ends at Change 12).
3. **Steps 2 and 3 documented as operator-only (§8):** added inline callouts explaining why
   each step cannot be executed by Claude Code — Docker daemon not accessible from inside the
   sandbox filesystem namespace (no `docker` on PATH, no socket mount).

### Version 1.1 — 2026-07-04
Design review pass. Four issues identified and resolved:

1. **Shell glob safety (§5.1):** replaced `[ -e "$py" ]` guard with a `nullglob`-scoped
   subshell so an empty glob match produces no iterations rather than passing the literal
   pattern string to `check_venv_interpreter`.
2. **False-negative documented (§5.1, §7.2):** added explicit callout that the `-c ""`
   check passes when a venv's symlink resolves to a live-but-wrong-version interpreter
   (e.g., `python3` → `/usr/bin/python3.11` in the new container). Accepted limitation;
   full package-level integrity verification is out of scope.
3. **`maxdepth 3` propagated to policy (§5.2):** the `global-claude/CLAUDE.md` addition
   now states the three-level scan limit so operators applying the policy manually on
   deeply-nested venvs are not surprised by a silent non-detection.
4. **Implementation ordering risk noted (§8):** added guidance to minimise the window
   between Step 2 (live entrypoint check) and Step 4 (policy injection), recommending
   they be committed together or run back-to-back.

### Version 1.0 — 2026-06-27
Initial draft. Derived from the `store-transfer-report` incident (2026-06-22, see
`environment.md`) and the design discussion between the operator and Claude Sonnet 4.6.
