# Workspace Artifact Staleness — Software Design Document

> **Document type:** Software Design Document (SDD)
> **Status:** Accepted
> **Relates to:** `claude_code_security_plan.md` (Phase 5, Audit Logging; STRIDE coverage map),
> `interpreter-presence-health-check.md` (companion SDD; handles the Python venv case that
> motivated this generalization), `global_layer_injection_sdd.md` (entrypoint mechanism this
> design extends), `ARCHITECTURE.md` (Strategy A / Strategy B distinction)
> **Audience:** The engineer maintaining this sandbox — assumes familiarity with the entrypoint
> injection mechanism, the image hierarchy, and the STRIDE framework used throughout this
> project's documentation.

---

## 1. Purpose and Scope

This document designs staleness checks for two additional classes of path-dependent artifacts
that can be persisted to `/workspace` and silently break when a fresh container starts from the
unmodified base image: CMake build directories and Node.js native addons.

It also establishes a formal three-tier taxonomy for this entire problem class, providing a
documented ceiling that explains what is and is not detectable within the security constraints of
this architecture — and why. This taxonomy is the primary architectural contribution of this
document; the two concrete checks are applications of it.

### 1.1 Relationship to the interpreter-presence SDD

`interpreter-presence-health-check.md` defined the venv check and introduced the problem class
informally. This document is its complement: it handles the remaining artifact types that share
the same root cause (a path-dependent artifact in `/workspace` outlives the container state it
was built against), frames the full generalization space using a three-tier taxonomy, and
establishes a formal hard limit for what this architecture can and cannot safely detect.

### 1.2 Scope of this document

This document covers:

- The three-tier generalization taxonomy (Tier 1: clean, Tier 2: partial with documented
  ceiling, Tier 3: hard architectural limit)
- A Tier 1 check for CMake build directories (`claude-systems`)
- A Tier 2 check for Node.js native addons (`claude-base` and all images that inherit it)
- The formal rationale for why ELF binary dependency checking via `ldd` is an architectural
  hard limit, not a deferred implementation task
- STRIDE framing consistent with the existing coverage map
- Image-routing strategy (universal checks vs. image-scoped checks)
- The additions to `ARCHITECTURE.md` needed to make the boundary explicit for operators and
  for Claude Code itself

This document does **not** cover:

- The Python venv check (owned by `interpreter-presence-health-check.md`)
- Any artifact type not in Tier 1 or Tier 2 as defined by the taxonomy in §3
- Changes to the Squid proxy, `permissions.deny`, or any other existing layer
- Container-internal state that is never persisted to `/workspace` (e.g., the SoftHSM2 token
  directory `/var/lib/softhsm/`, the p11-kit module config in `~/.config/pkcs11/`)

---

## 2. Context

### 2.1 The general problem class

`interpreter-presence-health-check.md` §2 identified the root asymmetry: containers are
ephemeral by design; `/workspace` is the one persistent surface. Any artifact written to
`/workspace` that encodes a dependency on the container's installed state outlives the container
that made that dependency satisfiable.

The Python venv is the observed instance. But the same structural failure applies to any build
artifact that captures absolute toolchain paths, ABI versions, or shared library linkage at
construction time. Two additional artifact classes share this failure mode:

- **CMake build directories** encode the absolute path to every compiler and linker used at
  configure time. If a C compiler was installed ephemerally and the build directory persists,
  subsequent `cmake --build` invocations in a fresh container will attempt to invoke the absent
  binary and fail, often with a cryptic CMake generator error rather than a clear "file not
  found."
- **Node.js native addons** (`.node` files in `node_modules`) are compiled against a specific
  Node.js ABI version. If Node is upgraded in the image and the addon was compiled against the
  previous ABI, the addon will fail to load at runtime with `NODE_MODULE_VERSION` mismatch —
  again, not a clear "rebuild me" message.

### 2.2 Why uniform detection is not achievable

