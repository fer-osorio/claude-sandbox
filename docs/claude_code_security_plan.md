# Claude Code Security: Implementation Plan with Threat Modeling

> **Audience:** A cryptographer and computer scientist who wants to use Claude Code safely while understanding the *why* behind every security decision.

---

## Objectives

This document describes the security architecture for running Claude Code on a local development workstation. It has three goals:

**1. Protect assets from agentic AI risk.** Claude Code is a capable agent that reads and writes files, executes shell commands, and makes network requests on your behalf. The primary threat is not a remote attacker — it is Claude being manipulated or mistaken into causing harm using the legitimate tools it already has. Every control in this plan is designed with that threat model in mind.

**2. Enforce least privilege at every layer.** No single control is trusted to carry the full security burden. The architecture is explicitly layered so that bypassing any one layer does not defeat the others. Each layer maps to specific STRIDE threat categories, making the coverage testable and the gaps visible.

**3. Support real development workflows without friction.** Security controls that are too inconvenient get bypassed. The implementation is designed to be the path of least resistance: one command to start a session, one command to build images, per-project isolation that requires no manual configuration each time.

### Scope

This plan covers a single-user local workstation running rootless Podman under WSL2 (default engine as of Change 16; rootless Docker on Fedora remains fully supported via `ENGINE=docker`). It does not cover multi-user deployments, CI/CD pipeline integration, or cloud-hosted agents. Extensions to those contexts would require additional controls not described here.

### Non-Goals

This plan does not attempt to protect against a fully compromised Docker engine, a malicious host kernel, or prompt injections that the operator manually introduces. Those residual risks are noted in the Quick Reference Card at the end of this document.

---

## 0. Framing: What Is Threat Modeling?

Before the implementation, you need the mental model that drives it.

Threat modeling is a structured way to answer four questions:

1. **What are we protecting?** — your *assets*.
2. **Who or what could harm them?** — your *threat actors*.
3. **How could harm occur?** — your *attack vectors*.
4. **What do we do about it?** — your *mitigations*, ranked by risk.

The framework we'll use informally here is **STRIDE**, which categorizes threats by type:

| Letter | Threat Type | Plain meaning |
|--------|-------------|---------------|
| **S** | Spoofing | An entity pretends to be something it's not |
| **T** | Tampering | Data or code is modified without authorization |
| **R** | Repudiation | An action is taken with no audit trail |
| **I** | Information Disclosure | Sensitive data leaks to an unauthorized party |
| **D** | Denial of Service | A resource becomes unavailable |
| **E** | Elevation of Privilege | An entity gains more access than it should have |

We'll map each security control in the implementation plan to one or more of these STRIDE categories. That way, you know *what threat* each control is defending against, not just *that you should do it*.

---

## 1. Asset Inventory

Before defending anything, you must know what you're defending. In your case:

| Asset | Sensitivity | Notes |
|-------|-------------|-------|
| Cryptographic key material (private keys, seeds) | **Critical** | Loss or disclosure is catastrophic and often irreversible |
| Research code and unpublished algorithms | **High** | Intellectual property; could also contain exploitable logic |
| API keys and credentials | **High** | Can be used for impersonation or financial harm |
| Working project files (active Claude session) | **Medium** | Should be accessible to Claude, but scoped tightly |
| Published/public code | **Low** | Already public; still don't want unauthorized tampering |

This inventory drives every decision below. Controls are stricter for higher-sensitivity assets.

---

## 2. Threat Actor Analysis

Who or what might attack this system?

| Actor | Motivation | Capability |
|-------|------------|------------|
| **Prompt injection** (malicious content in files Claude reads) | Hijack Claude's actions | High — Claude reads your codebase |
| **Compromised dependency** (supply chain attack in a package) | Code execution inside the container | Medium |
| **Malicious MCP server** | Exfiltration via a tool call | Medium |
| **Direct attacker** (unlikely for a local workstation) | Full system compromise | Low in a local setup |

This is important: *the primary threat actor is not a human hacker targeting you directly*. It is **indirect compromise via the AI's own capabilities** — Claude being tricked or exploited into doing something harmful using legitimate tools it already has. This is what makes agentic AI security subtly different from traditional application security.

---

## 3. The Layered Defense Architecture

The strategy is **defense in depth**: multiple independent layers, each addressing different STRIDE categories. Defeating all layers simultaneously is much harder than defeating any one.

```
┌─────────────────────────────────────────────┐
│              HOST MACHINE                   │
│                                             │
│  Key material, secrets, sensitive research  │
│  ← never mounted into any container        │
│                                             │
│  ┌───────────────────────────────────────┐  │
│  │           DOCKER CONTAINER            │  │
│  │                                       │  │
│  │  Network: allowlist only              │  │
│  │  Filesystem: project dir only         │  │
│  │                                       │  │
│  │  ┌─────────────────────────────────┐  │  │
│  │  │    NON-ROOT USER (claude-agent) │  │  │
│  │  │                                 │  │  │
│  │  │  Claude Code process runs here  │  │  │
│  │  │  permissions.deny active        │  │  │
│  │  └─────────────────────────────────┘  │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

Each layer maps to specific STRIDE threats:

| Layer | STRIDE threats mitigated |
|-------|--------------------------|
| Container filesystem isolation | **I** (Information Disclosure), **E** (Elevation of Privilege) |
| Container network allowlisting | **I** (exfiltration), **T** (tampering via network) |
| Non-root user inside container | **E** (Elevation of Privilege), **T** (Tampering) |
| `permissions.deny` in Claude Code | **I**, **E** — a third independent gate |
| Secrets never on disk in container | **I** (Information Disclosure) |
| Audit logging | **R** (Repudiation) |

---

## 4. Implementation Plan

### Phase 1 — Authenticate Claude Code on the Host

The host installation serves **one specific purpose**: running the one-time OAuth authentication flow to obtain your Anthropic credentials. It is not used for day-to-day work — the container built in Phase 2 is what actually runs Claude Code.

Install using the current recommended native installer (the npm method is deprecated for host installations):

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

If you prefer to inspect the script before executing it — a reasonable habit for a security-conscious workflow — download it first, read it, then run it:

```bash
curl -fsSL https://claude.ai/install.sh -o install.sh
# review install.sh
bash install.sh
```

Verify the installation, then run the authentication flow:

```bash
claude --version
claude   # follow the OAuth prompts to authenticate
```

Once authenticated, your credentials are stored in `~/.claude/` on the host. These will be injected into containers as environment variables (see Phase 4), so you never need to re-authenticate per session.

**Threat model note:** The host installation is a minimal footprint — you are not using it to process any project files. The container in Phase 2 is what constrains Claude's reach over your actual work.

---

### Phase 2 — Create the Sandbox Image Hierarchy

The sandbox is structured as a hierarchy of Docker images. A shared base image contains everything all project types need. Domain-specific child images inherit from it and add only what their context requires. Each project session mounts only its own directory into the appropriate image.

```
debian:bookworm-slim
    └── claude-base          git, gh, node, npm, python3, sqlite3, Claude Code
            ├── claude-crypto    + openssl, p11-kit, softhsm2, gnutls
            ├── claude-systems   + cmake, gcc/g++, gtest, ninja
            └── claude-research  + texlive, latexmk
