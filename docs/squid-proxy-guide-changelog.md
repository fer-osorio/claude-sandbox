# Squid Proxy Guide Changelog

A record of every correction and upgrade made to
[`squid-proxy-guide.md`](squid-proxy-guide.md) and the accompanying Squid
implementation files, in chronological order. Each entry states what
changed, why, and the security reasoning where relevant.

Split out of that document in #139, applying the convention #132 established
for `claude-code-security-plan.md`. Numbering here is this guide's own and is
independent of the security plan's — which is why a bare "Change 2" was
ambiguous before the split, and why citations should name the file.
Nothing was summarised or removed in the move.

---

### Change 1 — Base Image Changed from Ubuntu to Debian
**Affects:** Step 2 (Squid Dockerfile). Date: 2026-04-09.

**What changed:**
The Squid Dockerfile base image was changed from `ubuntu:24.04` to
`debian:bookworm-slim`.

**Why:** Two reasons. First, consistency: all Claude Code sandbox images use
`debian:bookworm-slim` following the same decision recorded in Change 3 of
`claude-code-security-plan.md`. A mixed base-image environment creates
unnecessary complexity when auditing the full image set. Second, the slim
variant has a smaller installed package footprint, reducing the Squid
container's attack surface.

The UID conflict that originally motivated the switch from Ubuntu
(`ubuntu:24.04` pre-creates UID 1000) does not apply to the Squid container
directly because Squid does not use `HOST_UID`. The consistency and footprint
arguments are sufficient on their own.

**Security posture:** Marginally improved. Debian bookworm is the upstream
base for Ubuntu 24.04; all security properties carry over.

---

### Change 2 — Inline Shell Comments Removed from start.sh
**Affects:** Step 4 (launch script). Date: 2026-04-09.

**What changed:**
The `start.sh` shown in Step 4 contained `#` comments embedded inside a
multi-line `docker run` command connected by `\` line continuations. These
were removed. All explanatory text was moved into prose above the code block.

**Why:** A `\` at the end of a line continues the shell expression onto the
next line. A `#` character appearing in that context does not reliably start
a comment — the shell may silently drop the commands that follow it rather
than producing an error. This is the same class of bug addressed across all
Dockerfiles in Change 12 of `claude-code-security-plan.md`. In the specific
case of `start.sh`, the flags after several of the inline comments —
including `--security-opt`, `--cap-drop`, and the logging flags — were at
risk of being silently omitted, which would have degraded the security
posture of every session without any visible indication.

**Security posture:** The corrected script reliably passes `--cap-drop=ALL`,
`--security-opt=no-new-privileges`, and `--log-driver json-file` on every
invocation. These flags are **Elevation of Privilege (E)** and
**Repudiation (R)** controls respectively; their silent omission would have
been a meaningful regression.

---

### Change 3 — start.sh Updated for Image Hierarchy
**Affects:** Step 4 (launch script). Date: 2026-04-09.

**What changed:**
The `start.sh` shown in Step 4 previously referenced `claude-sandbox` as
a fixed image name. It was updated to accept a second argument selecting
the domain-specific image (`base`, `crypto`, `systems`, or `research`),
consistent with the image hierarchy introduced in the main security plan.

The cleanup step was also made fault-tolerant: `docker stop && docker rm`
now includes `|| true` so that a proxy container that has already stopped
(e.g. due to a crash) does not cause the script to exit with an error and
mask the completion of the session.

**Why:** The single `claude-sandbox` image no longer exists following the
upgrade described in Change 10 of `claude-code-security-plan.md`. A script
referencing it would fail immediately. The `|| true` guard is a robustness
improvement with no security implications.

---

### Change 4 — Step 3 Integrated with build.sh
**Affects:** Step 3 (build command). Date: 2026-04-09.

**What changed:**
Step 3 previously gave a standalone `docker build` command for the Squid
image. It now references `build.sh` as the primary build mechanism, with
the direct `docker build` command retained for rebuilding Squid in isolation.

**Why:** `build.sh` was introduced in the image hierarchy upgrade to build
all sandbox images in dependency order. The Squid image should be part of
that workflow so that a single `./build.sh` command produces a complete,
consistent set of images rather than requiring a separate manual step.

---

### Change 5 — Maintenance Section Updated
**Affects:** Part 5 (Maintenance). Date: 2026-04-09.

**What changed:**
The "Keeping Squid updated" instruction changed the reference from "latest
Ubuntu package" to "latest Debian package", consistent with Change 1 above.
The per-project allowlists note was extended with a sentence connecting the
Squid allowlist to the image hierarchy: the two are the network-layer and
image-layer expressions of the same per-domain separation of concerns.

**Why:** The Ubuntu reference was a stale artefact. The added sentence makes
the relationship between the image hierarchy and the network policy explicit
so both can be maintained together when a new project type is added.

---

### Change 6 — Squid Actually Implemented and Wired In
**Affects:** Part 3 Step 4 (launch script), Part 5 (Maintenance). Date: 2026-08-04.