Each artifact class exposes different diagnostic information and presents different execution
risks when inspected. Any complete treatment of this problem space must therefore be structured
as a taxonomy of what is and is not feasible, rather than a uniform checklist. §3 provides that
taxonomy.

---

## 3. Three-Tier Generalization Taxonomy

This is the governing framework for all current and future staleness checks in this
architecture. Any new check must be classified against this taxonomy before implementation.

### Tier 1 — Clean generalizations

**Properties:** The check requires only static text inspection or a safe, bounded binary
invocation (e.g., `python3 -c ""`). No execution of workspace-resident code. Produces a binary
OK / WARNING result with no meaningful false positive class. Consistent with the existing
`claude-agent` capability set.

**Current members:**
- Python venv interpreter check (owned by `interpreter-presence-health-check.md`)
- CMake toolchain path check (§5.1 of this document)

### Tier 2 — Partial generalizations with documented ceilings

**Properties:** A meaningful check is possible, but it is weaker than full validity verification
— either because full verification requires executing code, or because static analysis of the
artifact's binary format is non-trivially fragile. The check is a presence warning, not a
correctness assertion. The ceiling must be documented explicitly; consumers of the check must
understand what it does and does not guarantee.

**Current members:**
- Node.js native addon presence warning (§5.2 of this document)

### Tier 3 — Hard architectural limit

**Properties:** A correct check would require executing a workspace-resident binary or invoking
a tool (`ldd`) that does so. This violates the security boundary. The limit is architectural, not
a deferred implementation task. It must be documented explicitly and permanently, not treated as
a gap to fill later.

**Current member:**
- General ELF binary dependency checking via `ldd` (§6.3)

---

## 4. Design Principles

Inherited from the existing security plan and extended where the new artifact classes require it.

**Read-only, no execution of workspace-resident code.** The only binaries this check may
execute are image-resident binaries installed via Strategy A (`find`, `grep`, `readlink`, `test`,
and the Python interpreter). A `.node` file or any other binary resident in `/workspace` is an
untrusted surface and must never be executed from the entrypoint context.

**Warn, don't gate.** Consistent with the interpreter-presence SDD and the existing entrypoint
contract: a stale build artifact is a recoverable environment-correctness condition, not an
unrecoverable or security-relevant failure. The session is not aborted. See §7.2 for the decision
record.

**Universal checks, zero routing complexity.** Both checks run in all images. A CMake check
finding no `CMakeCache.txt` in a `claude-crypto` container is a sub-millisecond no-op. Routing
checks per image would require either ENV-based dispatch in the entrypoint or separate
entrypoint scripts per child image — both of which add complexity and divergence risk across the
image hierarchy for no meaningful gain. Universal checks are simpler, auditable, and consistent
with how the interpreter-presence check is deployed.

**Document ceilings explicitly, at architectural level.** A Tier 2 check that produces a
presence warning must say it is a presence warning. A Tier 3 limit must say it is a hard limit
and why. Implicit gaps are defects in security architecture.

---

## 5. Component Design

### 5.1 CMake build directory check (Tier 1)

**Location:** `base/entrypoint.sh`, after the interpreter-presence check block, before
`exec "$@"`.

**Artifact:** `CMakeCache.txt`. Produced by `cmake -S ... -B ...` at configure time. Contains
`CMAKE_C_COMPILER:FILEPATH=` and `CMAKE_CXX_COMPILER:FILEPATH=` entries (among others) encoding
the absolute paths to the compilers used. A plain text file — no binary parsing, no execution.

**Logic:**

