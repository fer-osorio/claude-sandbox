# Security Plan Changelog

A record of every correction and refinement made to the
*Claude Code Security: Implementation Plan with Threat Modeling*,
in chronological order. Each entry explains what changed, why it changed,
and what the underlying cause was.

---

## Change 1 — Installation Method Corrected

**Affects:** Phase 1, Dockerfile in Phase 2.1

**What changed:**
The original plan used `npm install -g @anthropic-ai/claude-code` in both
the host installation instructions and the Dockerfile. This was replaced with
the native installer in Phase 1:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

**Why:** The npm installation method has been officially deprecated by
Anthropic. The native installer produces a self-contained binary that requires
no Node.js runtime, starts faster, and has a more stable auto-updater.

**Note on the Dockerfile:** The native installer proved unreliable in the
Docker build context (see Change 3 below), so the Dockerfile ultimately
retains the npm method. The deprecation applies to host installations;
inside a controlled Dockerfile environment, npm remains functional and
installs to a predictable, standard location.

---

## Change 2 — Host Installation Reframed

**Affects:** Phase 1

**What changed:**
The original plan stated the host installation was "required even if you
later run it primarily inside containers." This was corrected. The host
installation serves exactly one purpose: running the one-time OAuth
authentication flow. It is not required for sandboxed operation itself.

**Why:** The Dockerfile installs Claude Code inside the container image,
which is the actual installation used for all work. The only reason to
install on the host is to obtain credentials that are then injected into
containers as environment variables.

---

## Change 3 — Dockerfile Base Image Changed

**Affects:** Phase 2.1 (Dockerfile)

**What changed:**
The base image was changed from `ubuntu:24.04` to `debian:bookworm-slim`,
and the installation method inside the Dockerfile was kept as npm (not the
native installer). The final working Dockerfile:

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl git nodejs npm \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

ARG HOST_UID=1000
RUN groupadd -r claude-agent && \
    useradd -r -g claude-agent -m -d /home/claude-agent \
    -u $HOST_UID claude-agent

WORKDIR /workspace
RUN chown claude-agent:claude-agent /workspace

USER claude-agent
CMD ["claude"]
```

**Why — two compounding issues discovered during implementation:**

*Issue A:* The native installer placed the `claude` binary in
`/root/.local/bin/`, which is not on the `PATH` of the `claude-agent`
user. The container started but immediately failed with
`executable file not found in $PATH`. The npm method installs to
`/usr/local/bin/claude`, which is always on `PATH` for all users.

*Issue B:* Ubuntu 24.04 pre-creates a user with UID 1000 named `ubuntu`
(a Canonical convention for cloud images). Attempting to create
`claude-agent` at the same UID failed with `useradd: UID 1000 is not unique`.
Debian slim images do not pre-create any UID 1000 user, so the conflict
does not exist.

**Security posture:** Unchanged. Debian bookworm is the upstream base for
Ubuntu; all the same security properties apply. The slim variant has a
smaller attack surface due to fewer pre-installed packages.

---

## Change 4 — `--add-host` Flag Removed

**Affects:** Phase 2.4

**What changed:**
The original plan mentioned Docker's `--add-host` flag as a mechanism for
restricting network connections. This was removed and corrected.

**Why:** `--add-host` adds static entries to a container's `/etc/hosts`
file — it is a DNS convenience tool, not a firewall. It does not prevent
connections to any destination. The section now clearly states that real
outbound restriction requires either `iptables` rules or the Squid proxy.

---

## Change 5 — Network Section Clarified

**Affects:** Phase 2.4, new Phase 2.5

**What changed:**
The network setup section was restructured to clarify that the Docker
network (`claude-net`) is created once and shared across all projects.
Per-project variation lives in the Squid allowlist rules, not in separate
networks. A new Phase 2.5 was added as a bridge to the companion
*Squid Proxy Implementation Guide*.

**Why:** The original text was ambiguous about whether a new network should
be created per project, which would have been unnecessarily complex and
architecturally incorrect.

---

## Change 6 — Entrypoint Script Added (then Superseded)

**Affects:** Phase 2.1 (Dockerfile), start.sh

**What changed:**
During implementation, Claude Code could not write to mounted project files
because the bind-mounted files were owned by the host Fedora user, while
the container process ran as `claude-agent` — a different user. An
entrypoint script was introduced to `chown` the workspace at container
startup:

```bash
#!/bin/bash
chown -R claude-agent:claude-agent /workspace
exec su -s /bin/bash claude-agent -c "$(printf '%q ' "$@")"
```

This was subsequently superseded by Change 3 (UID matching), which
eliminates the ownership mismatch at the design level rather than
patching it at runtime. The entrypoint script is no longer needed
and is not present in the final Dockerfile.

**Why the `chown` approach failed:** The host system runs rootless Docker
(enabled by `sudo usermod -aG docker $USER` on Fedora). In rootless mode,
`root` inside the container maps to the unprivileged host user outside it
via Linux user namespaces. A process cannot `chown` files to a UID that
falls outside its mapped user namespace range, so the operation failed
with `Operation not permitted`.

---

## Change 7 — UID Matching via Build Argument

**Affects:** Phase 2.1 (Dockerfile), build command

**What changed:**
The Dockerfile now accepts a `HOST_UID` build argument and creates
`claude-agent` with that exact UID. The image must be built passing
the host user's UID:

```bash
docker build \
  --build-arg HOST_UID=$(id -u) \
  -t claude-sandbox \
  ~/.claude-sandbox/