```

Web projects (Vite, Vitest, TypeScript) use `claude-base` directly. Those tools are project-level `devDependencies` installed via `npm install` inside `/workspace` — they require nothing additional at the image level.

Docker's layer cache means the base layers are built once and shared on disk across all child images. Storage cost is paid once, not per image.

#### 2.1 — Directory layout

Place all files under `~/.claude-sandbox/`:

```
~/.claude-sandbox/
├── build.sh          — builds all images, or a named target
├── start.sh          — launches a container for a given project
├── ARCHITECTURE.md   — architecture and dependency management reference
├── base/
│   └── Dockerfile
├── crypto/
│   └── Dockerfile
├── systems/
│   └── Dockerfile
└── research/
    └── Dockerfile
```

#### 2.2 — The base Dockerfile

`base/Dockerfile` is the root of the hierarchy. All other images inherit from it via `FROM claude-base`. It contains only what every project type needs: version control, Node.js, Python, SQLite, and Claude Code itself.

Key decisions carried forward from earlier implementation work:

`debian:bookworm-slim` is used instead of `ubuntu:24.04` because Ubuntu pre-creates a user at UID 1000 named `ubuntu`, which conflicts with the `HOST_UID` build argument. Debian slim images do not pre-create any UID 1000 user.

`npm install -g @anthropic-ai/claude-code` is used instead of the native Anthropic installer because the native installer places the binary in `/root/.local/bin/`, which is not on the non-root user's PATH. npm installs to `/usr/local/bin/claude`, which is on PATH for all users. The npm deprecation applies to host installations; inside a Dockerfile it remains correct.

`HOST_UID` is accepted as a build argument and used to create `claude-agent` with a matching UID. When the container user and the bind-mounted project files share the same UID, the Linux kernel treats them as the same owner — no `chown` or privilege escalation needed at runtime.

**Important:** `ARG HOST_UID` must be redeclared in every child Dockerfile. ARG values do not inherit across `FROM` in Docker. Omitting it causes the child image to silently use the default value of `1000` regardless of what was passed at build time.

**Threat model note:** `USER claude-agent` ensures Claude never runs as root. UID matching removes the need for any root operations at container startup. This mitigates **Elevation of Privilege (E)**.

#### 2.3 — The crypto Dockerfile

`crypto/Dockerfile` extends `claude-base` with the full HSM development stack: OpenSSL, p11-kit, SoftHSM2, and GnuTLS.

Two failure modes are explicitly addressed in the crypto image:

**Wrong group ownership.** The `softhsm2` package on Debian creates a group called `ods` and sets `/var/lib/softhsm` to `drwxr-x---` owned by `ods:ods`. The correct access pattern is to add `claude-agent` to the `ods` group and set the token directory to `root:ods 0770`. Adding `claude-agent` to the `root` group instead would grant far broader implicit permissions than needed and is a security smell — the same root cause as the host-level SoftHSM2 permission errors documented in `softhsm2-token-init-error.md`.

**Missing `SOFTHSM2_CONF`.** If `softhsm2-util` cannot locate its config file it prints `ERROR: Failed to enumerate object store` even when the directory exists and permissions are correct. `SOFTHSM2_CONF` is declared using Docker's `ENV` instruction rather than a shell `export`. `ENV` persists into every subsequent build layer and into the running container; a shell export survives only the single `RUN` command it appears in.

#### 2.4 — The systems Dockerfile

`crypto/Dockerfile` extends `claude-base` with the C++ build toolchain: CMake, GCC/G++, Google Test, Ninja, and pkg-config.

`libgtest-dev` on Debian ships source files only — no compiled libraries. The GTest libraries are compiled from source during the image build via `cmake --build` and installed via `cmake --install`. After this, CMake projects can use `find_package(GTest)` without any additional configuration. This is a one-time cost at build time.

#### 2.5 — The research Dockerfile

`research/Dockerfile` extends `claude-base` with the LaTeX document preparation stack: `texlive-latex-extra`, `texlive-fonts-recommended`, `texlive-science`, and `latexmk`. Python and SQLite are available through the base image without reinstallation.

`texlive-latex-extra` covers the vast majority of real-world documents and papers. `texlive-full` (~5 GB) can be substituted if obscure packages are required.

#### 2.6 — Build all images

```bash
cd ~/.claude-sandbox
chmod +x build.sh start.sh
./build.sh
```

Build a single image and its dependencies:

```bash
./build.sh crypto     # rebuilds base first, then crypto
./build.sh systems
./build.sh research
```

You only need to rebuild when you change a Dockerfile or want to pull updated package versions. See `ARCHITECTURE.md` for the full dependency management strategy.

#### 2.7 — Launch script

`start.sh` accepts the project directory as the first argument and the image name as the second. The image name defaults to `base` if omitted.

```bash
./start.sh ~/projects/mylib crypto      # HSM / cryptography work
./start.sh ~/projects/myapp systems     # C++ / CMake projects
./start.sh ~/projects/paper research    # LaTeX documents
./start.sh ~/projects/webapp            # web / Python (uses base)
```

The script validates that the named image exists before attempting to run it, and rejects unknown image names with an actionable error message.

**Threat model note:** `--security-opt=no-new-privileges` prevents any process inside the container from using `setuid` tricks to gain elevated privileges — a direct mitigation against **Elevation of Privilege (E)**. `--cap-drop=ALL` removes all Linux kernel capabilities unnecessary for Claude to function.

#### 2.8 — Set up the restricted Docker network

Create the shared network once. All Claude Code containers use it:

```bash
docker network create \
  --driver bridge \
  claude-net
