# Squid Proxy Implementation Guide

---

## Objectives

This guide implements the network isolation layer described in Phase 2.8–2.9
of `claude_code_security_plan.md`. It has two goals:

**1. Enforce a default-deny outbound network policy.** Without network
restriction, a compromised Claude session can transmit workspace contents to
any server on the internet. Squid acts as a mandatory checkpoint: all HTTP
and HTTPS traffic from every Claude container must pass through it, and any
connection to a domain not on the allowlist is refused before a single byte
leaves the network.

**2. Provide a human-readable audit trail of every outbound connection.** The
Squid access log records one line per attempted connection — destination,
timestamp, bytes transferred, and permit/deny outcome. This directly addresses
the **Repudiation (R)** threat: you can always reconstruct what Claude
attempted to contact during a session and whether it succeeded.

### Scope

This guide covers running Squid as a companion container on the `claude-net`
Docker network alongside the Claude Code sandbox images defined in
`build.sh`. It does not cover transparent proxying, TLS inspection, or
authentication between the Claude container and the proxy — none of which
are needed for this use case.

### Relationship to the main security plan

Squid implements Layer 4 of the five-layer defense described in the security
plan. It is independent of the other layers: if the `permissions.deny`
application layer is misconfigured, Squid still blocks the network call.
If Squid is misconfigured, `permissions.deny` still blocks the tool invocation
before it reaches the network. The layers do not trust each other.

---

## Part 1 — What Is a Proxy, and Why Does It Exist?

### The Core Concept

A **proxy** is an intermediary — an entity that acts on behalf of another. In networking, a proxy server sits between a client (your container) and the internet. Instead of your container connecting directly to, say, `api.anthropic.com`, it sends the request to the proxy, which evaluates it, and either forwards it or refuses it.

The analogy that maps cleanly to your security thinking: a proxy is a **checkpoint**. All traffic must pass through it and declare its destination. The proxy consults a policy (its configuration file) and decides whether to let the traffic through.

There are two fundamental kinds:

- **Forward proxy:** Sits in front of clients, controlling their outbound access to the internet. This is what you want — a gatekeeper that decides which external destinations your container is allowed to reach.
- **Reverse proxy:** Sits in front of servers, controlling inbound access. Used to protect web services; not relevant here.

### Historical Context

The concept of proxies emerged in the early 1990s alongside the explosive growth of the web. University and corporate networks faced two problems simultaneously: bandwidth was expensive and scarce, and administrators wanted to control what users could access.

The first major open-source proxy was **CERN httpd** (1990), developed at the same lab that created the World Wide Web. It introduced the idea of a proxy that could cache frequently-requested web pages, so multiple users fetching the same resource only caused one actual download. This was purely about efficiency.

**Squid** was born from this lineage. It began as a research project called *Harvest* at the University of Colorado in 1994, evolving into Squid by 1996 under Duane Wessels. Its name is a playful nod to its predecessor *Cached* — squid are related to cuttlefish, a species that... also caches things in its ink sac. The naming logic is loose, but the software endured.

What made Squid dominant was that it combined three things in one tool: caching (efficiency), access control (security policy), and logging (auditability). These are exactly the three properties you need for your use case — though you care primarily about the last two.

Squid has been continuously maintained for nearly 30 years and is today a standard component in enterprise network security, ISP infrastructure, and exactly the kind of sandboxing setup you're building. It is mature, well-documented, and designed to be configured through a human-readable text file — which is what makes it preferable to raw `iptables` rules for this use case.

### Why a Proxy Rather Than a Firewall Rule?

Both approaches can restrict outbound traffic, but they work at different layers and have different properties:

