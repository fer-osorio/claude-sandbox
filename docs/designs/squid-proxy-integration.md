# Squid Proxy Integration — Software Design Document

> **Document type:** Software Design Document (SDD)
> **Status:** Accepted
> **Relates to:** `docs/claude_code_security_plan.md` (Phase 2.8–2.9, Phase 5 Audit Logging,
> STRIDE coverage map), `docs/squid_proxy_guide.md` (source guide this design implements and
> corrects), `ARCHITECTURE.md`, `docs/designs/docs-as-code-workflow.md` (Case E trigger),
> `docs/designs/claude-sandbox-testing-module-sdd.md` (Test Group 3, S-1–S-3 — currently unable
> to run; this design is the prerequisite)
> **Audience:** The engineer maintaining this sandbox — assumes familiarity with the image
> hierarchy, the entrypoint/global-layer mechanism, and the STRIDE framework used throughout
> this project's documentation.
> **Trigger:** Two gaps identified while investigating `test_squid_isolation.bats` setup
> failures: (1) `squid/Dockerfile` and `squid/squid.conf` are described in
> `docs/squid_proxy_guide.md` but were never committed to the repository; (2) the tracked
> `start.sh` contains no proxy lifecycle, no `HTTP_PROXY`/`HTTPS_PROXY` injection, and no
> reference to Squid at all — contradicting the guide's own claim that "the current `start.sh`
> already incorporates Squid." Layer 4 of the five-layer defense (network egress allowlisting)
> is currently a no-op against the tracked tree.

---

## 1. Purpose and Scope

This document designs the actual implementation of Squid-based network egress enforcement for
`claude-sandbox` — closing the gap between what `docs/squid_proxy_guide.md` describes and what
is committed and wired into `build.sh`/`start.sh`.

### 1.1 What currently exists vs. what is claimed

| Claimed by `squid_proxy_guide.md` | Actually true of the tracked tree |
|---|---|
| `squid/Dockerfile`, `squid/squid.conf` exist under `~/.claude-sandbox/squid/` | Neither file is tracked anywhere in the repo |
| "The Squid image is built by `build.sh` alongside the Claude Code images" | `build.sh` builds only `base`/`crypto`/`systems`/`research` |
| "The current `start.sh` already incorporates Squid" (Part 3, Step 4) | Tracked `start.sh` has no proxy container logic, no `HTTP_PROXY`/`HTTPS_PROXY` injection, and runs the target image with direct, unrestricted network access to `claude-net` |

The second row is the one worth sitting with: **this is not a documentation gap alone.** The
primary control against Information Disclosure via exfiltration — the one Phase 2.8–2.9 of the
security plan and the STRIDE coverage map both name as the mitigation for that threat — is not
deployed. Any session started from this repo today has outbound network access constrained only
by `permissions.deny`'s specific bash-command denials (`curl`, `wget`, `nc`, `ssh`, `scp`), which
does not cover in-language HTTP clients, `npm install` reaching an unexpected registry, or `git
clone` to an unexpected remote.

### 1.2 Scope of this document

This document covers:

- `squid/Dockerfile` and `squid/squid.conf`, committed and tracked
- Additions to `build.sh` to build the Squid image
- Additions to `start.sh` for proxy container lifecycle: startup, `HTTP_PROXY`/`HTTPS_PROXY`/
  `NO_PROXY` injection, and guaranteed teardown via `trap ... EXIT`
- The allowlist design: `dstdomain` as the primary mechanism, `dstdom_regex` as a narrowly
  scoped exception, and a curated reference-documentation tier
- Corrections to `docs/squid_proxy_guide.md` Part 3 Step 4 and Part 5 to match what is actually
  implemented
- Two hardening additions beyond the original guide: non-root execution inside the proxy
  container, and runtime hardening flags (`--cap-drop=ALL`, `--security-opt=no-new-privileges`)
  applied to the proxy container's own `docker run` invocation
- The fail-open vs. fail-closed decision for proxy startup failure

This document does **not** cover:

- TLS interception / `ssl_bump` (rejected — see §3, Design Principles)
- Per-profile `squid.conf` variants (explicitly deferred; single shared config for now)
- Validating the companion-container networking pattern under rootless Podman's `slirp4netns`
  (deferred to the Podman migration SDD; this design is the Docker-validated baseline it will
  migrate against)
- The config-file evaluation question (`docs/claude-sandbox-memory.md`, pre-merge task 3;
  explicitly deferred until after the Podman migration)
