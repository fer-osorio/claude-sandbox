# Global Layer Injection — Software Design Document

> **Document type:** Software Design Document (SDD)
> **Status:** Approved for implementation
> **Relates to:** `claude_code_security_plan.md` (Phases 2–6), `squid_proxy_guide.md`
> **Audience:** The engineer maintaining this sandbox — assumes familiarity with the existing
> threat model, STRIDE categories, and the image hierarchy already documented in the security plan.

---

## 1. Purpose and Scope

This document designs the mechanism by which Claude Code's *global layer* — the operator-curated
set of cross-project instructions, skills, and commands that Claude reads at session start — is
injected into every sandbox container at launch time.

### 1.1 What the global layer is

Claude Code loads configuration from multiple scopes at session start, each stacking on top of
the previous. From broadest to most specific:

| Scope | Source on a host installation |
|---|---|
| User instructions | `~/.claude/CLAUDE.md` |
| Personal skills | `~/.claude/skills/` |
| Personal commands | `~/.claude/commands/` |
| Project instructions | `./.claude/settings.json`, `./CLAUDE.md` |

Inside the sandbox, there is no persistent home directory — each container starts from a clean
image. Without explicit injection, none of the user-scoped layer reaches Claude, and every session
starts as if it were the operator's first ever interaction with the tool.

This design corrects that gap while preserving all existing security properties.

### 1.2 Scope of this document

This document covers:

- The design of a curated host directory (`global-claude/`) that stands in for `~/.claude/`
- A per-image overlay directory (`global-<image>/`) that layers domain-specific additions on top
- A non-root entrypoint script that merges these layers into the container's home directory at
  startup
- The STRIDE threat analysis for each new surface introduced
- The directory layout changes to `~/.claude-sandbox/`
- The interface changes to `start.sh` and `base/Dockerfile`

This document does **not** cover:

- Changes to the Squid proxy configuration
- Changes to `settings.json` permission rules (covered separately in the implementation guide)
- Multi-user or CI/CD deployments

---

## 2. Design Principles

These principles govern every decision in this design. They are inherited directly from the
existing security plan and extended where the new feature requires it.

**Least privilege at the mount point.** The host directory mounted into the container is the
minimum necessary surface — not `~/.claude/` wholesale, but a curated subdirectory containing
only what was consciously authored for injection. Session history, auto-memory from other
projects, and credential artifacts never enter the container filesystem namespace.

**Physical absence over permission checks.** The strongest control is not a permission that could
be misconfigured — it is the data simply not being present. The curated directory contains no
secrets. The mount is readonly at the OS level. Defense in depth means both controls are active
simultaneously.

**Writable working copy, readonly source.** The entrypoint copies files from the readonly mount
into the container's home directory. Claude writes auto-memory to the copy, not the source. When
the container exits, the working copy is destroyed with it. The host source is never modified by
a container process.

**Overlay, not replacement.** Domain-specific additions (crypto skills, systems skills) are
applied on top of the base global layer using the same merge logic. No image-specific file can
silently replace a base-level rule — files are merged directory-by-directory, with overlay files
taking precedence only where filenames collide, which is the documented and expected behavior.

**Session isolation.** Each container gets its own copy of the global layer, fully independent.
A prompt injection that corrupts Claude's in-session memory in one container cannot affect the
next session or any other concurrent session.

**Auditability.** Every file in the injected layer is a source-controlled text file with a
human-readable diff history. The operator can reconstruct exactly what Claude was told in any
past session by checking out the relevant commit.

---

## 3. Architecture Overview

### 3.1 Current architecture (before this change)

```
HOST
├── ~/.claude-sandbox/
│   ├── build.sh
│   ├── start.sh
│   ├── base/Dockerfile
│   ├── crypto/Dockerfile
│   ├── systems/Dockerfile
│   ├── research/Dockerfile
│   └── squid/
│
└── CONTAINER (per session)
    ├── /workspace          ← bind mount of project dir (rw)
    ├── /home/claude-agent/ ← empty; no global layer present
    └── /run/               ← unused
```

Claude Code starts with no cross-session instructions. Every session is a blank slate at the
user-instruction scope.