| Property | `iptables` firewall rule | Squid proxy |
|----------|--------------------------|-------------|
| Works at | Network layer (IP addresses) | Application layer (domain names, URLs) |
| Allowlist format | IP addresses and ports | Domain names |
| Problem with IP-based rules | Cloud services change IPs constantly; `api.anthropic.com` may resolve to dozens of different IPs | None — Squid resolves DNS at connection time |
| Auditability | Kernel logs, hard to read | Plain-text access log, one line per request |
| Configuration readability | Arcane `iptables` syntax | Plain English-like config file |
| Gives you connection logs | Requires extra setup | Built-in, always on |

For a cryptographer who values auditability and wants a clear record of every outbound connection Claude attempted, Squid's access log is particularly valuable. It becomes part of your audit trail, addressing the **Repudiation (R)** threat alongside Docker's own logs.

---

## Part 2 — Architecture of the Setup

You will run Squid as a **companion container** on the same Docker network as Claude Code. The Claude Code container is configured to route all HTTP and HTTPS traffic through Squid before it leaves the network.

```
┌─────────────────────────────────────────────────────────┐
│                   claude-net (Docker network)            │
│                                                          │
│  ┌────────────────────────┐   ┌────────────────────────┐ │
│  │  claude-base / crypto  │   │  squid-proxy           │ │
│  │  / systems / research  │──▶│  (port 3128)           │ │
│  │  (Claude Code)         │   │                        │ │
│  │  HTTP_PROXY=squid:3128 │   │  Allowlist policy      │ │
│  │  HTTPS_PROXY=squid:... │   │  Access logs           │ │
│  └────────────────────────┘   └───────────┬────────────┘ │
│                                            │              │
└────────────────────────────────────────────┼──────────────┘
                                             │
                                 ┌───────────▼──────────┐
                                 │     THE INTERNET      │
                                 │                       │
                                 │  ✓ api.anthropic.com  │
                                 │  ✓ pypi.org           │
                                 │  ✗ everything else    │
                                 └──────────────────────┘
```

Port `3128` is Squid's default and conventional port — it has been since the 1990s.

---

## Part 3 — Implementation

### Step 1 — Create the Squid configuration file

Create the directory `~/.claude-sandbox/squid/` and place this file inside it as `squid.conf`:

```
# ─── squid.conf ───────────────────────────────────────────────────────────────
# Squid configuration for Claude Code sandboxing
# Policy: deny everything by default, allow only what is explicitly listed.
# ──────────────────────────────────────────────────────────────────────────────

# Port Squid listens on inside the container
http_port 3128

# ── Allowed destinations ──────────────────────────────────────────────────────

# Claude Code API endpoint (required for all Claude Code operation)
acl allowed_domains dstdomain api.anthropic.com

# Package registries — add or remove based on your project's needs
# acl allowed_domains dstdomain registry.npmjs.org
# acl allowed_domains dstdomain pypi.org
# acl allowed_domains dstdomain files.pythonhosted.org

# Your institution's internal mirror (uncomment and edit if applicable)
# acl allowed_domains dstdomain your.internal.mirror.example.com

# ── Access policy ─────────────────────────────────────────────────────────────

# Allow HTTPS CONNECT tunneling only to allowed domains
acl CONNECT method CONNECT
http_access allow CONNECT allowed_domains

# Allow plain HTTP only to allowed domains
http_access allow allowed_domains

# Deny everything else — this is the default-deny posture
http_access deny all

# ── Logging ───────────────────────────────────────────────────────────────────

# Log every request to stdout so Docker captures it
access_log stdio:/dev/stdout combined

# ── Privacy and cache ─────────────────────────────────────────────────────────

# Do not cache anything — you want fresh responses and no data persistence
cache deny all

# Strip client IP from forwarded headers (don't leak internal network topology)
forwarded_for off

# Do not reveal that a proxy is in use
via off
```

**Reading the config:** Each `acl` line defines a named rule. `allowed_domains` is the allowlist. The `http_access` lines enforce the policy: permit connections to allowed domains, deny everything else. The order matters — Squid evaluates rules top to bottom and acts on the first match.

---

### Step 2 — Create the Squid Dockerfile