- Digest-pinning the base images of `base/crypto/systems/research` Dockerfiles (existing,
  separately tracked ADR-mandate gap; out of scope to expand here — see §5.1 for how this
  design treats *its own new* `FROM` line)

---

## 2. Context

### 2.1 Why this blocks other work, not just itself

`test_squid_isolation.bats` (Group 3, S-1–S-3) is already written against this exact design —
it builds `squid/Dockerfile`, runs it as a sibling container on `claude-net`, and asserts on the
access log. It currently fails at `setup_file()` with an explicit, named error rather than
skipping silently, per the testing SDD's own error-handling philosophy (§8: "a skipped security
test is indistinguishable from a passing one"). Group 3 is also the one test group most directly
relevant to validating the Podman migration's most uncertain change — the companion-container
networking pattern under `slirp4netns`. Migrating before this exists means migrating the
highest-risk-of-behavioral-change control with zero regression coverage for it.

### 2.2 CONNECT-tunnel visibility constrains the design space

Squid here does not perform TLS interception. For HTTPS, Squid sees only the `CONNECT
domain:port` request line — not the path, query string, or body. This rules out `url_regex`
entirely (it matches full URLs, which Squid never observes for HTTPS traffic under this design)
and means every policy decision in this document operates at **domain granularity only**. This
constraint, not stylistic preference, is why `dstdomain`/`dstdom_regex` are the only viable
mechanisms — see §3.

---

## 3. Design Principles

**`dstdomain` (exact-match) as the default and primary mechanism.** A flat list is scannable in
seconds during review; a page of regex requires mentally executing each pattern against edge
cases. The failure mode also differs in the direction that matters: a missing list entry fails
loudly (connection denied, add the domain), while an unanchored or overly broad regex fails
silently-permissive — the same class of bug as `squid_proxy_guide.md`'s own Change 2 (a syntax
error that silently dropped `--cap-drop=ALL`), just at the policy layer instead of the shell
layer.

**`dstdom_regex` reserved for individually-justified, anchored exceptions.** Not a parallel
default mechanism. Each use requires an inline comment stating what it covers and why a flat
list is insufficient (e.g., a package registry's rotating CDN-edge subdomain). Anchored
(`^...$`) without exception.

**Single shared `squid.conf`, not per-profile variants.** `claude-net` is already a single
shared network across all profiles; splitting the allowlist per profile now would require
teaching `start.sh` to select a config variant, which is exactly the kind of config-surface
decision `docs/claude-sandbox-memory.md`'s pre-merge task 3 defers until after the Podman
migration. Per-profile splitting is named here as a deliberate future option, not built
preemptively.

**Blind-tunnel exfiltration is an accepted, pre-existing limitation — not something this design
claims to solve.** Any domain on the allowlist is a potential blind exfiltration channel: Squid
restricts *destination*, not *content*, and cannot see inside a permitted HTTPS tunnel. This is
already true today for `api.anthropic.com`; it does not change in kind as the allowlist grows,
only in the number of viable channels. Documented explicitly in §6 rather than left implicit.

**Reference-tier curation: authoritative, low-user-generated-content sources only.** Official
project documentation, not Q&A/forum sites. Two independent reasons, not one: (a) a Q&A site is
a *larger* plausible-looking blind-exfil channel than an official docs domain, and (b) unmoderated
third-party text is prompt-injection surface — `docs/claude_code_security_plan.md` Phase 6
already flags exactly this risk category for any externally-sourced content a session reads.

**Unanticipated mid-session access needs are handled procedurally, not by loosening default
policy.** `squid_proxy_guide.md` Part 5 already documents the mechanism: edit `squid.conf`,
rebuild only the Squid image (`squid/` has no toolchain — a Debian+Squid rebuild is seconds), and
restart only the proxy. Formalized here as a named operational habit (§7.4), not solved by
widening the default allowlist under time pressure.

**TLS interception (`ssl_bump`) is explicitly rejected.** It would give path-level policy, but
at the cost of provisioning a MITM CA into every container — new key material to protect,
breakage for any tool doing certificate pinning, and a direct contradiction of this project's own
"physical absence over permission checks" and "no secrets on disk in the container" principles.
Scope explosion relative to the problem it solves.

**Proxy container lifecycle is ephemeral and 1:1 with the session, not a shared long-running
service.** Matches `squid_proxy_guide.md`'s own reference `start.sh` implementation (per-session
unique naming) and extends this project's existing "one project, one container, one session"
operational habit to the proxy. Considered alternative: a single long-running proxy shared across
concurrent sessions, which would reduce container-startup overhead slightly but adds a
lingering-container cleanup surface that per-session `trap`-based teardown avoids entirely, and
diverges from the guide's already-written reference implementation for no clear gain.