```bash
echo "[entrypoint] Checking /workspace for stale CMake build directories"

while IFS= read -r -d '' cache; do
    while IFS= read -r entry; do
        path="${entry#*=}"
        if [ -n "$path" ] && [ ! -x "$path" ]; then
            echo "[entrypoint] WARNING: stale CMake toolchain path detected"
            echo "[entrypoint]   Cache:  $cache"
            echo "[entrypoint]   Entry:  $entry"
            echo "[entrypoint]   Missing or non-executable: $path"
            echo "[entrypoint]   Likely cause: compiler installed ephemerally (Strategy B)"
            echo "[entrypoint]   and not promoted to the Dockerfile before this path was"
            echo "[entrypoint]   captured at cmake configure time."
            echo "[entrypoint]   Fix: rm -rf $(dirname "$cache") && re-run cmake"
        else
            echo "[entrypoint] OK: CMake toolchain path $path"
        fi
    done < <(grep -E "^CMAKE_(C|CXX)_COMPILER:FILEPATH=" "$cache" 2>/dev/null)
done < <(find /workspace -maxdepth 4 -name "CMakeCache.txt" -print0 2>/dev/null)

echo "[entrypoint] CMake check complete"
```

**Why `grep -E` on the cache rather than a CMake API call:** `cmake -LA` (list all variables)
requires a configured build directory and executes CMake itself. Plain `grep` on `CMakeCache.txt`
is purely textual and sufficient — the `FILEPATH` entries are stable, human-readable, and
written deterministically by all CMake versions relevant to this image. No CMake subprocess.

**Scope:** `maxdepth 4` covers the common patterns (`build/`, `cmake-build-debug/`,
`out/build/x64-Debug/`) without unbounded recursion. Deeper nesting is an undocumented ceiling
(§9.2).

**False positive class:** A compiler path that exists in the image but is non-executable (mode
`0644` instead of `0755`) would produce a spurious warning. This is an extremely unlikely
condition in a Debian image but should be noted. In practice, if `gcc` is not executable, the
container has a more fundamental problem.

### 5.2 Node.js native addon check (Tier 2)

**Location:** `base/entrypoint.sh`, after the CMake check block, before `exec "$@"`.

**Artifact:** `.node` files under `node_modules/`. Compiled C++ addons loaded at runtime via
`require()`. ABI-version-dependent: compiled against a specific `NODE_MODULE_VERSION` (the
integer that identifies Node.js ABI compatibility). If the Node version in the image changes and
the addon was compiled against the previous ABI, the addon silently fails to load with a
`NODE_MODULE_VERSION` mismatch error — not a "rebuild me" message.

**Check type: Tier 2 (presence warning, not correctness assertion).** Full ABI verification
requires either executing Node (`node -e "require('./addon.node')"`) or statically parsing the
ELF NAPI version tag — the former executes untrusted workspace code; the latter requires
`readelf` (not in the base image, and fragile across NAPI vs. V8 API addons). The presence
warning is the correct ceiling for this tier.

**Logic:**

```bash
echo "[entrypoint] Checking /workspace for Node.js native addons"

ADDON_COUNT=0
while IFS= read -r -d '' addon; do
    ADDON_COUNT=$((ADDON_COUNT + 1))
    echo "[entrypoint] WARNING: native Node.js addon present"
    echo "[entrypoint]   $addon"
    echo "[entrypoint]   Native addons are ABI-version-dependent. If the Node.js version"
    echo "[entrypoint]   in this image differs from the one used to compile this addon,"
    echo "[entrypoint]   it will fail to load at runtime with a NODE_MODULE_VERSION error."
    echo "[entrypoint]   Fix: rm -rf $(dirname "$(dirname "$addon")") && npm install"
done < <(find /workspace -maxdepth 5 -path "*/node_modules/*.node" -print0 2>/dev/null)

if [ "$ADDON_COUNT" -eq 0 ]; then
    echo "[entrypoint] OK: no native Node.js addons found"
fi

echo "[entrypoint] Node.js addon check complete"
```

**What this guarantees:** that the operator knows native addons are present and may need
rebuilding. It does not guarantee they are broken, and it does not guarantee they are valid if
no warning is produced (a `.node` file could still be broken for other reasons; this only checks
presence, not ABI correctness).