In `~/.claude-sandbox/squid/Dockerfile`:

```dockerfile
FROM debian:bookworm-slim

# debian:bookworm-slim is used here for consistency with the Claude Code
# sandbox images and for a smaller attack surface than ubuntu:24.04.
# Squid is available in the standard Debian bookworm repository.
# The -N flag in CMD tells Squid to run in the foreground rather than
# forking into the background as a daemon. Docker requires the container's
# main process to stay in the foreground; a daemonising process causes
# Docker to consider the container immediately exited.
RUN apt-get update && apt-get install -y --no-install-recommends squid \
    && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf

EXPOSE 3128

CMD ["squid", "-N", "-f", "/etc/squid/squid.conf"]
```

---

### Step 3 — Build the Squid image

The Squid image is built by `build.sh` alongside the Claude Code images.
To build everything at once:

```bash
cd ~/.claude-sandbox && ./build.sh
```

To build only the Squid image:

```bash
docker build -t claude-squid ~/.claude-sandbox/squid/
```

---

### Step 4 — Update the main launch script

The current `start.sh` already incorporates Squid. For reference, the
core pattern it uses is shown below. The key points are:

- The proxy container is started first with `-d` (detached) and given a
  unique name derived from the shell PID (`$$`) so concurrent sessions
  don't collide.
- `HTTP_PROXY` and `HTTPS_PROXY` are set to the proxy container's name.
  Docker's internal DNS resolves container names on the same network, so
  `http://claude-proxy-$$:3128` reaches the Squid container without any
  IP address configuration.
- `NO_PROXY` excludes localhost so that intra-container loopback traffic
  is not accidentally routed through the proxy.
- After the Claude session exits, the proxy container is stopped and
  removed. The `||  true` guard ensures a failed stop doesn't mask the
  fact that the session completed.

```bash
#!/usr/bin/env bash
# Usage: start.sh <project_directory> [image]
# image: base | crypto | systems | research  (default: base)

set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"
IMAGE_TAG="${2:-base}"
IMAGE_NAME="claude-${IMAGE_TAG}"
PROXY_NAME="claude-proxy-$$"
CLAUDE_NAME="claude-$(basename "$PROJECT_DIR")-$$"

echo "Project : $PROJECT_DIR"
echo "Image   : $IMAGE_NAME"
echo "Proxy   : $PROXY_NAME"
echo ""

echo "Starting Squid proxy..."
docker run -d \
    --name "$PROXY_NAME" \
    --network claude-net \
    claude-squid

echo "Starting Claude Code sandbox..."
docker run --rm -it \
    --name "$CLAUDE_NAME" \
    --network claude-net \
    --env HTTP_PROXY="http://$PROXY_NAME:3128" \
    --env HTTPS_PROXY="http://$PROXY_NAME:3128" \
    --env NO_PROXY="localhost,127.0.0.1" \
    --env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
    --mount type=bind,source="$PROJECT_DIR",target=/workspace \
    --memory="2g" \
    --cpus="2" \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    --log-driver json-file \
    --log-opt max-size=50m \
    --log-opt max-file=5 \
    "$IMAGE_NAME"

echo ""
echo "Session ended. Stopping proxy..."
docker stop "$PROXY_NAME" && docker rm "$PROXY_NAME" || true
echo "Done."
```

Make it executable:

```bash
chmod +x ~/.claude-sandbox/start.sh
```

---

### Step 5 — Test the proxy in isolation

Before trusting this in a real session, verify it works as expected:

```bash
# Start the proxy manually
docker run -d --name test-proxy --network claude-net claude-squid

# Test 1: allowed domain — should succeed
docker run --rm --network claude-net \
  --env HTTPS_PROXY="http://test-proxy:3128" \
  curlimages/curl:latest \
  curl -sv https://api.anthropic.com

# Test 2: blocked domain — should fail with "Access Denied"
docker run --rm --network claude-net \
  --env HTTPS_PROXY="http://test-proxy:3128" \
  curlimages/curl:latest \
  curl -sv https://example.com

# View the proxy access log
docker logs test-proxy

# Clean up
docker stop test-proxy && docker rm test-proxy
```