### 3.2 Target architecture (after this change)

```
HOST
├── ~/.claude-sandbox/
│   ├── build.sh
│   ├── start.sh              ← modified: mounts global layers
│   ├── global-claude/        ← new: base global layer (all images)
│   │   ├── CLAUDE.md
│   │   ├── skills/
│   │   └── commands/
│   ├── global-crypto/        ← new: overlay for claude-crypto
│   │   └── skills/
│   ├── global-systems/       ← new: overlay for claude-systems
│   │   └── skills/
│   ├── global-research/      ← new: overlay for claude-research
│   │   └── skills/
│   ├── base/
│   │   ├── Dockerfile        ← modified: adds entrypoint
│   │   └── entrypoint.sh     ← new
│   ├── crypto/Dockerfile
│   ├── systems/Dockerfile
│   ├── research/Dockerfile
│   └── squid/
│
└── CONTAINER (per session)
    ├── /workspace               ← bind mount of project dir (rw)
    ├── /run/claude-global/      ← bind mount of global-claude/ (ro)
    ├── /run/claude-overlay/     ← bind mount of global-<image>/ (ro, if exists)
    └── /home/claude-agent/.claude/   ← writable copy, merged by entrypoint
```

### 3.3 Data flow at container startup

```
start.sh launches container
        │
        ├─ mounts /run/claude-global  (readonly)
        └─ mounts /run/claude-overlay (readonly, if overlay dir exists)
                │
                ▼
        entrypoint.sh executes (as claude-agent)
                │
                ├─ mkdir -p ~/.claude
                ├─ cp -r /run/claude-global/.   ~/.claude/
                │         (base layer applied)
                ├─ cp -r /run/claude-overlay/.  ~/.claude/   [if mount present]
                │         (overlay applied; collisions resolved: overlay wins)
                └─ exec claude
                        │
                        ▼
                Claude Code session begins
                ~/.claude/ is readable and writable
                /run/claude-global/ and /run/claude-overlay/ are readonly
                auto-memory writes go to ~/.claude/ (ephemeral, destroyed on exit)
```

---

## 4. Component Design

### 4.1 `global-claude/` — the base global layer directory

**Location on host:** `~/.claude-sandbox/global-claude/`

**Purpose:** Contains the files that Claude should receive in every session regardless of image
type. This is the operator's cross-project global configuration, curated and version-controlled.

**Contents (minimal initial structure):**

```
global-claude/
├── CLAUDE.md          — cross-project operator instructions
├── skills/            — skills available in all sessions
│   └── <skill-name>/
│       └── SKILL.md
└── commands/          — slash commands available in all sessions
    └── <command>.md
```

**What belongs here:** Instructions that apply to all projects regardless of domain — coding
standards, commit message conventions, security reminders, tool usage preferences, response
format preferences.

**What does not belong here:** Project-specific context (use the project's own `CLAUDE.md` for
that), domain-specific skills (use the overlay directories for those), secrets or credentials
(use environment variables), anything generated by Claude at runtime (auto-memory is ephemeral
and does not live here).

**Version control:** This directory should be tracked in the same git repository as the sandbox
infrastructure. Every change to `CLAUDE.md` or any skill file produces a reviewable diff. The
operator can reconstruct what Claude was instructed during any historical session by checking out
the relevant commit.

### 4.2 `global-<image>/` — per-image overlay directories

**Locations on host:**
- `~/.claude-sandbox/global-crypto/`
- `~/.claude-sandbox/global-systems/`
- `~/.claude-sandbox/global-research/`

**Purpose:** Extend the base global layer with domain-specific skills and commands that are
relevant only when working with a particular image type. A crypto session gets PKCS#11 workflow
skills. A systems session gets CMake and sanitizer skills. A research session gets LaTeX
compilation skills.

**Merge behavior:** The entrypoint applies the base layer first, then the overlay. Because `cp -r`
is used with the overlay applied second, a file in `global-crypto/skills/foo/SKILL.md` silently
replaces `global-claude/skills/foo/SKILL.md` if both exist. This is intentional and documented:
domain-specific skills can override base skills of the same name. Operators who need to prevent
overrides should use distinct skill names.