```

This network is created once and reused by every project container. What varies per project is which endpoints you allow through it via the Squid configuration — not the network itself.

**How to restrict outbound traffic:** Docker does not have a simple built-in allowlist for domains. There are two approaches:

- **`iptables` rules (lower-level):** Write kernel firewall rules that drop packets to any IP outside an allowed set. Effective but requires familiarity with `iptables` syntax and breaks when servers change IPs.
- **Squid forward proxy (recommended):** A small proxy service that all container traffic passes through. The allowlist is a plain-text configuration file listing allowed domains by name. Easier to read, audit, and update. See Phase 2.9 and the companion Squid guide for full implementation details.

Note: Docker's `--add-host` flag is **not** a network restriction mechanism — it only adds static DNS entries to a container's `/etc/hosts` file and does not prevent connections to any destination. Do not use it as a substitute for proper traffic filtering.

**Threat model note:** Network allowlisting is your primary defense against **Information Disclosure (I)** via exfiltration. Without it, a compromised Claude session could transmit your workspace contents to an external server. With the Squid proxy in place, any connection attempt to a non-allowlisted domain is refused before a single byte leaves the container.

#### 2.9 — Add the Squid proxy container

See the companion *Squid Proxy Implementation Guide* for the full setup. In brief, you will run Squid as a second container on the same `claude-net` network, and configure the Claude Code container to route all HTTP/HTTPS traffic through it. The Squid configuration file is your explicit, human-readable allowlist — the single document that defines exactly what outbound connections are permitted.

---

### Phase 3 — Configure Claude Code's Own Permission System

Claude Code has a built-in `permissions.deny` mechanism. This is your third independent layer — it operates at the application level, above the OS and container levels.

Create a `.claude/settings.json` in each project directory:

```json
{
  "permissions": {
    "deny": [
      "Bash(rm -rf *)",
      "Bash(curl *)",
      "Bash(wget *)",
      "Bash(nc *)",
      "Bash(ssh *)",
      "Bash(scp *)",
      "Bash(git remote *)",
      "Bash(git push *)",
      "Write(../*)"
    ]
  }
}
```

Adjust the deny list per project. The key principle: deny by default, grant explicitly.

**Threat model note:** Even if someone crafts a prompt injection that tricks Claude into trying to exfiltrate data via `curl`, this layer rejects the tool call before it reaches the network. This is defense in depth — the network layer would also block it, but you want two gates, not one. This primarily mitigates **Information Disclosure (I)** and **Tampering (T)**.

---

### Phase 4 — Secrets Management

Never place key material or credentials as plaintext files in a project directory that Claude can read. Instead:

**For API keys Claude Code itself needs** (your Anthropic API key), inject them as environment variables at container start, not as files:

```bash
docker run ... \
  --env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  claude-sandbox
```

Your shell reads `ANTHROPIC_API_KEY` from your host environment (where you set it once, securely), and passes it into the container. The key never touches the filesystem inside the container.

**For your research key material**, the rule is simpler: *never mount the directory containing it*. Your `~/.gnupg`, your HSM interface directory, your private key store — these directories are not in `$PROJECT_DIR` and therefore not mounted. The container literally cannot see them. This is the strongest possible control: not a permission check that could be misconfigured, but a physical absence of the data from the container's filesystem namespace.

**Threat model note:** This directly mitigates **Information Disclosure (I)** for your most critical assets. No permission system is needed if the data is simply not present.

---

### Phase 5 — Audit Logging

Address the **Repudiation (R)** threat: you want a record of what Claude did, so you can detect and investigate anomalous behavior.

Enable Docker logging with a persistent log driver by adding these flags to your `docker run` invocation:

```bash
docker run ... \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  ...
```

Claude Code also maintains its own session logs in `~/.claude/logs/` inside the container. Since the container is ephemeral but `/workspace` (your project directory) is persistent, copy logs out before the container exits:

```bash
# Add to your start.sh as a post-run hook:
docker run ... claude-sandbox
# After the container exits:
cp ~/.claude/logs/ "$PROJECT_DIR/.claude-session-logs/$(date +%Y%m%d_%H%M%S)/"
```

The Squid proxy access log (see Phase 2.5 and the companion guide) provides a third audit trail: one line per outbound connection attempted, showing destination, timestamp, bytes, and permit/deny outcome. Any `TCP_TUNNEL` to a domain you did not intentionally allowlist is a red flag worth investigating.

Review all three log sources periodically. Unexpected `curl` calls, writes to unusual paths, or large data transfers are indicators of compromise.

---

### Phase 6 — Operational Habits (Human Layer)

Technology controls fail when humans work around them. These habits complete the picture:

- **One project, one container, one session.** Never reuse a container across projects. Ephemeral containers cannot carry contamination between sessions.
- **Review before confirming.** Claude Code asks for confirmation before destructive operations. Read them. The confirmation step exists because Claude can be wrong or manipulated.
- **Treat injected content as untrusted.** If Claude will read files from external sources (scraped data, downloaded papers, repository clones), those files could contain prompt injections. Be alert to Claude suddenly proposing unusual actions after reading external content.
- **Minimal scope.** Only mount the subdirectory you need for the specific task, not the entire project root if possible.
- **Rebuild the image if you see Git `safe.directory` warnings.** Git refuses to operate on repositories where the directory owner does not match the running user (a security feature since Git 2.35.2). With the `HOST_UID` build argument applied correctly, this warning should never appear. If it does, it means the image was built without the correct UID — rebuild with `--build-arg HOST_UID=$(id -u)`. Do **not** approve the `git config --global --add safe.directory` workaround Claude Code may propose, and always refuse `chmod -R a+w` suggestions — this makes host files world-writable permanently, weakening **Tampering (T)** controls on your actual filesystem.

---

## 5. The Complete STRIDE Coverage Map

| Threat (STRIDE) | Concrete risk in your scenario | Controls that address it |
|-----------------|-------------------------------|--------------------------|
| **Spoofing (S)** | A malicious package pretends to be a legitimate dependency | Pin dependency versions; use a private mirror |
| **Tampering (T)** | Claude modifies files outside the project scope | Container filesystem mount (scope) + `permissions.deny` |
| **Repudiation (R)** | You can't tell what Claude did in a session | Docker logs + Squid access log + Claude Code session logs |
| **Information Disclosure (I)** | Key material or research leaks to external server | Network allowlist (Squid) + secrets never mounted + `permissions.deny` on `curl`/`wget` |
| **Denial of Service (D)** | Runaway Claude process exhausts host resources | `--memory` and `--cpus` limits on the container |
| **Elevation of Privilege (E)** | Claude process gains root or host-level access | Non-root user + UID matching + `--cap-drop=ALL` + `--no-new-privileges` |

---

## 6. On Your Career Integration and Threat Modeling

Yes, what you've been doing intuitively in this conversation *is* threat modeling. More specifically, you've been doing it in the way that translates directly to formal practice:

- Identifying assets and their sensitivity levels → **asset classification**
- Reasoning about who benefits from attacking you → **adversary modeling**
- Evaluating whether a control actually closes a gap → **control analysis**
- Layering independent controls → **defense in depth**, which is a direct analogue of the cryptographic principle that security shouldn't depend on a single assumption

For a cryptographer, the most natural formal extension is **attack trees** — a technique invented by Bruce Schneier in 1999 where you model an attacker's goal as the root of a tree, and the sub-goals they need to achieve as branches. The tree can be annotated with probabilities, costs, or feasibility ratings, turning it into a rigorous mathematical object. Given your background in formal reasoning, you'd find attack trees very natural to work with, and they compose well with the kind of probabilistic and information-theoretic thinking you already do.

The connection to your cryptography research is also direct: many modern protocols (TLS, Signal, WireGuard) are designed by first building a threat model and then proving that the protocol achieves security goals *with respect to that model*. Provable security is threat modeling made formal. The gap between the two fields is smaller than it appears.

---

## Quick Reference Card

```
Start a secure Claude session (pick the image for your project type):
  ~/.claude-sandbox/start.sh ~/projects/mylib    crypto    — HSM / cryptography
  ~/.claude-sandbox/start.sh ~/projects/myapp    systems   — C++ / CMake
  ~/.claude-sandbox/start.sh ~/projects/paper    research  — LaTeX / documents
  ~/.claude-sandbox/start.sh ~/projects/webapp             — web / Python (base)