---

## 4. Architecture Overview

### 4.1 Current architecture (as tracked, corrected description)

```
HOST
├── build.sh          — builds base/crypto/systems/research only
├── start.sh           — runs the target image directly:
│                         no proxy, no HTTP_PROXY/HTTPS_PROXY, no egress restriction
└── (no squid/ directory exists)

CONTAINER (per session)
    --network claude-net    ← unrestricted egress to anything claude-net's
                               bridge can route to; permissions.deny is the
                               only active constraint, and it is narrow
                               (specific bash commands only)
```

### 4.2 Target architecture

```
HOST
├── build.sh                  ← modified: adds build_squid
├── start.sh                  ← modified: proxy lifecycle + trap EXIT
├── squid/                    ← new, tracked
│   ├── Dockerfile
│   └── squid.conf
├── base/ crypto/ systems/ research/   ← unchanged
└── docs/squid_proxy_guide.md ← corrected: Part 3 Step 4, Part 5

CONTAINER (per session)
    ┌────────────────────────────┐   ┌──────────────────────────────┐
    │  claude-<profile>          │   │  claude-proxy-$$              │
    │  (main session container)  │──▶│  (ephemeral, per-session)     │
    │  HTTP_PROXY=claude-proxy-$$:3128│  claude-net only               │
    │  HTTPS_PROXY=...            │   │  non-root, cap-dropped        │
    └────────────────────────────┘   │  dstdomain allowlist          │
              │                       │  access_log → stdout          │
              └── claude-net ─────────┘
                        │
                        ▼
                  THE INTERNET
                  ✓ core tier (Anthropic API, registries, GitHub)
                  ✓ reference tier (per-profile docs)
                  ✗ everything else
```

### 4.3 Data flow at session start

```
start.sh invoked
    │
    ├─ existing preflight checks (docker daemon, project dir, image tag, claude-net)
    ├─ NEW: check claude-squid image exists
    │        └─ missing → error, "Build it first with: ./build.sh squid", exit 1
    ├─ NEW: trap cleanup EXIT registered
    ├─ NEW: start proxy container (detached, unique name claude-proxy-$$)
    │        └─ fails to start → fail-closed (§6.3): abort, main container never starts
    ├─ start main session container
    │        --env HTTP_PROXY="http://claude-proxy-$$:3128"
    │        --env HTTPS_PROXY="http://claude-proxy-$$:3128"
    │        --env NO_PROXY="localhost,127.0.0.1"
    │        (existing mounts, --cap-drop=ALL, --security-opt=no-new-privileges unchanged)
    │
    ▼
session runs; all outbound HTTP/HTTPS from the main container is forced through the proxy
    │
    ▼
session ends (normal exit, error, or Ctrl+C)
    │
    └─ trap fires: stop + remove claude-proxy-$$ unconditionally
```

---

## 5. Component Design

### 5.1 `squid/Dockerfile`

Carries forward the guide's existing design (`debian:bookworm-slim`, matching the base image
family used everywhere else in this project; `-N` foreground flag required so Docker's PID 1
tracking works correctly) with two additions not present in the original guide:

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends squid \
    && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf

EXPOSE 3128

# Non-root execution (addition beyond the original guide — see SDD §6.4).
# Debian's squid package creates a service user for this purpose; confirm the
# exact name (expected: "proxy") via `id proxy` inside a built image before
# finalizing — do not assume without checking against the actual package.
USER proxy

CMD ["squid", "-N", "-f", "/etc/squid/squid.conf"]
```

**Digest pinning.** This is a *new* file, not an edit to an existing one, so the existing
repo-wide digest-pinning gap (tracked separately, deferred to the Podman migration where every
`FROM` line is already being touched) does not automatically extend to it by inertia. Recommend
pinning `FROM debian:bookworm-slim@sha256:<digest>` from the start — resolve the current digest
at implementation time (`docker pull debian:bookworm-slim && docker inspect --format='{{index
.RepoDigests 0}}' debian:bookworm-slim`) rather than carrying a fabricated or stale value into
this document. Not extending this to `base/crypto/systems/research`'s existing `FROM` lines —
that remains explicitly out of scope per §1.2.