**Absence is valid:** If `global-systems/` does not exist, `start.sh` does not pass the overlay
mount flag, and the entrypoint skips the overlay merge step without error. No image is required
to have an overlay.

**What belongs here:** Skills and commands specific to a domain — HSM initialization patterns for
crypto, CMake project structure conventions for systems, BibTeX workflow for research.

**What does not belong here:** Cross-domain instructions (those go in `global-claude/`),
image-level configuration (that lives in the Dockerfile), secrets.

### 4.3 `entrypoint.sh` — the merge script

**Location in image:** `/usr/local/bin/entrypoint.sh`

**Runs as:** `claude-agent` (non-root). The script has no sudo access and cannot write outside
directories owned by `claude-agent`.

**Responsibilities:**
1. Create `~/.claude/` if it does not exist.
2. Copy the base global layer from `/run/claude-global/` into `~/.claude/`.
3. If `/run/claude-overlay/` is present and non-empty, copy the overlay layer into `~/.claude/`,
   allowing overlay files to overwrite base files where names collide.
4. Log each step to stdout so Docker captures it in the container log (Repudiation control).
5. `exec "$@"` — hand off to the CMD (`claude`) with no subprocess overhead.

**What the script does not do:**
- It does not run as root and cannot `chown` anything.
- It does not touch `/workspace`.
- It does not make network connections.
- It does not modify `/run/claude-global/` or `/run/claude-overlay/` (they are readonly mounts;
  any write attempt would fail at the OS level regardless).

**Failure behavior:** If the base global directory is absent (the mount was not passed), the
script logs a warning and proceeds. Claude Code starts without a global layer — degraded
experience, but not a security failure. The session is not aborted.

### 4.4 `start.sh` — launcher modifications

**New responsibilities:**
- Resolve the path of the base global layer directory.
- Determine whether a per-image overlay directory exists for the selected image.
- Add the appropriate `--mount` flags for whichever directories are present.
- Pass no overlay mount if the overlay directory does not exist.

**Interface:** Unchanged. `start.sh <project_dir> [image]` continues to work as before. The
global layer injection is fully transparent to the operator.

**Mount point selection:** The global directories are mounted under `/run/` rather than directly
under `/home/claude-agent/.claude/` for two reasons. First, a direct mount of a readonly
directory into `~/.claude/` would prevent Claude Code from writing auto-memory there, which
causes silent failures. Second, `/run/` is a conventional location for runtime data injected
into a container, making the architecture self-documenting.

### 4.5 `base/Dockerfile` — entrypoint addition

**Change:** Two additions to the base Dockerfile, applied after the `claude-agent` user is
created:

1. `COPY entrypoint.sh /usr/local/bin/entrypoint.sh` (as root, before `USER claude-agent`)
2. `RUN chmod +x /usr/local/bin/entrypoint.sh` (as root)
3. `ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]` (replaces the implicit no-op entrypoint)
4. `CMD ["claude"]` (unchanged — passed to `exec "$@"` in the entrypoint)

Because the entrypoint is added to `claude-base`, all child images (`claude-crypto`,
`claude-systems`, `claude-research`) inherit it automatically without changes to their own
Dockerfiles.

---

## 5. Threat Model

This section extends the STRIDE coverage map from `claude_code_security_plan.md` to account
for the new surfaces introduced by this design.

### 5.1 New surfaces

| Surface | Description |
|---|---|
| `global-claude/` host directory | Contains operator-authored instructions; readable by container |
| `global-<image>/` host directories | Overlay instructions; readable by container |
| `/run/claude-global/` mount point | Readonly view of `global-claude/` inside container |
| `/run/claude-overlay/` mount point | Readonly view of overlay directory inside container |
| `~/.claude/` working copy | Writable copy created by entrypoint; destroyed on container exit |
| `entrypoint.sh` | Runs at container start; merges the above; execs `claude` |

### 5.2 STRIDE analysis of new surfaces

**Tampering (T)**

_Threat:_ A prompt injection causes Claude to modify files in `global-claude/` on the host,
poisoning future sessions.