Build all images (do this once, and after any Dockerfile change):
  cd ~/.claude-sandbox && ./build.sh

Build a single image and its dependencies:
  ./build.sh crypto | systems | research

What is protected:
  ✓ All files outside the mounted project directory  (not mounted)
  ✓ Network destinations outside allowlist           (Squid proxy)
  ✓ Root access inside container                     (non-root user + UID matching)
  ✓ Kernel capabilities                              (--cap-drop=ALL)
  ✓ Specific dangerous commands                      (permissions.deny)
  ✓ Session auditability                             (Docker + Squid + Claude logs)
  ✓ Cross-project contamination                      (per-image isolation)

What is NOT protected by this setup:
  ✗ Vulnerabilities in the Docker engine itself (rare, patch regularly)
  ✗ Files you accidentally mount               (your responsibility)
  ✗ Prompt injections you manually paste in    (stay alert)
```

---

## Changelog

A record of every correction and upgrade made to this document and the
accompanying implementation files, in chronological order.

---

### Change 1 — Installation Method Corrected

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

### Change 2 — Host Installation Reframed

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

### Change 3 — Dockerfile Base Image Changed

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

### Change 4 — `--add-host` Flag Removed

**Affects:** Phase 2.4

**What changed:**
The original plan mentioned Docker's `--add-host` flag as a mechanism for
restricting network connections. This was removed and corrected.

**Why:** `--add-host` adds static entries to a container's `/etc/hosts`
file — it is a DNS convenience tool, not a firewall. It does not prevent
connections to any destination. The section now clearly states that real
outbound restriction requires either `iptables` rules or the Squid proxy.

---

### Change 5 — Network Section Clarified

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

### Change 6 — Entrypoint Script Added (then Superseded)

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

### Change 7 — UID Matching via Build Argument

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

### Change 8 — Git Safe Directory Behaviour Documented

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

### Change 9 — Domain-Specific Toolchain Added to Images
**Affects:** Phase 2 (all sub-sections). Date: 2026-04-09.

**What changed:**
The original plan used a single minimal Dockerfile containing only
`curl`, `git`, `nodejs`, `npm`, and Claude Code. The implementation
files were upgraded to include a full professional toolchain:

- LaTeX (TeX Live): `texlive-latex-extra`, `texlive-fonts-recommended`,
  `texlive-science`, `latexmk`
- Python: `python3`, `python3-pip`, `python3-venv`
- CMake and C++ build tools: `cmake`, `build-essential`, `libgtest-dev`,
  `ninja-build`, `pkg-config`
- Cryptographic / HSM stack: `openssl`, `libssl-dev`, `p11-kit`,
  `p11-kit-modules`, `softhsm2`, `gnutls-bin`
- Database: `sqlite3`, `libsqlite3-dev`
- Version control: `gh` (GitHub CLI, via official apt repository)

GTest requires a separate compilation step on Debian because
`libgtest-dev` ships source only. This is handled at image build time
via `cmake --build` and `cmake --install`.

**Why:** The single minimal image was sufficient for the original
proof-of-concept but did not support real project work. The toolchain
addition was the first step toward the image hierarchy introduced in
Change 10.

**Security posture:** Unchanged. Additional packages increase the
image's attack surface marginally, but all containers remain non-root,
capability-dropped, and network-restricted.

---

### Change 10 — Single Image Replaced by Domain-Specific Image Hierarchy
**Affects:** Phase 2 (restructured entirely). Date: 2026-04-09.

**What changed:**
The single `claude-sandbox` image was replaced by a four-image hierarchy:

```
debian:bookworm-slim
    └── claude-base
            ├── claude-crypto
            ├── claude-systems
            └── claude-research