### 5.2 `squid/squid.conf`

```
# ─── squid.conf ──────────────────────────────────────────────────────
# Default-deny outbound policy. dstdomain (exact match) is the primary
# mechanism; dstdom_regex is used only for the individually-justified
# exception below, anchored, with its own comment.
# ─────────────────────────────────────────────────────────────────────

http_port 3128

# ── Core tier — required for basic toolchain operation ────────────────
acl allowed_domains dstdomain api.anthropic.com
acl allowed_domains dstdomain registry.npmjs.org
acl allowed_domains dstdomain pypi.org
acl allowed_domains dstdomain files.pythonhosted.org
acl allowed_domains dstdomain github.com
acl allowed_domains dstdomain api.github.com
acl allowed_domains dstdomain codeload.github.com
acl allowed_domains dstdomain raw.githubusercontent.com

# ── Reference tier — authoritative, low-UGC documentation only ────────
# Curated per SDD §3. Stack Overflow and similar UGC sites are
# deliberately excluded — see squid-proxy-integration.md §3.
acl allowed_domains dstdomain docs.python.org
acl allowed_domains dstdomain nodejs.org
acl allowed_domains dstdomain developer.mozilla.org

# systems profile
acl allowed_domains dstdomain en.cppreference.com
acl allowed_domains dstdomain cmake.org

# crypto profile
acl allowed_domains dstdomain www.openssl.org

# research profile
acl allowed_domains dstdomain ctan.org
acl allowed_domains dstdomain tug.org

# ── dstdom_regex exceptions (none at initial implementation) ──────────
# Reserved for individually-justified, anchored patterns only — e.g. a
# registry's rotating CDN-edge subdomain that a flat list can't track.
# Example (commented, not active):
# acl allowed_domains dstdom_regex ^[a-z0-9-]+\.pkg-cdn\.example\.com$

# ── Access policy ───────────────────────────────────────────────────
acl CONNECT method CONNECT
http_access allow CONNECT allowed_domains
http_access allow allowed_domains
http_access deny all

# ── Logging ─────────────────────────────────────────────────────────
access_log stdio:/dev/stdout combined

# ── Privacy and cache ───────────────────────────────────────────────
cache deny all
forwarded_for off
via off
```

Single shared file for all profiles, per §3 — a `systems` session and a `research` session both
get the full reference tier rather than a profile-scoped subset. This is a deliberate simplicity
trade-off (§3); profile-scoping is future work if the shared list proves too broad in practice.

### 5.3 `build.sh` additions

```bash
build_squid() {
    echo "→ Building claude-squid..."
    docker build $NO_CACHE -t claude-squid ./squid/
}
```

Deliberately **no `$UID_ARG`** — unlike `base`/`crypto`/`systems`/`research`, the Squid image
creates no `claude-agent`-equivalent user tied to the host UID; it has no bind-mounted
`/workspace` and nothing that needs host-UID alignment. This is a documented omission, not an
oversight, to preempt the "why doesn't this build call match the others" question later.

Add to the `case "$TARGET"` dispatch:

```bash
    squid)
        build_squid
        ;;
```

And add `build_squid` to the `all` target alongside the four existing builds.

### 5.4 `start.sh` modifications

```bash
# Preflight: Squid image must exist (fail-closed if missing, matching the
# existing pattern for base/crypto/systems/research image checks)
if ! docker image inspect claude-squid > /dev/null 2>&1; then
    echo "Error: image 'claude-squid' does not exist."
    echo "Build it first with: ./build.sh squid"
    exit 1
fi

PROXY_NAME="claude-proxy-$$"

# Guaranteed teardown regardless of how the script exits (normal completion,
# main-container failure, or Ctrl+C) — a plain "stop after" line only runs
# on the clean-exit path and would leak the proxy container otherwise.
cleanup() {
    local exit_code=$?
    if docker ps -a --format '{{.Names}}' | grep -qx "$PROXY_NAME"; then
        docker stop "$PROXY_NAME" > /dev/null 2>&1 || true
        docker rm "$PROXY_NAME" > /dev/null 2>&1 || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT

echo "Starting Squid proxy ($PROXY_NAME)..."
if ! docker run -d \
    --name "$PROXY_NAME" \
    --network claude-net \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    claude-squid > /dev/null; then
    echo "Error: Squid proxy failed to start."
    echo "Fail-closed per squid-proxy-integration.md SDD §6.3 — aborting session."
    exit 1
fi
```