**Why the aggregate count before the conditional:** some projects have many addons (e.g., a
project using `node-gyp` for several native dependencies). Emitting one warning line per addon
with context is more actionable than a single aggregate count. The count variable is used only to
distinguish "zero found" (clean state) from "one or more found" (warn state) for the final
summary line.

---

## 6. Threat Model

### 6.1 New surfaces introduced

| Surface | Description |
|---|---|
| `CMakeCache.txt` read | Entrypoint reads a text file from `/workspace` via `grep` — no execution |
| `find` over `/workspace` for `.node` files | Filesystem traversal only — no execution of discovered files |
| `test -x` on compiler paths | Tests executability of image-resident binaries — no execution of workspace-resident code |

None of these surfaces introduces an execution path for workspace-resident code.

### 6.2 STRIDE analysis

**Tampering (T)**

_Threat:_ A crafted `CMakeCache.txt` in `/workspace` contains a malicious `FILEPATH` entry
designed to cause `grep` or the surrounding bash logic to behave incorrectly — e.g., a path
containing shell metacharacters.

_Control:_ The path value is used only in two ways: passed to `test -x` (safe — `test` does not
interpret its argument as shell code) and echoed to stdout for logging. Neither operation
executes the path or passes it to a shell that would expand it. The `while read` loop with
`IFS= read -r` is the correct bash pattern for reading arbitrary strings without word splitting
or glob expansion. No injection risk.

_Residual risk:_ A path containing a newline could split across log lines, producing misleading
output. In practice, CMake does not write newlines into `FILEPATH` entries and the `grep`
pattern is anchored to a line start — this is an academic edge case.

**Information Disclosure (I)**