```

The directory layout changed from a single `Dockerfile` to a structured
set of directories, each with its own `Dockerfile`:

```
~/.claude-sandbox/
├── build.sh
├── start.sh
├── ARCHITECTURE.md
├── base/Dockerfile
├── crypto/Dockerfile
├── systems/Dockerfile
└── research/Dockerfile
```

`start.sh` was updated to accept a second argument selecting the image:
`./start.sh <project_dir> [base|crypto|systems|research]`. It validates
the image name and confirms the image exists before running.

`build.sh` was added to build all images in dependency order, or a
named target plus its dependencies.

Web projects (Vite, Vitest, TypeScript) use `claude-base` directly
because those tools are project-level `devDependencies` installed via
`npm install` in `/workspace` — no separate image is needed.

**Why:** The monolithic image bundled LaTeX, a C++ toolchain, an HSM
stack, and a Python runtime into every container regardless of what the
project actually needed. This violated the principle of least privilege
at the image level: a web project had no reason to carry a PKCS#11
module, and a cryptography project had no reason to carry TeX Live.
Separate images reduce the per-container attack surface and make the
dependency manifest of each container type explicit and auditable.

**ARG inheritance note:** Docker `ARG` values do not inherit across
`FROM`. Each child Dockerfile redeclares `ARG HOST_UID=1000` explicitly.
Omitting this causes the child image to silently use UID 1000 regardless
of the value passed at build time — a silent misconfiguration with no
build error.

**STRIDE mapping:** The hierarchy strengthens **Information Disclosure (I)**
by reducing what tooling is present in any given container. A prompt
injection in a web project cannot invoke PKCS#11 operations because the
relevant libraries are not installed in `claude-base`.

---

### Change 11 — SoftHSM2 Permission and Config Bugs Fixed
**Affects:** `crypto/Dockerfile`. Date: 2026-04-09.

**What changed:**
Two bugs in the initial SoftHSM2 setup were identified and corrected.

**Bug 1 — Wrong group ownership.**
The initial implementation added `claude-agent` to the `root` group to
grant access to the SoftHSM2 token directory. This was replaced with
the correct pattern: add `claude-agent` to the `ods` group (which
`softhsm2` creates on Debian for exactly this purpose), and set the
token directory to `root:ods 0770`. This is structurally identical to
the fix for the same error on a Fedora host machine, documented in
`softhsm2-token-init-error.md`.

**Bug 2 — Missing `SOFTHSM2_CONF`.**
The initial implementation did not set `SOFTHSM2_CONF`. Without it,
`softhsm2-util` falls back to a hardcoded path that may not exist,
producing: `ERROR: Failed to enumerate object store`. The fix uses
Docker's `ENV` instruction rather than a shell `export` because `ENV`
persists into every subsequent build layer and into the running
container. A shell `export` survives only the single `RUN` command
it appears in.

The config file is now written explicitly in the Dockerfile so its
content is auditable from source rather than depending on whatever the
package installer created.

**STRIDE mapping:** Bug 1 fix strengthens **Elevation of Privilege (E)**
by removing an unnecessarily broad group membership. Bug 2 fix is
correctness rather than security, but auditable configuration is a
**Repudiation (R)** control.

---

### Change 12 — Inline Shell Comments Removed from RUN Instructions
**Affects:** All Dockerfiles. Date: 2026-04-09.

**What changed:**
All `#` comments that appeared inside `RUN` command chains (within
backslash-continued lines) were moved above their respective `RUN`
blocks as Dockerfile-level comments.

**Why:** The shell continuation character `\` at the end of a line
means the shell treats the next line as a continuation of the same
command. A `#` character in that context does not reliably start a
comment — behavior varies by shell and context, and commands following
the comment can be silently dropped without a build error. Dockerfile
comments (lines beginning with `#` outside a `RUN`) are parsed by
Docker before any shell is involved and are unambiguously safe.

**Security posture:** No functional change. This is a correctness and
reliability fix that prevents silent command omission during builds.

### Change 13 — Interpreter-Presence Health Check Added to Entrypoint
**Affects:** `base/entrypoint.sh`, `global-claude/CLAUDE.md`, `ARCHITECTURE.md`. Date: 2026-07-04.

**What changed:**
A venv-interpreter presence check was added to `base/entrypoint.sh`, running after the
global-layer injection and before `exec "$@"` on every session start. The check scans
`/workspace` for `.venv` directories (up to `maxdepth 3`) and attempts to execute each
discovered `bin/python3*` binary with `-c ""`. A failure logs a `WARNING` block with the
broken symlink target and a remediation hint; the session continues regardless (warn-only).

Two policy documents were updated in parallel: `global-claude/CLAUDE.md` received an
"Interpreter discipline" section instructing Claude not to create venvs or build artifacts
against ephemerally-installed interpreters; `ARCHITECTURE.md` received a "Boundary with
Strategy A" note at the end of the Strategy B section clarifying that Strategy B is for
evaluation only, not for building durable artifacts.

**Why:** A Python 3.12 venv created during a Strategy B session (`store-transfer-report`,
2026-06-22) persisted to `/workspace`. The next session started from the unmodified
`claude-base` image (Python 3.11 only), leaving the venv's symlink chain broken. The failure
was silent — no existing control surfaced the mismatch until three failed task attempts
localized it. This change converts that silent state into a one-line, timestamped log entry
at a deterministic point on every session start.

**STRIDE mapping (delta only):**

| Threat (STRIDE) | Control added |
|---|---|
| **Repudiation (R)** | Entrypoint stdout log for interpreter-path mismatches, surfaced at the same deterministic point as the global-layer merge log. Converts a silent multi-step-diagnosis failure into a logged event. |

No other STRIDE category is affected. The check is read-only, introduces no new privilege,
no new mount, and no new attack surface.

### Change 14 — CMake and Node.js Native Addon Staleness Checks Added to Entrypoint
**Affects:** `base/entrypoint.sh`, `ARCHITECTURE.md`. Date: 2026-07-06.

**What changed:**
Two additional staleness checks were added to `base/entrypoint.sh`, running after the
interpreter-presence check (Change 13) and before `exec "$@"` on every session start.

1. **CMake build directory check (Tier 1):** scans `/workspace` for `CMakeCache.txt` files
   (up to `maxdepth 4`). For each, reads the `CMAKE_C_COMPILER:FILEPATH=` and
   `CMAKE_CXX_COMPILER:FILEPATH=` entries via `grep` and tests whether those paths are
   executable with `test -x`. A missing or non-executable compiler path logs a `WARNING` block
   with the cache file path, the stale entry, and a `rm -rf` remediation hint.