The existing `docker run` for the main container gains three env vars, no other changes:

```bash
    --env HTTP_PROXY="http://$PROXY_NAME:3128" \
    --env HTTPS_PROXY="http://$PROXY_NAME:3128" \
    --env NO_PROXY="localhost,127.0.0.1" \
```

`--cap-drop=ALL`/`--security-opt=no-new-privileges` on the proxy container's own invocation are
an addition beyond the original guide — see §6.4.

### 5.5 `docs/squid_proxy_guide.md` corrections

- Part 3, Step 4: replace the stale reference `start.sh` sample (which also predates the
  global-layer-injection mount logic, a second, independent staleness) with a pointer to the
  actual tracked `start.sh`.
- Part 5, Maintenance: "restart the proxy container" no longer applies as a manual step — the
  proxy is created fresh per session (§3), so a `squid.conf` edit + image rebuild is picked up
  automatically by the *next* `start.sh` invocation. Simplifies the documented procedure.

---

## 6. Threat Model

### 6.1 New surfaces

| Surface | Description |
|---|---|
| `squid/Dockerfile`, `squid/squid.conf` (host, tracked) | Baked into the image at build time; not runtime-injected |
| `claude-squid` image | Built by `build.sh squid` |
| Proxy container (ephemeral, per-session) | Runs on `claude-net`, non-root, cap-dropped |
| `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` env vars | Injected into the main container only |
| Squid access log | stdout → Docker's default `json-file` driver |

### 6.2 STRIDE analysis

**Spoofing (S).** Docker's internal DNS resolves `claude-proxy-$$` uniquely per session (shell
PID); concurrent sessions have distinct names by construction. Residual, pre-existing structural
point (not introduced by this design): `claude-net` is a flat bridge network with no additional
segmentation, so any container on it can in principle address any other container on it by name
or IP. This predates this design — worth noting for completeness, not a new gap.

**Tampering (T).** `squid.conf` is baked into the image at build time, not mounted at runtime —
the main session container has no path to modify it, since the host `squid/` directory is never
bind-mounted into any session container. A compromised session has no `docker` socket access and
cannot exec into or otherwise modify the proxy container.

**Repudiation (R).** Primary positive contribution of this design as a whole. `access_log
stdio:/dev/stdout combined` is captured by Docker's default `json-file` log driver (proxy
container is not currently given explicit `--log-opt` size caps in this design — Docker's
default has no size limit; adding `--log-opt max-size=10m --log-opt max-file=3` is a cheap
hygiene addition worth including at implementation time, though it is not filling a functional
gap — logs are captured either way). Note, found in passing: the tracked `start.sh` does not
currently pass `--log-driver json-file --log-opt ...` to the *main* session container either,
despite `docs/claude_code_security_plan.md` Phase 5 documenting this as standard practice. This
is a separate, pre-existing gap, orthogonal to Squid — flagged here per the same "no silent
scope expansion" principle the original issue report itself applied, not fixed as part of this
change.

**Information Disclosure (I).** This is the gap this design closes: default-deny egress,
allowlist-only reachability. Residual, explicitly accepted (§3): any allowlisted domain is a
potential blind exfiltration channel, since CONNECT-tunnel proxying gives Squid no visibility
into tunnel contents. This scales with allowlist size — a incremental, not qualitative, change
introduced by adding the reference tier.

**Denial of Service (D).** See §6.3 — the fail-open/fail-closed decision is the primary DoS
trade-off in this design.

**Elevation of Privilege (E).** See §6.4 — non-root execution inside the proxy container is a
hardening addition beyond the original guide.

### 6.3 Decision record: fail-open vs. fail-closed

Two options for proxy-container-fails-to-start:

- **Fail-open:** proceed without the proxy; main container starts with unrestricted network
  access.
- **Fail-closed:** abort; main container never starts.

**Decision: fail-closed** (implemented in §5.4 above; signed off by the operator 2026-08-03 —
see Changelog).