_Threat:_ Entrypoint log output (captured by Docker's `json-file` driver) reveals the contents
of `CMakeCache.txt` compiler paths or the presence of native addons — information an attacker
who can read Docker logs could use to profile the toolchain.

_Control:_ Docker logs are accessible only to host-level operators (root or `docker` group
membership on the host). This is within the existing threat model's accepted access boundary.
The information disclosed (compiler binary paths, presence of `.node` files) is not sensitive
in this architecture.

**Elevation of Privilege (E)**

_Threat:_ The check could be used as an injection vector to execute code with the entrypoint's
process identity before `exec claude`.

_Control:_ No workspace-resident binary is executed. `find`, `grep`, `test`, `readlink`, and
`echo` are all image-resident binaries installed via Strategy A. The check runs as
`claude-agent` under `--cap-drop=ALL` and `--no-new-privileges` — identical to the rest of
the entrypoint.

**Repudiation (R)**

_Primary positive contribution:_ Both checks log their results to stdout, captured by the
`json-file` Docker log driver (50 MB retention, per the existing `start.sh`). A session that
began with a stale CMake cache or native addon is now auditable after the fact — the warning
appears in the container's startup log with a timestamp, the specific cache or addon path, and
the remediation step. Before this change, the failure was silent at session start and only
appeared cryptically at the point of use.

### 6.3 The Tier 3 hard limit — ELF binary dependency checking via `ldd`

This is the architectural boundary this taxonomy exists to formally document.

`ldd` determines the shared library dependencies of a compiled binary. It works by invoking the
dynamic linker (`ld-linux.so`) on the target binary, which causes the binary's `.init` sections
to execute and `LD_PRELOAD` to be honoured. Against a binary of unknown provenance residing in
`/workspace`, this is a code execution vulnerability in the entrypoint context: before `exec
claude`, before any `permissions.deny` rule is active, before Claude Code has taken control of
the session.

A crafted ELF binary in `/workspace` with a malicious `.init` section would execute under
`claude-agent` with whatever capabilities the entrypoint process holds. Even under `--cap-drop=ALL`
and `--no-new-privileges`, that is execution of attacker-controlled code at the highest-privilege
moment of the session relative to `/workspace` access.

`readelf -d` (static extraction of `NEEDED` entries without execution) avoids this, but
introduces a different problem: satisfiability checking. Knowing that a binary `NEEDS`
`libssl.so.3` does not tell you whether the version on disk satisfies the symbol version
requirements without replicating `ld-linux.so`'s resolution logic — including `rpath`, `runpath`,
`LD_LIBRARY_PATH`, and versioned symbol matching. Implementing this correctly in a shell entrypoint
script is non-trivially fragile and would require `binutils` (`readelf`) to be added to
`claude-base`, increasing the image's attack surface for a check that covers an unobserved
failure mode.

**Ruling:** `ldd`-based dependency checking is permanently out of scope for this architecture.
The constraint is security-first, not convenience. If a compiled binary in `/workspace` has been
linked against an ephemerally-installed library, the correct mitigation is the operator policy
in `ARCHITECTURE.md` (Strategy A promotion before building) and the absence of any automated
entrypoint check. Operators who need to verify binary dependencies should do so explicitly with
`docker exec -u root` after the session starts, using `readelf -d` manually, with awareness of
what they are running and why.

This ruling must not be overturned by a future change to this or any related SDD without a full
threat model revision covering the code execution risk.

### 6.4 Updated STRIDE coverage map (delta only)

| Threat (STRIDE) | Controls — pre-existing | Controls — added by this design |
|---|---|---|
| **Repudiation (R)** | Docker + Squid + Claude logs; entrypoint stdout for global-layer merge; entrypoint stdout for interpreter-path mismatches | Entrypoint stdout for stale CMake toolchain paths; entrypoint stdout for native addon presence |
| **Tampering (T)** | Container filesystem scope + `permissions.deny`; readonly mounts at `/run/` | No change. The `IFS= read -r` pattern in the CMake check prevents bash metacharacter injection from crafted `FILEPATH` values. |

No other rows change.

---

## 7. Interface Contract

### 7.1 Entrypoint behavior

- Both checks run unconditionally on every session start, in every image, after the
  interpreter-presence check and before `exec "$@"`.
- Neither check causes a non-zero exit under any condition.
- Scope for CMake: directories named `CMakeCache.txt`, up to 4 levels below `/workspace`.
- Scope for Node addons: files with the `.node` extension, under any `node_modules/` directory,
  up to 5 levels below `/workspace`.
- Checks outside these depths are not performed and are not silently ignored — they are simply
  out of scope, as documented in §9.

### 7.2 Warn-only decision record

Identical rationale to `interpreter-presence-health-check.md` §6.2: a stale build artifact is
recoverable and does not block all work in the session, only work that depends on the stale
artifact. The existing entrypoint contract reserves non-zero exit for unrecoverable errors.
Escalating these checks to hard-fail would impose a disproportionate availability cost on
sessions where the operator can work around the staleness or remediate it immediately.

Escalation to hard-fail is a one-line change in each check block if experience shows warnings
are systematically ignored. That decision requires no new SDD — a changelog entry in this
document and an update to §7.1 are sufficient.

### 7.3 What these checks do not guarantee

- A CMake build directory that passes the toolchain check may still be stale for other reasons
  (changed CMake version, changed `find_package` results, changed system headers). The check
  verifies only compiler binary presence.
- A project with no `.node` files found may still have broken native addons (e.g., stored under
  a non-standard naming convention or at depths beyond `maxdepth 5`). The check verifies only
  the presence of the standard pattern.
- Neither check verifies anything about library linkage or ABI compatibility beyond what is
  described in §5. These are environment-signal checks, not build system validators.

---

## 8. Implementation Plan

Each step maps to a single commit.

1. **Add the CMake build directory check to `base/entrypoint.sh`** — the logic in §5.1,
   appended after the interpreter-presence check block and before the Node check.
2. **Add the Node.js native addon check to `base/entrypoint.sh`** — the logic in §5.2,
   appended after the CMake check block and before `exec "$@"`.
3. **Rebuild images** — `./build.sh`. The checks live in `claude-base`; all child images
   inherit them automatically.
4. **Smoke test (CMake)** — create a synthetic `CMakeCache.txt` in a test directory under
   `/workspace` containing a `CMAKE_CXX_COMPILER:FILEPATH=` entry pointing at a nonexistent
   path; run `start.sh`; confirm the `WARNING` block appears and the session reaches the
   `claude` prompt.
5. **Smoke test (Node)** — create a zero-byte `fake.node` file under
   `/workspace/node_modules/fake/`; confirm the presence warning appears and the session
   proceeds normally.
6. **Add the Tier 2 ceiling and Tier 3 limit to `ARCHITECTURE.md`** — an explicit subsection
   under "What Not to Do" documenting the `ldd` ruling and the boundary of the Node presence
   warning.
7. **Add a changelog entry** to `docs/claude_code_security_plan.md` as Change 14, recording
   this change in the established format, using §6.4 and §6.3 as source material.

---

## 9. Open Questions and Non-Decisions

### 9.1 Should `maxdepth` be configurable per project?

Not decided. The current values (4 for CMake, 5 for Node) are heuristics covering common
project layouts. A monorepo with deeply nested packages may produce no warnings for stale
artifacts outside these depths. Per-project configuration would require either a dotfile in
`/workspace` (a new convention, a new injection path) or an operator-supplied ENV variable
(adds `start.sh` complexity). The silent miss is preferable to new configuration surface area
until a real case requires it. If it does, add a note here and revisit.

### 9.2 Should this SDD cover non-venv Python artifacts (`.pyc` files, `__pycache__`)?

No. `.pyc` files encode the Python version in their magic number and are silently regenerated
by CPython when the version changes — they do not cause the class of hard failure this taxonomy
addresses. This is a different failure mode (performance/behavior, not "cannot execute") and is
outside scope.

### 9.3 Is there a safe static check for Node ABI compatibility using `readelf`?

Potentially. The NAPI version is stored in a `.note.gnu.nabi-tag`-style section or in the
symbol table of NAPI-based addons. `readelf -n` or `readelf --dyn-syms` could extract it
without executing the binary. `readelf` is in the `binutils` package, not currently in
`claude-base`. If this path is pursued, it requires: (a) adding `binutils` to `claude-base`
(increasing image attack surface), (b) handling both NAPI and NAN/V8 API addons differently
(NAN addons encode ABI in `NODE_MODULE_VERSION` in the binary's symbol table, not in a note
section), and (c) comparing the result against `node -e "process.version"` output (safe, since
`node` is image-resident). This would promote the Node check from Tier 2 to Tier 1. Not pursued
in this revision — the additional complexity should be motivated by an observed incident, not
preemptive design.

---

## Changelog

### Version 1.1 — 2026-07-06
Pre-implementation review pass. Changes:

1. **Status updated Draft → Accepted** — design approved by operator.
2. **Stale `docs/AGENTS.md` references updated to `ARCHITECTURE.md`** — throughout frontmatter,
   §1.2, §6.3, and §8 Step 6. File was renamed and promoted to repo root in PR #6.
3. **§8 Step 7 changelog number corrected** — "Change 13 or the next available number" updated
   to "Change 14"; Change 13 was consumed by the interpreter-presence health check (PR #6).
4. **§8 Step 6 insertion point clarified** — target section named as "What Not to Do" to match
   the actual heading in `ARCHITECTURE.md`.

### Version 1.0 — 2026-06-27
Initial draft. Establishes the three-tier generalization taxonomy and covers CMake build
directory (Tier 1) and Node.js native addon (Tier 2) staleness checks. Companion to
`interpreter-presence-health-check.md`. Formally documents the ELF/`ldd` hard architectural
limit as Tier 3. Derived from design discussion between the operator and Claude Sonnet 4.6.