_Controls:_
- `/run/claude-global/` and `/run/claude-overlay/` are mounted readonly. Any write attempt
  fails at the kernel level before any application logic runs.
- `permissions.deny` in `settings.json` should include `Write(/run/*)` as an additional
  application-level gate.
- `claude-agent` does not have write access to the bind-mount source directories on the host.

_Residual risk:_ None above the baseline. The physical readonly mount is the primary control;
`permissions.deny` is defense in depth.

**Information Disclosure (I)**

_Threat 1:_ A compromised Claude session reads sensitive content from the global layer and
exfiltrates it via a network call.

_Controls:_
- The global layer directories contain no secrets by design (see Section 4.1).
- Network exfiltration is blocked by the Squid proxy allowlist regardless.
- `permissions.deny` blocks `curl`, `wget`, `nc`, and `scp` at the application layer.

_Threat 2:_ The global layer directories on the host are readable by other processes.

_Controls:_
- Standard host filesystem permissions apply. The directories are owned by the host user and
  not world-readable.
- This is outside the container threat model but is worth noting.

_Threat 3:_ The working copy in `~/.claude/` within the container contains sensitive
auto-memory written during the session, which another process inside the same container reads.

_Controls:_
- Each container is a single-process session (Claude Code). There are no co-tenant processes.
- The container exits and the working copy is destroyed when the session ends.

**Elevation of Privilege (E)**

_Threat:_ The entrypoint script runs as root and can be used to escalate privileges.

_Controls:_
- `entrypoint.sh` runs as `claude-agent` (non-root). The `USER claude-agent` directive in the
  Dockerfile applies before the entrypoint executes.
- `--security-opt=no-new-privileges` on the container prevents any `setuid` escalation.
- `--cap-drop=ALL` removes all Linux capabilities. The entrypoint cannot call any privileged
  kernel interface even if exploited.

**Repudiation (R)**

_Threat:_ There is no record of what global layer content was active during a past session.

_Controls:_
- The global layer directories are version-controlled. The git log of `global-claude/` is the
  audit trail of what Claude was instructed in any past session.
- The entrypoint logs each merge step to stdout, which Docker captures in the container log
  (json-file driver, 50 MB retention).

**Spoofing (S)**

_Threat:_ A malicious file placed in `global-claude/` by a supply chain attack impersonates
a legitimate skill and hijacks Claude's behavior.

_Controls:_
- The operator authors and reviews every file in `global-claude/`. No automated process writes
  to this directory.
- Version control provides a diff-based review mechanism for every change.
- This threat is equivalent to an attacker modifying the operator's source code — outside the
  container threat model, but mitigated by standard source control hygiene.

**Denial of Service (D)**

_Threat:_ A very large `global-claude/` directory bloats the container startup time or the
Claude context window.

_Controls:_
- The `cp -r` operation at startup is bounded by the size of the global layer directory. For
  a well-maintained operator config (tens of files, kilobytes of content), this is
  sub-millisecond.
- Claude Code's context window cost is bounded by the total size of injected Markdown files.
  A 200-line `CLAUDE.md` and five skills of similar size costs roughly 8,000–10,000 tokens —
  significant but acceptable. Operators should keep the global layer lean.

### 5.3 Updated STRIDE coverage map

| Threat (STRIDE) | Controls — pre-existing | Controls — added by this design |
|---|---|---|
| **Spoofing (S)** | Pin dependency versions | Version-controlled global layer; operator-authored only |
| **Tampering (T)** | Container filesystem scope + `permissions.deny` | Readonly mounts at `/run/`; `Write(/run/*)` deny rule |
| **Repudiation (R)** | Docker + Squid + Claude logs | Entrypoint stdout logs; git history of `global-claude/` |
| **Information Disclosure (I)** | Network allowlist; secrets not mounted | Global layer contains no secrets by design |
| **Denial of Service (D)** | `--memory` and `--cpus` limits | Global layer size discipline |
| **Elevation of Privilege (E)** | Non-root user; `--cap-drop=ALL`; `--no-new-privileges` | Entrypoint runs as `claude-agent`; no sudo in script |

---

## 6. Directory Layout After This Change