Rationale: fail-open would silently recreate the exact gap this design exists to close — and
arguably worse than today's state, since once this SDD ships, the operator has reasonable cause
to believe egress protection is active. A security control that silently degrades to absent on
its own failure is the anti-pattern this project has consistently avoided elsewhere (e.g., the
Squid guide's own Change 2 regression is precisely a case of a control silently failing to
apply). The availability cost is real but bounded: `claude-squid` is a small, dependency-light
image (Debian + Squid, no toolchain), so build failures should be rare and fast to diagnose and
fix — unlike, say, a broken `claude-systems` build blocking one profile, a broken proxy build
blocks all sessions, which is a meaningful but not disproportionate cost given what it protects.

This differs from the warn-only precedent set in `interpreter-presence-health-check.md` and
`workspace-artifact-staleness.md` — those checks address environment-correctness conditions
(a stale venv, a stale CMake cache) where hard-failing would impose an availability cost
disproportionate to a non-security-relevant problem. Network egress enforcement is the primary
control against Information Disclosure; the asymmetry does not hold here.

### 6.4 Decision record: non-root execution and runtime hardening for the proxy container

Not present in the original `squid_proxy_guide.md`. Two related findings from reviewing the
guide's Dockerfile and reference `start.sh` against this project's own stated principles:

1. The guide's `Dockerfile` has no `USER` directive, and its `squid.conf` does not set
   `cache_effective_user` (the directive Debian's stock config normally uses to drop privileges
   internally after startup). Without either, Squid runs as root for its full process lifetime.
   Port 3128 does not require root to bind (only ports below 1024 do), so there is no functional
   reason for this. Addressed in §5.1 via `USER proxy` — pending implementation-time
   confirmation of the exact service-user name Debian's `squid` package creates.
2. The guide's reference `start.sh` proxy invocation carries no `--cap-drop=ALL` or
   `--security-opt=no-new-privileges`, inconsistent with the treatment given to the main session
   container and with this project's "no single control carries the full burden" posture applied
   everywhere else. Addressed in §5.4.

Neither finding is a currently-exploited gap — the proxy does not execute attacker-influenced
code in the way the main session container's `claude-agent` process does. The recommendation is
defense-in-depth consistency: every other container in this project runs non-root and
capability-dropped; the proxy should not be the one exception, especially given it is a new
network-facing component sitting directly between every session and the internet.

### 6.5 Updated STRIDE coverage map (delta)

| Threat (STRIDE) | Controls — pre-existing (claimed but not implemented) | Controls — added by this design |
|---|---|---|
| **Information Disclosure (I)** | Squid allowlist (documented, not implemented) | Squid allowlist actually built, wired into `build.sh`/`start.sh`, and enforced via `HTTP_PROXY`/`HTTPS_PROXY` injection; fail-closed on proxy startup failure |
| **Repudiation (R)** | Squid access log (documented, not implemented) | Access log actually active, captured via Docker's default log driver |
| **Elevation of Privilege (E)** | — | Non-root execution inside the proxy container; `--cap-drop=ALL` / `--security-opt=no-new-privileges` on the proxy's own runtime invocation |
| **Denial of Service (D)** | — | Fail-closed proxy startup is a deliberate, bounded availability cost accepted in exchange for not silently degrading the egress control (§6.3) |

No other row in the existing coverage map changes.

---

## 7. Interface Contract

### 7.1 `build.sh` contract

- `./build.sh squid` builds `claude-squid` standalone, no dependency on `claude-base`.
- `./build.sh` (no target / `all`) includes `claude-squid` in the full build.
- No `HOST_UID` build-arg is passed or required for this target (§5.3).

### 7.2 `start.sh` contract

- Aborts before starting the main container if `claude-squid` does not exist, with the same
  `Build it first with: ./build.sh squid` guidance pattern used for the other profile images.
- Aborts (fail-closed) if the proxy container fails to start; the main session container is
  never started in that case.
- Proxy container is guaranteed torn down on script exit via `trap ... EXIT`, regardless of exit
  path (success, main-container failure, or interrupt).
- Existing positional interface (`start.sh <project_dir> [image]`) is unchanged.

### 7.3 Allowlist contract

- `dstdomain` exact-match is the default and required mechanism for all new entries.
- `dstdom_regex` requires an inline comment justifying why a flat list is insufficient, and must
  be anchored.
- Single `squid.conf`, shared across all profiles (§3) — no profile-scoped subsetting at this
  stage.

### 7.4 What this design does not guarantee

- Does not protect against exfiltration to any domain already on the allowlist — CONNECT-tunnel
  blindness is an accepted limitation, not a solved problem (§3, §6.2-I).