2. **Node.js native addon check (Tier 2):** scans `/workspace` for `.node` files under
   `node_modules/` (up to `maxdepth 5`). Each discovered file triggers a presence warning
   noting that the addon is ABI-version-dependent and may fail to load if the Node.js version
   in the image has changed. This is a presence warning, not a correctness assertion — full ABI
   verification would require executing the addon or invoking `readelf`, which introduces
   either untrusted code execution or an unacceptable image surface increase.

Both checks are warn-only (consistent with Change 13) and run in all images universally.
`ARCHITECTURE.md` was updated to document all three artifact check tiers and to formally record
the `ldd` hard architectural limit as Tier 3.

**Why:** Same root cause as Change 13: a path-dependent workspace artifact outlives the
container state it was built against. CMake caches encode absolute compiler paths captured at
configure time; a compiler installed ephemerally (Strategy B) leaves those paths dangling.
Node.js native addons encode the ABI version of the Node binary used to compile them; an image
upgrade silently breaks addons compiled against the prior ABI. Neither failure produces a clear
"rebuild me" message at the point of use — both are now surfaced at session start.

**STRIDE mapping (delta only):**

| Threat (STRIDE) | Control added |
|---|---|
| **Repudiation (R)** | Entrypoint stdout log for stale CMake toolchain paths and native addon presence, surfaced at the same deterministic session-start point as Changes 12–13. |
| **Tampering (T)** | CMake check reads `CMakeCache.txt` via `grep` with `IFS= read -r`; path values are passed only to `test -x` and `echo` — neither interprets shell metacharacters. No injection risk from crafted `FILEPATH` values. |

No other STRIDE categories are affected. No new privilege, no new mount, no execution of
workspace-resident code.

---

### Change 15 — Squid Network Egress Proxy Actually Implemented
**Affects:** Phase 2.8–2.9, §5 (STRIDE Coverage Map, delta only). Date: 2026-08-04.

**What changed:**
Phase 2.9 and the companion *Squid Proxy Implementation Guide* described a Squid-based
network egress allowlist, but neither `squid/Dockerfile` nor `squid/squid.conf` was ever
committed to the sandbox repository, and `start.sh` had no proxy lifecycle, no
`HTTP_PROXY`/`HTTPS_PROXY` injection, and no reference to Squid at all — Layer 4 of the
five-layer defense described in §3 was a no-op against the tracked tree. This was closed:
`squid/` is now committed, `build.sh` builds `claude-squid` as a new target, and `start.sh`
starts the proxy before the main container, injects the proxy environment variables into it,
and guarantees teardown via `trap ... EXIT` regardless of how the session ends. Full design
and rationale: `docs/designs/squid-proxy-integration.md`.

Two hardening decisions beyond what Phase 2.8–2.9 originally specified:

- **Fail-closed proxy startup.** If `claude-squid` fails to start, the session aborts rather
  than falling back to unrestricted egress. A control that silently degrades to absent on its
  own failure is the anti-pattern this plan has consistently avoided elsewhere (see Change 12).
- **Non-root, capability-dropped proxy container.** The proxy runs as the `proxy` system
  account (uid/gid 13, a standard Debian `base-passwd` account) rather than root, with
  `--cap-drop=ALL`/`--security-opt=no-new-privileges` on its own invocation — consistent with
  the treatment already given to every other container in this architecture.

**Why:** Surfaced by `test_squid_isolation.bats` (Group 3, S-1–S-3) failing at `setup_file()`
because the files it depends on did not exist in the tracked tree. Network egress allowlisting
is named in §3 and Phase 2.8 as the primary control against Information Disclosure via
exfiltration; until this change, that control was documentation only.

**STRIDE mapping (delta only):**

| Threat (STRIDE) | Control added |
|---|---|
| **Information Disclosure (I)** | Squid allowlist actually built, wired into `build.sh`/`start.sh`, and enforced via `HTTP_PROXY`/`HTTPS_PROXY` injection — previously documented but not present in the tracked tree. Residual, accepted risk: any allowlisted domain remains a potential blind exfiltration channel, since Squid sees only the CONNECT tunnel for HTTPS, not its contents. |
| **Repudiation (R)** | Squid access log (`access_log stdio:/dev/stdout combined`) actually active and captured by Docker's default log driver, joining the Docker and Claude Code session logs named in Phase 5. |
| **Elevation of Privilege (E)** | Non-root execution inside the proxy container; `--cap-drop=ALL`/`--security-opt=no-new-privileges` on the proxy's own runtime invocation. Not present in the original guide. |
| **Denial of Service (D)** | Fail-closed proxy startup is a deliberate, bounded availability cost accepted in exchange for not silently degrading the egress control on proxy failure. |

No other STRIDE category in §5 changes as a result of this work.

---

### Change 16 — Container Engine Migrated from Docker to Rootless Podman/WSL2
**Affects:** Scope, Phase 5 (Audit Logging), §5 (STRIDE Coverage Map, delta only). Date: 2026-08-10.

**What changed:**
`build.sh` and `start.sh` now route every build/run invocation through `$ENGINE`
(default `podman`, rootless under WSL2; `ENGINE=docker` selects Docker instead — fully
supported as a fallback). Three changes travel with the engine swap:

- **Runtime UID matching for the Podman path.** The main session container now adds
  `--userns=keep-id:uid=1000,gid=1000` under Podman, remapping the image's fixed
  `claude-agent` UID onto the actual invoking host UID at run time. The Docker path is
  unchanged — it still matches UID at build time via `HOST_UID` (Change 7).
- **Explicit, size-capped log drivers on both containers, both engines.**
  `--log-driver json-file --log-opt max-size=... --log-opt max-file=...` is now present
  on the proxy container (closing the hygiene gap noted but not implemented in
  `squid-proxy-integration.md` §6.2-R/§9) and on the main session container (closing
  the gap between this document's Phase 5 and the tracked `start.sh`, noted in the same
  Squid SDD passage). Pinned to `json-file` on both engines deliberately, rather than
  relying on differing per-engine defaults.
- **`base/Dockerfile`'s `FROM debian:bookworm-slim` is now digest-pinned**, closing the
  repo-wide gap the Squid SDD deferred to this migration (§5.1).

Full design and rationale: `docs/designs/podman-migration.md`.