```

**Why:** When `claude-agent` inside the container and the user outside it
share the same UID, the Linux kernel treats them as the same owner for
filesystem permission purposes. The bind-mounted project files are already
owned by the correct UID from the container's perspective, requiring no
`chown`, no `sudo`, and no privilege escalation of any kind. This is the
architecturally correct solution — aligning identities rather than granting
extra permissions to work around a mismatch.

**STRIDE mapping:** This change strengthens **Elevation of Privilege (E)**
controls by removing the need for any root operations at container startup,
and it removes the `sudo` availability that was an unintended weakening of
the non-root user control.

---

## Change 8 — Git Safe Directory Behaviour Documented

**Affects:** Phase 6 (Operational Habits) — informational

**What changed:**
No file was modified, but the following operational knowledge was
established during troubleshooting and should be understood:

Git refuses to operate on repositories where the directory owner does not
match the running user (a security feature introduced in Git 2.35.2).
With the UID-matching fix from Change 7 in place, this warning should
not appear. If it does appear, it indicates the image was built without
the correct `HOST_UID`, and the image should be rebuilt rather than
approving the `git config --global --add safe.directory` workaround
Claude Code proposes.

**Security reasoning:** The `git config safe.directory` command addresses
a symptom rather than the cause and persists a configuration change. The
`chmod -R a+w` command that Claude Code also proposed as a workaround
should always be refused — it makes host files world-writable permanently,
weakening **Tampering (T)** controls on your actual Fedora filesystem.

---

## Current State of Key Files

### `~/.claude-sandbox/Dockerfile`
```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl git nodejs npm \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

ARG HOST_UID=1000
RUN groupadd -r claude-agent && \
    useradd -r -g claude-agent -m -d /home/claude-agent \
    -u $HOST_UID claude-agent

WORKDIR /workspace
RUN chown claude-agent:claude-agent /workspace

USER claude-agent
CMD ["claude"]
```

### Build command
```bash
docker build \
  --build-arg HOST_UID=$(id -u) \
  -t claude-sandbox \
  ~/.claude-sandbox/
```

### `~/.claude-sandbox/start.sh` (core docker run invocation)
```bash
docker run --rm -it \
  --name "claude-$(basename "$PROJECT_DIR")-$(date +%s)" \
  --mount type=bind,source="$PROJECT_DIR",target=/workspace \
  --network claude-net \
  --memory="2g" \
  --cpus="2" \
  --security-opt=no-new-privileges \
  --cap-drop=ALL \
  claude-sandbox
```

---

## What Has Not Changed

The security architecture, threat model, and STRIDE coverage map are
unchanged from the original plan. Every change above was a correction
to the *implementation* of the design — not to the design itself. The
layered defense structure (application permissions → non-root user →
filesystem isolation → network isolation → audit logging) remains intact
and all layers are functioning as intended.