- Does not cover unanticipated third-party sites needed mid-session. The documented path is the
  break-glass procedure: edit `squid.conf`, rebuild `claude-squid` only (seconds — no toolchain),
  the next `start.sh` invocation picks it up automatically. This is an operational habit, not a
  gap to be closed by loosening default policy.
- Does not validate behavior under rootless Podman/`slirp4netns` — explicitly deferred to the
  Podman migration SDD, which will use this design (and `test_squid_isolation.bats` against it)
  as the known-good baseline.

---

## 8. Implementation Plan

Each step maps to a single commit, per project convention.

1. **Add `squid/Dockerfile` and `squid/squid.conf`** — content per §5.1–5.2. Resolve and pin the
   `debian:bookworm-slim` digest at this step; confirm the Debian-created service-user name via
   `id proxy` (or actual name found) inside a locally built image before finalizing `USER`.
2. **Add `build_squid` to `build.sh`** — §5.3, including the `squid` case target and inclusion in
   `all`.
3. **Modify `start.sh`** — §5.4: image-existence preflight, `trap cleanup EXIT`, proxy startup
   with fail-closed behavior, `--env` additions to the main container invocation.
4. **Correct `docs/squid_proxy_guide.md`** — §5.5: Part 3 Step 4 and Part 5, per the corrections
   described above. Add a changelog entry to the guide following its own established convention
   (Change 6).
5. **Rebuild and smoke test** — `./build.sh squid`, then a manual session start confirming: proxy
   container starts and is visible in `docker ps`; an allowed-domain request succeeds; a
   non-allowed-domain request is refused; the proxy container is gone after the session ends
   (including after a `Ctrl+C` interrupt, to verify the `trap` path specifically, not just clean
   exit).
6. **Run `test_squid_isolation.bats`** — `bats --filter-tags slow tests/test_squid_isolation.bats`
   (or the full slow tier) — S-1/S-2/S-3 should now pass against the real `squid/` directory
   rather than failing at `setup_file()`.
7. **Add a changelog entry** to `docs/claude_code_security_plan.md`, following the established
   Change-N format, using §6 of this document as source material.

---

## 9. Open Questions and Non-Decisions

**Q: Should `squid.conf` be split per-profile now rather than shared?**

Not decided; deliberately deferred per §3. Revisit only if the shared reference tier proves
too broad for a given profile in practice, or when the config-file evaluation (pre-merge task 3)
is taken up post-Podman-migration.

**Q: Should the reference tier be expanded preemptively to reduce break-glass frequency?**

Not decided. Current position (§3, §7.4): fixed list at implementation time, expanded via the
break-glass procedure as real, observed need arises — not by trying to anticipate every future
documentation site now. If break-glass edits become frequent for the same handful of domains,
that is itself the signal to promote them into the tracked reference tier.

**Q: Should `--log-opt max-size`/`max-file` be added explicitly to the proxy container, given
the main container doesn't currently set them either?**

Noted in §6.2-R as a cheap hygiene addition for the proxy specifically, recommended at
implementation time. The main-container gap is flagged as a separate, pre-existing finding —
not addressed here, to avoid silent scope expansion beyond what this design set out to fix.

**Q: Does the non-root proxy hardening (§6.4) risk breaking anything Squid needs write access
to?**

Believed no — caching is disabled (`cache deny all`), logging goes to stdout (no file write),
and the only file the process needs to read is `/etc/squid/squid.conf` (world-readable by
default from `COPY`). Should be confirmed empirically at implementation time (step 1 of §8)
rather than assumed.

---

## Changelog

### Version 1.0 — 2026-08-03
Initial draft. Derived from the design discussion between the operator and Claude Sonnet 5,
triggered by `test_squid_isolation.bats` setup failures surfacing that `squid/` was never
committed and `start.sh` was never actually wired to use it, contradicting
`docs/squid_proxy_guide.md`'s claims. Establishes `dstdomain`-primary/`dstdom_regex`-exception
allowlist design, a curated reference-documentation tier, fail-closed proxy startup, and two
hardening additions beyond the original guide (non-root proxy execution, runtime hardening flags
on the proxy container).

### Version 1.1 — 2026-08-03
Operator signed off on the §6.3 fail-closed decision. Status moved from Draft to Accepted.
Document relocated to `docs/designs/squid-proxy-integration.md` per the location convention in
`docs/designs/docs-as-code-workflow.md` (§2.2, repository layout).