**Why:** Podman is daemonless — no root-owned `dockerd` process runs on the host, unlike
even "rootless" Docker's typical desktop configuration. This closes a root-daemon attack
surface this document did not previously address. The Squid sibling-container proxy
pattern (`claude-proxy-$$` on `claude-net`) had never been exercised under anything but
Docker's bridge network; `squid-proxy-integration.md` §7.4 explicitly flagged this as
unvalidated, not merely unmigrated, and deferred its resolution to this change. It is now
confirmed: `ENGINE=podman bats tests/` passes in full, including
`test_squid_isolation.bats` S-1–S-3 under `slirp4netns`.

**STRIDE mapping (delta only):**

| Threat (STRIDE) | Control added or changed |
|---|---|
| **Spoofing (S)** | Sibling-container name resolution for `claude-proxy-$$` confirmed functional under `slirp4netns` (`test_squid_isolation.bats` S-1–S-3 green under `ENGINE=podman`) — previously an open, explicitly unvalidated question. |
| **Tampering (T)** | No change. `squid.conf` remains baked into the image at build time; out of scope for this migration. |
| **Repudiation (R)** | Explicit `--log-driver`/`--log-opt` now present on both the proxy and the main session container, on both engines — closes two previously-flagged gaps (see "What changed"). |
| **Information Disclosure (I)** | No change to the allowlist mechanism itself; confirmed to still hold under the new networking backend by the same S-1–S-3 gate. |
| **Denial of Service (D)** | Fail-closed proxy startup unchanged. Residual, not yet closed: `--memory`/`--cpus` enforcement on the main container depends on cgroups v2 delegation under rootless Podman, which is not exercised by the automated suite — manual confirmation (attempt to exceed `--memory`, observe an OOM-kill) is a tracked action item, not yet performed. **Resolved — see Change 17**, which found this gap genuinely present and fixed it. **Change 18** found and closed a second, narrower gap in the same area: Podman's own OOM *reporting* (not enforcement) is unreliable under this host's cgroup layout. |
| **Elevation of Privilege (E)** | Primary contribution of this change: no root-owned daemon process on the host. `--cap-drop=ALL`/`--security-opt=no-new-privileges` retained unchanged on both containers, on both engines — under rootless Podman these now defend against within-namespace capability gain rather than a host-root escape, which rootless execution already prevents structurally. Runtime UID matching via `--userns=keep-id` (Podman path only) replaces build-time `HOST_UID` matching (Change 7) for that path only; the Docker path is unchanged. |

No other STRIDE category in §5 changes as a result of this work.

---

### Change 17 — cgroups v2 Memory Delegation Gap Found and Fixed
**Affects:** Change 16 (Denial of Service row), `BUILDING.md`. Date: 2026-08-11.

**What changed:**
Change 16 flagged, but had not yet confirmed, that `--memory`/`--cpus` enforcement on
the main session container depends on cgroups v2 delegation under rootless Podman. The
operator ran the manual smoke test that entry called for (exceed `--memory=100m`,
expect an OOM-kill) and reproduced exactly the predicted failure mode: the process was
killed (`exit 137`), but `podman inspect --format '{{.State.OOMKilled}}'` reported
`false`.

Root cause: WSL2's default `user@.service` does not delegate the `memory` cgroup
controller down to the user's own session by default — present in
`/sys/fs/cgroup/cgroup.controllers` (machine-wide availability) but absent from
`/sys/fs/cgroup/user.slice/user-<uid>.slice/cgroup.subtree_control` (delegated
availability). Without delegation, the container's own `memory.max` is never actually
wired up; the SIGKILL that was observed came from a different, unscoped boundary, which
is also why it was never recorded against the container's own cgroup. `BUILDING.md`'s
original Podman-prerequisites check only verified machine-wide availability — necessary
but not sufficient — and has been corrected to check the actual delegation chain.

Fix: a `Delegate=memory pids cpu io` drop-in for `user@.service`
(`/etc/systemd/system/user@.service.d/delegate.conf`), requiring a full WSL2 restart to
take effect (documented in `BUILDING.md`).

**Why:** `--memory`/`--cpus` silently becoming no-ops is a Denial-of-Service-relevant
regression from the Docker path's previously-working behavior, and — more subtly — a
resource limit that Podman's own tooling reports as never having fired is exactly the
kind of silently-degraded control this plan has consistently treated as unacceptable
elsewhere (Change 12, `squid-proxy-integration.md` §6.3).

**STRIDE mapping (delta only):**

| Threat (STRIDE) | Control added |
|---|---|
| **Denial of Service (D)** | `--memory`/`--cpus` enforcement on the main session container now actually holds under rootless Podman/WSL2, closing the item Change 16 left open. Regression-tested going forward by `tests/test_runtime_posture.bats` R-6, so environment drift (e.g. a delegation drop-in lost across a host rebuild) is caught by `bats tests/` rather than requiring another manual smoke test. |

No other STRIDE category in §5 changes as a result of this work.

---

### Change 18 — Podman's `conmon` OOM Marker File Written to the Wrong Directory
**Affects:** Change 16 and Change 17 (Denial of Service row), `tests/test_runtime_posture.bats`. Date: 2026-08-13.

**What changed:**
After the Change 17 delegation fix, the operator re-ran R-6 and it still failed — but on
a different assertion than before, indicating a different underlying cause. Diagnosis
this time ruled *enforcement* fully in:

- `memory.max` on the container's actual leaf cgroup
  (`.../user@<uid>.service/user.slice/libpod-<id>.scope/container/memory.max`) correctly
  reflects the configured `--memory` limit.
- Kernel `dmesg` records a genuine `Memory cgroup out of memory: Killed process ...`
  entry for the offending process, with `anon-rss` consistently pinned near the
  configured limit — airtight, engine-independent proof the kernel enforced it.

But `podman inspect --format '{{.State.OOMKilled}}'` remains `false`. Investigating why
turned up an unrelated-looking clue: an empty file literally named `oom` appearing in
the operator's working directory after every R-6 run. That file is the actual
mechanism Podman uses for OOM bookkeeping — `conmon` (the per-container monitor
process) watches the container's `memory.events` file itself, and when it observes
`oom_kill` increment, it writes an empty `oom` marker file as a record of that; `podman
inspect`/`wait` later check for that marker's presence at the container's expected
exit/state directory to populate `.State.OOMKilled`. So `conmon` **did** correctly
detect the kill — the marker file being created at all is proof of that. The bug is
that under this host's rootless setup, the marker lands in `conmon`'s own current
working directory (wherever `podman run` was invoked from) rather than the container's
real exit/state directory, so Podman's own inspect logic checks the correct path,
finds nothing there, and reports `false`. This is a path-resolution bug in *where the
evidence gets written*, not a failure to detect the OOM, and not a cgroups delegation
issue — no further delegation configuration fixes it (Change 17's fix was already
correct and complete).

