# Podman Migration — Software Design Document
## Docker → Rootless Podman/WSL2 Engine Swap

| Field | Value |
|---|---|
| **Document Type** | Software Design Document (SDD) |
| **Status** | Draft |
| **Version** | 1.0 |
| **Date** | 2026-08-07 |
| **Author** | Fernando |
| **Reviewers** | Security Team |
| **Supersedes** | — |
| **Relates to** | `docs/claude_code_security_plan.md`, `docs/designs/squid-proxy-integration.md`, `docs/designs/claude-sandbox-testing-module-sdd.md`, `ARCHITECTURE.md`, `BUILDING.md`, `tests/lib/engine.bash` |

---

## Revision History

| Version | Date | Author | Description |
|---|---|---|---|
| 1.0 | 2026-08-07 | Fernando | Initial draft. Scope and three governing decisions agreed with the operator prior to drafting (see §3). |

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [Context](#2-context)
3. [Governing Decisions](#3-governing-decisions)
4. [Architecture Overview](#4-architecture-overview)
5. [Component Design](#5-component-design)
6. [Threat Model](#6-threat-model)
7. [Interface Contract](#7-interface-contract)
8. [Implementation Plan](#8-implementation-plan)
9. [Open Questions and Non-Decisions](#9-open-questions-and-non-decisions)

---

## 1. Purpose and Scope

This document specifies the migration of `claude-sandbox`'s container engine from
rootless Docker to rootless Podman under WSL2. It is a toolchain substitution, not a
redesign: every security property currently claimed for the sandbox — non-root
execution, capability dropping, network allowlisting, readonly global-layer mounts —
must hold after the swap, verified against the regression baseline established by
`tests/lib/engine.bash`'s `$ENGINE` abstraction (`claude-sandbox-testing-module-sdd.md`
§3.4).

This is the second of three pre-merge tasks named in the testing SDD's own
introduction ("testing → Podman migration → config evaluation"), and it is the
document the Squid SDD explicitly forward-referenced when it deferred validation of
the sibling-container proxy pattern under `slirp4netns` (`squid-proxy-integration.md`
§7.4): *"Does not validate behavior under rootless Podman/`slirp4netns` — explicitly
deferred to the Podman migration SDD."*

In scope:
- Generalizing `build.sh` and `start.sh` to route through `$ENGINE`.
- Rootless Podman under WSL2 as the target runtime.
- Validating the Squid sibling-container pattern under `slirp4netns` (or `pasta`, if
  `slirp4netns` proves unfit).
- Runtime UID-matching via `--userns=keep-id` instead of a build-time `HOST_UID`
  re-declaration in every child Dockerfile, for the Podman path.
- Closing the previously-deferred `--log-driver`/`--log-opt` gap on the main session
  container, and adding it to the proxy container, since `start.sh`'s run invocations
  are being rewritten regardless.
- Pinning the digest of `base/Dockerfile`'s `FROM debian:bookworm-slim` — a gap
  explicitly deferred to this migration by the Squid SDD (§5.1: *"the existing
  repo-wide digest-pinning gap … deferred to the Podman migration where every `FROM`
  line across the hierarchy is being resolved anyway"*).

Explicitly out of scope:
- Splitting `squid.conf` per profile (deferred per `squid-proxy-integration.md` §3/§9;
  not reopened here — see §3.C below).
- Retiring the Docker fallback path entirely. Docker stays functional via
  `ENGINE=docker` until a separate, later decision removes it.
- A "containers" profile for nested container execution inside the sandbox — a
  separate, already-analyzed and rejected question, unrelated to swapping which host
  engine `build.sh`/`start.sh` shell out to.
- CI/CD integration — out of scope for the whole project per
  `docs/claude_code_security_plan.md`.

---

## 2. Context

`claude-sandbox` currently targets rootless Docker on a single-user local workstation
(`docs/claude_code_security_plan.md`, Scope). Only one file in the repository routes
through an engine abstraction today — `tests/lib/engine.bash`, added by the testing
SDD specifically so `ENGINE=podman bats tests/` would validate a future migration
without rewriting test logic. `build.sh` and `start.sh` still call `docker` literally
throughout; generalizing them is net-new work, not a rename.

Two already-accepted, merged documents anticipate this migration directly:

- **`claude-sandbox-testing-module-sdd.md`** is subtitled *"Docker Baseline,
  Pre-Podman-Migration"* and states its own non-goal: *"Implementation of the Podman
  migration itself"* (§1.2) — reserved for this document.
- **`squid-proxy-integration.md`** ships a working sibling-container pattern (the
  `claude-proxy-$$` proxy container on `claude-net`, addressed by name, receiving
  `CONNECT` tunnels from the main session container) that has only ever been exercised
  under Docker's bridge network. Its own §7.4 flags this pattern as **unvalidated**,
  not merely unmigrated, under `slirp4netns`.

The primary motivation is eliminating the root daemon attack surface: `dockerd` runs
as root on the host even in "rootless" Docker's typical desktop configuration, whereas
Podman is daemonless — each `podman run` is a plain fork/exec from the CLI. This
layers with, not replaces, the sandbox's existing non-root `claude-agent` control.

---

## 3. Governing Decisions

Agreed with the operator prior to drafting.

### A. `--userns=keep-id` at runtime, scoped to the Podman path only

Today, every non-squid Dockerfile declares `ARG HOST_UID=1000` and creates
`claude-agent` with `-u $HOST_UID`, and `build.sh` passes
`--build-arg HOST_UID=$(id -u)` at build time so bind-mounted `/workspace` files are
accessible without a runtime `chown`. `ARG` values do not inherit across `FROM`, so
this is re-declared in `crypto/Dockerfile`, `systems/Dockerfile`, and
`research/Dockerfile` independently — a known, already-shipped hazard (silent
misconfiguration if a future child Dockerfile omits it).

Podman's `--userns=keep-id:uid=<N>,gid=<N>` remaps a *fixed* in-container UID to
whatever UID is actually invoking `podman` on the host, at run time, without
touching the image. This lets the Podman path use the Dockerfiles' existing default
(`HOST_UID=1000`, i.e. `claude-agent` always built as UID 1000) unconditionally, with
no `--build-arg` passed at all — `start.sh` maps that fixed UID 1000 onto the real
host user at container-start time instead.

**Decision:** the Podman path drops `--build-arg HOST_UID` entirely and adds
`--userns=keep-id:uid=1000,gid=1000` to the main session container's `run` invocation
only (the proxy container has no bind mounts and needs no UID matching, per
`build.sh`'s existing `build_squid` comment). The **Docker fallback path is
unchanged** — it keeps the build-time `HOST_UID` mechanism exactly as it works today,
`ARG` re-declaration hazard and all.

This is a deliberate, scoped trade-off, not a full fix: the re-declaration hazard is
not eliminated project-wide by this migration, only bypassed for the Podman path.
Removing `ARG HOST_UID` from the Dockerfiles outright is deferred until the Docker
fallback is retired (§9) — doing it now would mean maintaining two divergent
UID-handling code paths mid-migration for no benefit.

### B. Fold in the main-container `--log-driver`/`--log-opt` gap

The Squid SDD flagged, and deliberately did not fix (§6.2-R, §9), that `start.sh`'s
main session container `run` invocation lacks `--log-driver`/`--log-opt` despite
`docs/claude_code_security_plan.md` Phase 5 documenting this as standard practice. It
also recommended, but did not implement, `--log-opt max-size=10m --log-opt max-file=3`
for the proxy container specifically.

**Decision:** since `start.sh`'s `run` invocations are being fully rewritten for the
engine swap anyway, both gaps close in this pass, with an explicit driver pinned for
**both engines** rather than relying on differing per-engine defaults (Podman's
default varies by configuration — `journald` is common but not guaranteed available
under a minimal WSL2 systemd setup):

- Main session container: `--log-driver json-file --log-opt max-size=50m --log-opt max-file=5`
  (the exact values already documented in `claude_code_security_plan.md` Phase 5).
- Proxy container: `--log-driver json-file --log-opt max-size=10m --log-opt max-file=3`
  (the exact values already recommended in `squid-proxy-integration.md` §6.2-R).

### C. `squid.conf` scope stays out of this migration

Per-profile `squid.conf` splitting remains deferred per the existing decision in
`squid-proxy-integration.md` §3/§9. Not reopened here. `squid/squid.conf` is not
modified by this document.

---

## 4. Architecture Overview

### 4.1 Current architecture

```
build.sh  ──docker build──▶  claude-base, claude-crypto, claude-systems,
                              claude-research, claude-squid

start.sh  ──docker run──▶   claude-proxy-$$ (Squid, sibling container)
          ──docker run──▶   claude-<project>-<ts> (main session container)
                              on claude-net bridge network, HTTP(S)_PROXY → proxy

tests/lib/engine.bash  ──$ENGINE (default docker)──▶  engine_run/build/ps/...
```

Only `tests/lib/engine.bash` has engine indirection. `HOST_UID` is baked into every
non-squid image at build time. Container-to-container reachability (`claude-net`,
Docker's embedded DNS resolving `claude-proxy-$$` by name) has never been exercised
under anything but Docker's native bridge networking.

### 4.2 Target architecture

```
build.sh  ──$ENGINE build──▶  same five images
                                UID_ARG passed only when $ENGINE = docker

start.sh  ──$ENGINE run──▶   claude-proxy-$$
                                + --log-driver json-file --log-opt max-size=10m --log-opt max-file=3
          ──$ENGINE run──▶   claude-<project>-<ts>
                                + --log-driver json-file --log-opt max-size=50m --log-opt max-file=5
                                + --userns=keep-id:uid=1000,gid=1000   (podman only)
                                on claude-net, via slirp4netns (or pasta — §8 step 7)

tests/lib/engine.bash  ──$ENGINE (docker or podman)──▶  unchanged, already engine-agnostic
```

`$ENGINE` becomes a single environment variable with one meaning, reused identically
across `build.sh`, `start.sh`, and the existing test harness. Default remains `docker`
until §8 step 11 flips it, after the full regression gate is green.

### 4.3 What does not change

- `squid/squid.conf` — untouched (§3.C).
- `crypto/Dockerfile`, `systems/Dockerfile`, `research/Dockerfile` — no `FROM`
  changes; they inherit from local `claude-base`, not an external registry image, so
  digest pinning does not apply to them.
- `squid/Dockerfile` — already digest-pinned (`FROM debian:bookworm-slim@sha256:...`);
  no change.
- The fail-closed proxy-startup decision (`squid-proxy-integration.md` §6.3) and the
  `trap cleanup EXIT` teardown pattern — both engine-agnostic, unchanged.
- The positional interface `start.sh <project_dir> [image]` — unchanged.

---

## 5. Component Design

### 5.1 `build.sh`

```bash
ENGINE="${ENGINE:-docker}"

UID_ARG=""
if [ "$ENGINE" = "docker" ]; then
    UID_ARG="--build-arg HOST_UID=$(id -u)"
fi
```

Every `docker build` / `docker images` call becomes `"$ENGINE" build` /
`"$ENGINE" images`. `build_squid` is unaffected — it already omits `UID_ARG`. Target
dispatch (`all|base|crypto|systems|research|squid`), the base-before-children
enforcement, and `--no-cache` handling are unchanged.

### 5.2 `start.sh`

```bash
ENGINE="${ENGINE:-docker}"

USERNS_ARGS=()
if [ "$ENGINE" = "podman" ]; then
    USERNS_ARGS=(--userns=keep-id:uid=1000,gid=1000)
fi

PROXY_LOG_ARGS=(--log-driver json-file --log-opt max-size=10m --log-opt max-file=3)
MAIN_LOG_ARGS=(--log-driver json-file --log-opt max-size=50m --log-opt max-file=5)
```

- Preflight checks (`docker info`, `docker image inspect`, `docker network inspect`)
  become `"$ENGINE" ...`; error text becomes engine-generic ("Error: `$ENGINE` is not
  reachable.").
- Cleanup trap (`docker ps -a` / `docker stop` / `docker rm`) becomes `"$ENGINE" ...`,
  unchanged in logic.
- Proxy `run`: adds `"${PROXY_LOG_ARGS[@]}"`. Does **not** get `USERNS_ARGS` — no bind
  mounts, no UID-matching need (matches `build_squid`'s existing rationale).
- Main session `run`: adds `"${MAIN_LOG_ARGS[@]}"` and `"${USERNS_ARGS[@]}"`.
- Fail-closed behavior on proxy startup failure (`squid-proxy-integration.md` §6.3) is
  unchanged — still aborts before starting the main container.

### 5.3 `base/Dockerfile`

Single-line change: pin the digest.

```dockerfile
FROM debian:bookworm-slim@sha256:<resolved-at-implementation-time>
```

Resolved fresh via `skopeo inspect docker://debian:bookworm-slim` or
`docker inspect --format='{{index .RepoDigests 0}}' debian:bookworm-slim` at
implementation time (§8 step 4) — not fabricated in this document, mirroring how
`squid/Dockerfile`'s existing pin was resolved. `ARG HOST_UID=1000` and the
`useradd -u $HOST_UID` line are **not** touched (§3.A).

### 5.4 `crypto/Dockerfile`, `systems/Dockerfile`, `research/Dockerfile`

No changes. `FROM claude-base` is a local image reference, not an external registry
pull — digest pinning does not apply. `ARG HOST_UID=1000` re-declarations are left as
they are, for the reason given in §3.A.

### 5.5 `squid/Dockerfile`, `squid/squid.conf`

No changes. Already digest-pinned; `squid.conf` is explicitly out of scope (§3.C).

### 5.6 `tests/lib/engine.bash`

No changes — this is the file the rest of the migration is built to reuse without
modification, per its own design rationale (§3.4 of the testing SDD).

---

## 6. Threat Model

### 6.1 New surfaces

| Surface | Description |
|---|---|
| Podman CLI/runtime | Daemonless; each invocation is a direct fork/exec, replacing a root-owned long-lived `dockerd` |
| `slirp4netns` (or `pasta`, §8 step 7) | User-mode networking backend for rootless container-to-container traffic, replacing Docker's bridge+iptables |
| `--userns=keep-id:uid=1000,gid=1000` | Runtime UID remapping, replacing build-time `HOST_UID` baking, Podman path only |
| subuid/subgid delegation | Host-level prerequisite range enabling the user-namespace remap above |
| cgroups v2 delegation | Host-level prerequisite for `--memory`/`--cpus` enforcement under rootless Podman |
| Explicit `--log-driver`/`--log-opt` on both containers | New, engine-agnostic — closes a previously-flagged gap (§3.B) |

### 6.2 STRIDE analysis

**Spoofing (S).** Container-name resolution for `claude-proxy-$$` under
`slirp4netns` is the highest-risk unvalidated item carried over from the Squid SDD.
`slirp4netns`'s built-in resolver has documented DNS quirks under rootless
configurations that Docker's embedded DNS does not share. This must be confirmed by
re-running `test_squid_isolation.bats` (S-1/S-2/S-3) against `ENGINE=podman` (§8 step
6) before it is trusted — not assumed safe because the sibling-container pattern
"looks the same." The residual, pre-existing point that `claude-net` is a flat
network with no additional segmentation (`squid-proxy-integration.md` §6.2-S) is
unchanged by this migration.

**Tampering (T).** Unchanged in kind. `squid.conf` remains baked into the image at
build time (§3.C); no new bind-mount or write path is introduced by the engine swap.

**Repudiation (R).** Net improvement (§3.B): both containers now carry explicit,
size-capped log drivers, closing the previously-flagged main-container gap
(`claude_code_security_plan.md` Phase 5 vs. reality) and the previously-recommended
proxy hygiene addition (`squid-proxy-integration.md` §6.2-R) in the same pass, pinned
to `json-file` on both engines to avoid depending on Podman's less predictable default.
Open question: rootless Podman's `json-file` log storage path/permissions under WSL2
need implementation-time confirmation, not assumption, consistent with this project's
established "confirmed empirically" standard.

**Information Disclosure (I).** Unchanged in kind — the allowlist mechanism itself
(`HTTP_PROXY`/`HTTPS_PROXY` env injection into the main container, Squid's
`dstdomain` ACLs) does not change with the engine. The open question the operator
raised — whether `slirp4netns`/`pasta` introduces any new DNS-spoofing or
container-to-container trust assumption Docker's bridge network didn't have — is not
resolved by inspection; it is resolved empirically by the same S-1/S-2/S-3 gate as
the Spoofing item above, since both share the same underlying networking-backend
change.

**Denial of Service (D).** Two items, both new:

1. **cgroups v2 delegation.** `--memory="2g"` and `--cpus="2"` on the main container
   currently work under Docker. Under rootless Podman, enforcement requires cgroups
   v2 with a delegated systemd user session — not guaranteed by default on WSL2,
   which gained systemd support relatively recently and requires explicit enablement.
   If delegation is absent, these flags silently become no-ops — a regression from
   currently-working behavior. Must be confirmed by deliberately exceeding
   `--memory` inside a session container and observing an OOM-kill (§8 step 8), not
   assumed to carry over.
2. The fail-closed proxy-startup decision (`squid-proxy-integration.md` §6.3) is
   unchanged — still the primary DoS trade-off for proxy unavailability, engine-agnostic.

**Elevation of Privilege (E).** Rootless Podman's in-container "root" (or, here,
`claude-agent`) is structurally an unprivileged host user by construction — similar in
effect to what UID-matching already gave the current Docker setup
(`claude_code_security_plan.md` Change 7), but achieved as a property of the engine
itself rather than a specific build-time choice. This changes what
`--cap-drop=ALL`/`--security-opt=no-new-privileges` are actually buying: they no
longer contribute to preventing a *host* root escape (rootless already prevents that
structurally, independent of these flags), but they remain meaningful **within** the
container's own namespace — restricting what a compromised `claude-agent` process can
do to other processes and resources inside its own confined view (e.g. capability
gain, `ptrace` of container-local processes). The controls are additive, not made
redundant, and both flags are retained unchanged on both containers under both
engines. The daemonless model closes the separate, larger gap this migration was
motivated by: no root-owned `dockerd` process on the host to attack in the first
place.

### 6.3 Decision record: log driver pinned explicitly on both engines

Rejected: relying on each engine's own default log driver. Podman's default varies by
distribution/configuration (`journald` is common but requires systemd-journald access
that a minimal WSL2 rootless setup may not reliably grant); Docker's default
(`json-file`, unbounded) is what created the original gap this design closes.
Pinning `json-file` with explicit size caps on both engines (§3.B) gives one
consistent, predictable behavior regardless of `$ENGINE`, rather than a
per-engine conditional whose divergence would need to be re-verified every time the
default engine changes.

---

## 7. Interface Contract

### 7.1 `build.sh` contract

- `ENGINE` env var, default `docker`. `ENGINE=podman ./build.sh ...` routes every
  build through `podman build`.
- `--build-arg HOST_UID=$(id -u)` is passed only when `$ENGINE = docker` (§3.A/§5.1).
- Target dispatch, base-before-children enforcement, and `--no-cache` handling are
  unchanged for both engines.

### 7.2 `start.sh` contract

- `ENGINE` env var, default `docker`, same variable and semantics as `build.sh` and
  `tests/lib/engine.bash` — one name, one meaning, everywhere in the project.
- `--userns=keep-id:uid=1000,gid=1000` is added to the main session container only,
  only when `$ENGINE = podman` (§3.A/§5.2).
- `--log-driver json-file --log-opt max-size=... --log-opt max-file=...` is added to
  **both** containers, **unconditionally**, regardless of engine (§3.B/§5.2).
- Fail-closed proxy-startup behavior, `trap cleanup EXIT` teardown, and the positional
  interface (`start.sh <project_dir> [image]`) are unchanged.

### 7.3 Test harness contract

- `ENGINE=podman bats tests/` (full suite, not just the fast tier) must pass in full
  before `podman` becomes the default in `build.sh`/`start.sh` (§8 step 11).
- No changes to `tests/lib/engine.bash` or any `.bats` file are required by this
  design — the abstraction was built in advance for exactly this migration.

### 7.4 What this design does not guarantee

- Does not change `squid.conf` or the allowlist (§3.C).
- Does not remove the Docker fallback path — `ENGINE=docker` remains fully functional
  indefinitely, until a separate future decision retires it.
- Does not eliminate the `ARG HOST_UID` re-declaration hazard for the Docker path
  (§3.A) — only bypasses it for Podman.
- Does not address nested/"containers-in-containers" execution — unrelated, separately
  analyzed and rejected question.
- Does not itself resolve the `slirp4netns` DNS-spoofing question raised in §6.2 — that
  is resolved empirically at §8 step 6, not by this document's analysis alone.

---

## 8. Implementation Plan

Each step maps to a single commit, per project convention, except where noted as
operator-executed (not a repo change).

1. **Document Podman prerequisites in `BUILDING.md`** — subuid/subgid delegation
   check (`grep "$(whoami)" /etc/subuid /etc/subgid`, or how to add ranges if absent),
   cgroups v2 requirement, and the WSL2 systemd-enablement note (`wsl.conf`
   `[boot] systemd=true`). Docs-only commit, no behavior change.
2. **Generalize `build.sh` to route through `$ENGINE`** (§5.1). Behavior-preserving
   under the still-default `ENGINE=docker`. Regression gate: `bats tests/test_build.bats`
   (`ENGINE=docker`) unchanged.
3. **Generalize `start.sh` to route through `$ENGINE`**, add the log-driver/log-opt
   flags to both containers, add the conditional `--userns=keep-id` flag (§5.2).
   Regression gate: `bats tests/test_runtime_posture.bats tests/test_global_layer.bats`
   (`ENGINE=docker`) unchanged.
4. **Pin `base/Dockerfile`'s digest** (§5.3) — resolve the current
   `debian:bookworm-slim` digest at this step, not before. Single-file atomic commit.
5. **Install and configure rootless Podman on the WSL2 host** per step 1's documented
   prerequisites. Operator-executed; not a repo commit.
6. **Run the full regression gate against Podman**: `ENGINE=podman bats tests/` (all
   tiers, not just fast). This is the validation gate for the Squid
   sibling-container/`slirp4netns` pattern (S-1/S-2/S-3, §6.2-S/§6.2-I) and for the new
   `--userns=keep-id` and log-driver behavior (B-*, R-* posture tests). Any failure is
   a finding to fix, not silently patched around.
7. **If `slirp4netns` fails step 6's gate**, evaluate `pasta` as the network backend
   (`containers.conf` `network_cmd_options`, or per-run `--network` value) and re-run
   step 6 against it before proceeding. Explicit decision point — not pre-committed in
   this document.
8. **Manual smoke test of cgroups v2 resource-limit enforcement** (§6.2-D) — exceed
   `--memory` inside a `podman`-run session container and confirm an OOM-kill, since
   no automated test in the current suite covers this and it is a newly-introduced
   risk with no Docker-path equivalent to regress against.
9. **Update `ARCHITECTURE.md`/`BUILDING.md`** to document `$ENGINE`, the Podman
   prerequisites now proven necessary by step 5/6, and (once flipped) the new default.
10. **Add a changelog entry to `docs/claude_code_security_plan.md`** documenting the
    engine swap and its STRIDE deltas (§6), following the established Change-N format
    — the same closing pattern used by the Squid SDD's own implementation plan.
11. **Flip the default `ENGINE` value** in `build.sh`/`start.sh` from `docker` to
    `podman`, only after steps 6 (and 7/8 if triggered) are fully green. Docker remains
    reachable via `ENGINE=docker` indefinitely, until a separate, later decision
    retires it — at which point `ARG HOST_UID` and its re-declaration hazard can
    finally be deleted outright (§9).

---

## 9. Open Questions and Non-Decisions

**Q: `slirp4netns` or `pasta`?**

Not decided here. Evidence-driven per §8 step 7 — default to `slirp4netns` first
(broadest existing documentation/precedent), fall back to `pasta` only if the
regression gate demonstrates a concrete failure, not preemptively.

**Q: Exact subuid/subgid range size needed on the WSL2 host?**

Not decided here — host-dependent, resolved empirically at §8 step 1/5, not
prescribed in this document.

**Q: Should the Docker fallback path be retired once Podman is default?**

Not decided here — explicitly deferred to a separate, later decision. This document's
scope is landing Podman as an option and eventually the default, not removing Docker.

**Q: Should `ARG HOST_UID` be removed from the Dockerfiles now, since Podman doesn't
need it?**

No — deferred until the Docker fallback (which still needs it) is retired (§3.A, §7.4).
Removing it now would break the Docker path this migration is explicitly keeping alive
as a fallback.

**Q: Does this reopen the "containers" nested-execution profile question?**

No. That is a separate, already-analyzed question (host-engine binary choice vs.
nesting an engine inside a session container) and is not affected by this migration.

**Q: Does this reopen per-profile `squid.conf` splitting?**

No — stays deferred per `squid-proxy-integration.md` §3/§9 (§3.C above).