In Test 1 you should see the connection proceed. In Test 2 you should see a `403 Access Denied` or a connection refusal. The `docker logs test-proxy` output is your audit log — one line per attempted connection, showing the destination, the time, and whether it was permitted.

---

## Part 4 — Reading the Squid Access Log

Squid's access log format looks like this:

```
1709050412.345   203 192.168.1.5 TCP_TUNNEL/200 9876 CONNECT api.anthropic.com:443 - HIER_DIRECT/1.2.3.4 -
1709050415.120    42 192.168.1.5 TCP_DENIED/403    0 CONNECT evil.example.com:443 - HIER_NONE/- -
```

Reading left to right: timestamp, response time in milliseconds, client IP, result code, bytes transferred, HTTP method, destination, and routing info.

The key result codes:

| Code | Meaning |
|------|---------|
| `TCP_TUNNEL/200` | HTTPS connection permitted and tunneled — normal allowed traffic |
| `TCP_DENIED/403` | Connection blocked by policy — what you want to see for non-allowlisted domains |
| `TCP_MISS/200` | HTTP request permitted and forwarded |

Any `TCP_TUNNEL` or `TCP_MISS` to a domain you did not intentionally allow is a red flag worth investigating.

---

## Part 5 — Maintenance

**Adding an allowed domain** for a specific project: edit `squid.conf`, add a line to the `acl allowed_domains` block, rebuild the Squid image, and restart the proxy container. The Claude Code containers do not need to be rebuilt.

```bash
docker build -t claude-squid ~/.claude-sandbox/squid/
```

**Keeping Squid updated**: rebuild the Squid image periodically with `--no-cache` to pull the latest Debian package:

```bash
docker build --no-cache -t claude-squid ~/.claude-sandbox/squid/
```

**Per-project allowlists**: if different projects need different allowed domains, maintain multiple `squid.conf` variants (e.g., `squid-crypto.conf`, `squid-web.conf`) and select the right one at launch time. This gives you per-project network policies without per-project networks. The image hierarchy in `build.sh` already separates projects by domain — the Squid allowlist is the corresponding network-layer separation.

---

## Summary: What You Now Have

```
Layer 1 (Application):  permissions.deny in Claude Code config
                         → blocks dangerous commands before they reach the shell

Layer 2 (Container):    Non-root user + --cap-drop=ALL + --no-new-privileges
                         → limits what a compromised process can do on the OS

Layer 3 (Filesystem):   Bind mount of project directory only
                         → key material and other projects are physically absent

Layer 4 (Network):      Squid proxy with domain allowlist
                         → exfiltration to arbitrary destinations is impossible

Layer 5 (Audit):        Squid access log + Docker logs + Claude Code session logs
                         → full record of what was attempted and what succeeded
```

Each layer is independent. Bypassing any one of them does not defeat the others. This is defense in depth expressed as a concrete, running system.

---

## Changelog

A record of every correction and upgrade made to this document and the
accompanying Squid implementation files, in chronological order. Each entry
states what changed, why, and the security reasoning where relevant.

---

### Change 1 — Base Image Changed from Ubuntu to Debian
**Affects:** Step 2 (Squid Dockerfile). Date: 2026-04-09.

**What changed:**
The Squid Dockerfile base image was changed from `ubuntu:24.04` to
`debian:bookworm-slim`.

**Why:** Two reasons. First, consistency: all Claude Code sandbox images use
`debian:bookworm-slim` following the same decision recorded in Change 3 of
`claude_code_security_plan.md`. A mixed base-image environment creates
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
Dockerfiles in Change 12 of `claude_code_security_plan.md`. In the specific
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
upgrade described in Change 10 of `claude_code_security_plan.md`. A script
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