Fix: `tests/test_runtime_posture.bats` R-6 no longer asserts on `.State.OOMKilled`.
It asserts only on `exit 137`, the one signal already confirmed (via `dmesg`) to
reliably indicate a genuine cgroup-triggered kill in this environment.

**Why:** Chasing further cgroups configuration would not have closed this gap — the
kernel enforcement was already correct, and the failure was purely in where `conmon`
happened to write its own bookkeeping file. Asserting on a summary field that's proven
unreliable under this host's layout would make R-6 either permanently red (masking a
passing control) or, worse, tempt a future change to weaken the test to "pass" rather
than reflecting reality. Asserting on the kernel-verified signal instead keeps the test
meaningful. Same rationale as the R-2 fix earlier on this branch: prefer ground truth
(kernel state, `/proc`) over an engine's own inspect metadata whenever the two diverge.

**STRIDE mapping (delta only):**

| Threat (STRIDE) | Control added |
|---|---|
| **Denial of Service (D)** | No change to the actual control — `--memory` enforcement was already correct (Change 17), and `conmon` does correctly detect the OOM kill. This closes a test-fidelity gap: R-6 now asserts on a signal (kernel exit code, cross-checked manually via `dmesg`) that is actually reliable under this host's cgroup layout, instead of a Podman-reported field left stale by a `conmon` marker-file path bug. |

No other STRIDE category in §5 changes as a result of this work.

---

### Change 19 — Podman SELinux Mount-Labeling Gap on `/workspace`
**Affects:** Change 16 (`start.sh` mount invocations), `docs/designs/podman-migration.md` §6.2 (Tampering) and §9, `BUILDING.md`, `tests/test_runtime_posture.bats`. Date: 2026-08-14.

**What changed:**
An operator reported that from inside a running session, `/workspace` and every file
under it were unreadable and unwritable — `ls`, `stat`, `cat`, and the Write tool's temp
file all failed with `EACCES`, even though the path was owned by `claude-agent` (uid
1000) with mode `0755`. Investigation found the operator's host filesystem is `btrfs`
mounted with the `seclabel` option — SELinux is enforcing at the kernel level. Podman
does not automatically relabel bind-mounted host directories: unless a mount is
explicitly relabeled, it keeps its original SELinux context, and the container's
type-enforcement policy denies access to it regardless of correct POSIX bits — a
mandatory-access-control layer that sits above standard Unix permissions and is
invisible to `stat`/`ls -la`.

`start.sh`'s three `--mount type=bind,...` invocations (`/workspace`,
`/run/claude-global`, `/run/claude-overlay`) have never carried a relabel option — the
mount block is byte-identical from before Change 16 through the merged Podman
migration. This was a latent gap the whole time; it simply never mattered under the
prior Docker-only default, and only became symptomatic once Change 16 flipped the
default engine to Podman on an SELinux-enforcing host. `podman-migration.md` never
analyzed volume labeling as a Docker→Podman delta, so it wasn't caught in that review.

Fix: `start.sh` now appends `,relabel=shared` to all three `--mount type=bind,...`
strings, gated on `ENGINE=podman` (Docker's `--mount` has no relabel suboption — only
the legacy `-v host:container:z` syntax does — so the Docker fallback path is
unchanged). `shared` (Podman's `:z`) was chosen over `private` (`:Z`): `GLOBAL_BASE`/
`GLOBAL_OVERLAY` are mounted by every concurrent session by design, and `/workspace`
itself can be mounted by two sessions against the same project directory — `private`
relabeling assigns an exclusive MCS category per container and is documented to
invalidate a prior container's access when a second container relabels the same host
path, which `shared` avoids. On a host where SELinux isn't enforcing, Podman's relabel
logic is a no-op, so this is safe to apply unconditionally under `ENGINE=podman`.

**Why:** `EACCES` on the project root makes the sandbox entirely unusable, not merely
less secure — this is a fail-shut usability break masquerading as a permissions bug,
discovered only because an operator happened to be running on an SELinux-enforcing
host. `relabel=shared` does have a real cost worth stating plainly: it drops these
paths to the generic, non-exclusive `container_file_t` context, removing SELinux
MCS-based isolation between claude-sandbox sessions and any other container on the
host also using shared context. This is accepted because SELinux MCS separation was
never the primary isolation boundary for these paths — `--cap-drop=ALL`, non-root
execution, `--security-opt no-new-privileges`, and per-session mount namespacing
already do that work (§3, Layered Defense Architecture); SELinux relabeling here
restores basic access, it doesn't newly rely on SELinux as the load-bearing control.

**Residual, not yet closed:** the Scope section above lists rootless Docker on Fedora
(also commonly SELinux-enforcing) as a fully supported fallback via `ENGINE=docker`.
The same underlying bug is presumed to still be present on that path — Docker's
`--mount` has no equivalent to `relabel=`, so fixing it would mean diverging the
mount-construction mechanism per engine (e.g. switching Docker to the legacy `-v
...:z` form). Tracked as an open question in `podman-migration.md` §9, not fixed here.

**STRIDE mapping (delta only):**

| Threat (STRIDE) | Control added |
|---|---|
| **Tampering (T)** | Bind mounts are now genuinely accessible under Podman on SELinux-enforcing hosts, closing an unintended over-restriction. Trade-off: `relabel=shared` removes SELinux MCS-based isolation on these specific paths from other shared-context containers on the host — accepted per the "Why" rationale above, since capability-drop/non-root/no-new-privileges/mount-namespacing remain the primary boundary. Regression-tested going forward by `tests/test_runtime_posture.bats` R-7/R-8 (skipped, not silently passed, on non-SELinux-enforcing hosts). |
| **Denial of Service (D)** | Restores basic sandbox availability on affected hosts; not a new DoS control. |

No other STRIDE category in §5 changes as a result of this work. The Docker-path
residual noted above remains open.