The complete `~/.claude-sandbox/` tree after this design is implemented:

```
~/.claude-sandbox/
├── build.sh
├── start.sh                     ← modified
├── global-claude/               ← new
│   ├── CLAUDE.md
│   ├── skills/
│   │   └── <skill-name>/
│   │       └── SKILL.md
│   └── commands/
│       └── <command>.md
├── global-crypto/               ← new (optional; created when needed)
│   └── skills/
│       └── pkcs11-patterns/
│           └── SKILL.md
├── global-systems/              ← new (optional)
│   └── skills/
│       └── cmake-patterns/
│           └── SKILL.md
├── global-research/             ← new (optional)
│   └── skills/
│       └── latex-workflow/
│           └── SKILL.md
├── base/
│   ├── Dockerfile               ← modified
│   └── entrypoint.sh            ← new
├── crypto/
│   └── Dockerfile
├── systems/
│   └── Dockerfile
├── research/
│   └── Dockerfile
├── squid/
│   ├── Dockerfile
│   └── squid.conf
└── docs/
    ├── AGENTS.md
    ├── claude_code_security_plan.md
    ├── security_plan_changelog.md
    ├── squid_proxy_guide.md
    ├── global_layer_injection_sdd.md   ← this document
    └── global_layer_injection_impl.md  ← companion implementation guide
```

---

## 7. Interface Contract

This section defines the stable interfaces that the implementation must satisfy. Changes that
break these contracts require a revision to this document.

### 7.1 Mount points (container-internal)

| Path | Type | Source | Writable |
|---|---|---|---|
| `/run/claude-global` | bind | `~/.claude-sandbox/global-claude/` | No |
| `/run/claude-overlay` | bind | `~/.claude-sandbox/global-<image>/` | No |
| `/home/claude-agent/.claude` | directory | Created by entrypoint | Yes |
| `/workspace` | bind | Project directory | Yes |

### 7.2 Entrypoint contract

- Must be located at `/usr/local/bin/entrypoint.sh` in the image.
- Must be executable by `claude-agent`.
- Must exit non-zero only on unrecoverable errors (not on missing optional mounts).
- Must `exec "$@"` as the final action, passing control to `CMD` with no subprocess overhead.
- Must log all merge actions to stdout.
- Must not write to `/run/claude-global/` or `/run/claude-overlay/`.
- Must not require root.

### 7.3 `start.sh` contract

- Existing positional arguments (`project_dir`, `image`) are unchanged.
- Global layer injection is automatic and requires no new arguments.
- If `global-claude/` does not exist, `start.sh` emits a warning and proceeds without the base
  mount. The session is not aborted.
- If `global-<image>/` does not exist, no overlay mount is passed. No warning is emitted
  (absence of an overlay is the normal state for images that have not yet had one authored).

---

## 8. Open Questions and Non-Decisions

**Q: Should `global-claude/` be a git submodule rather than a subdirectory of the sandbox
repo?**

Not decided. A submodule would allow the global layer to be shared across multiple sandbox
installations (e.g. a work machine and a personal machine) with independent version histories.
The implementation guide treats it as a plain subdirectory. Promotion to a submodule is a
future option.

**Q: Should the entrypoint verify a checksum of the global layer before injecting it?**

Not in scope for this design. Checksum verification would add a Tamper protection control at the
cost of additional infrastructure (a signing key, a verification step). The readonly mount
already prevents in-flight tampering. The git history provides integrity assurance for the source.
This is a reasonable future hardening for high-assurance environments.

**Q: Should auto-memory from a session be persisted back to the host?**

Explicitly no. Each session starts from the operator-curated baseline. Auto-memory accumulated
during a session is ephemeral by design. Persisting it back would require a writable mount to the
host, which reintroduces the write-back surface this design deliberately avoids. If a session
produces insights worth preserving, the operator reviews them and manually adds them to
`global-claude/CLAUDE.md`.

---

## Changelog

### Version 1.0 — 2026-05-20
Initial design document. Covers Strategy 3 (entrypoint-based copy injection) and its natural
evolution to Strategy 4 (per-image overlay). Derived from the design discussion between the
operator and Claude Sonnet 4.6.