**What changed:**
`squid/Dockerfile` and `squid/squid.conf` are now committed and tracked in
the repository — previously this guide described files that did not exist
anywhere in version control. `build.sh` now builds `claude-squid` via a new
`squid` target, included in `all`. The tracked `start.sh` now implements the
proxy lifecycle Step 4 previously only claimed it did: a fail-closed
preflight check for the `claude-squid` image, `trap`-based teardown of the
proxy container covering normal exit, main-container failure, and interrupt,
and `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` injection into the main container.
Step 4's fabricated reference `start.sh` sample — which also predated the
global-layer-injection mount logic, a second, independent staleness — is
replaced with a pointer to the actual tracked script. Part 5's "restart the
proxy container" instruction is removed: the proxy is ephemeral and
recreated fresh on every `start.sh` invocation, so a `squid.conf` edit plus
an image rebuild is picked up automatically by the next session with no
separate restart step.

**Why:** `test_squid_isolation.bats` (Group 3, S-1–S-3) failed at
`setup_file()` because `squid/` was never committed — this guide's own claim
that "the current `start.sh` already incorporates Squid" was false against
the tracked tree. See `docs/designs/0012-squid-proxy-integration.md` for the full
design, STRIDE analysis, and rationale (fail-closed startup, non-root proxy
execution, digest pinning).

**Security posture:** Materially improved, not a documentation-only fix.
Before this change, Layer 4 (network egress allowlisting) was a no-op:
sessions ran with unrestricted egress on `claude-net`, constrained only by
`permissions.deny`'s narrow bash-command denials. This closes that gap.

---

### Change 7 — `pid_filename none` Added After Non-Root Startup Failure
**Affects:** Step 1 (`squid.conf`). Date: 2026-08-05.

**What changed:**
Smoke testing (per Change 6) found the proxy container exiting immediately after start, with
`docker logs` showing `FATAL: failed to open /run/squid.pid: (13) Permission denied`. Running
Squid entirely as the non-root `proxy` user (introduced beyond this guide's original design —
see `docs/designs/0012-squid-proxy-integration.md` §6.4) means it never holds root privileges to
open the root-owned `/run/squid.pid`, unlike Squid's normal pattern of opening privileged
resources as root before dropping to its effective user. `pid_filename none` was added to
`squid.conf`, telling Squid not to write a PID file at all.

**Why:** Docker already tracks this container's process directly as its PID 1; Squid's own PID
file serves no purpose in this setup and was the one thing non-root execution from process start
couldn't do. Caching and logging — the other candidates considered for breakage under non-root
execution — were unaffected, as expected (caching is disabled via `cache deny all`; the access
log goes to stdout, not a file).

**Security posture:** Unchanged from Change 6's hardening — `USER proxy` is retained. This
removes the specific obstacle to non-root execution rather than reverting it.

---

### Change 8 — Access Log Format Corrected from `combined` to `squid`
**Affects:** Step 1 (`squid.conf`). Date: 2026-08-05.

**What changed:**
Step 1's `squid.conf` template set `access_log stdio:/dev/stdout combined`. This has been an
inconsistency in this guide since its first version: `combined` is Squid's NCSA/Apache-style log
format, whose result field is `%Ss:%Sh` — e.g. `TCP_TUNNEL:HIER_DIRECT` — while Part 4's own
documented example lines (`TCP_TUNNEL/200`, `TCP_DENIED/403`) are Squid's native `squid` format,
a different named format entirely. `test_squid_isolation.bats` (S-1, S-3) failed against a fully
working proxy — full CONNECT tunnel, full TLS handshake, correct 404 from `api.anthropic.com` —
because the assertions parse the native format's `TAG/CODE` shape, which `combined` never
produces. S-2 passed regardless, by coincidence: its check is a loose `TCP_DENIED` substring
match, present in both formats, just followed by `:HIER_NONE` instead of `/403`. The directive
is now `access_log stdio:/dev/stdout squid`.

**Why:** Nobody had run this configuration end-to-end until step 5 smoke testing surfaced it.
The mismatch was invisible from reading the config alone — both `combined` and `squid` are valid
Squid log formats, and only comparing an actual emitted log line against Part 4's documented
example revealed the discrepancy.

**Security posture:** Unchanged — this is a log-format correctness fix, not a policy change. The
allowlist enforcement itself (confirmed working via the manual CONNECT tunnel test) was never
affected.

---

### Change 9 — `platform.claude.com` Added to the Core Tier Allowlist
**Affects:** Step 1 (`squid.conf`). Date: 2026-08-06.

**What changed:**
A real Claude Code session through the fixed proxy hit `Failed to connect to
platform.claude.com: Status 403` — Squid correctly denying a domain that was never on the
allowlist. Step 1's core tier had only ever listed `api.anthropic.com`. `platform.claude.com` —
Claude Code's own service endpoint, distinct from the classic Anthropic API domain — is now
also allowed.

**Why:** Confirmed required by a live, session-blocking denial, not by inspecting Claude Code's
source or documentation in advance. `api.anthropic.com` is retained; nothing so far indicates
it's unused.

**Security posture:** The allowlist grows by exactly one entry, required for Claude Code to
function at all. No change to the default-deny posture or any other control.
