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

### Phase 1 — Install Claude Code on the Host (optional)

The host installation is not used for day-to-day work — the container built in Phase 2 is what actually runs Claude Code — and it is not how a session authenticates either. See Change 23: an earlier version of this phase said the host's credentials are injected into containers, and nothing has ever done that. Keep the host install if you want a Claude Code to compare versions against or to use outside the sandbox; skip it otherwise. Authentication is covered at the end of Phase 4.

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

Credentials obtained this way are stored in `~/.claude/` on the host, and stay there. `start.sh` does not mount `~/.claude` and does not pass an API key, so a host login has no effect on any session.

**Threat model note:** The host installation is a minimal footprint — you are not using it to process any project files. The container in Phase 2 is what constrains Claude's reach over your actual work. That the host credential never reaches a container is a property worth keeping: it is one fewer place the sandbox can leak from, not an inconvenience to be engineered away.

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

The path is load-bearing and is not interchangeable with `settings.json` at the project root — a rule declared there is never read. See Change 22; this repository had it in the wrong place from the start, and the layer was inert until 2026-09-04. `./check-auto-memory.sh deny-path` is the check that tells the two apart.

**Threat model note:** Even if someone crafts a prompt injection that tricks Claude into trying to exfiltrate data via `curl`, this layer rejects the tool call before it reaches the network. This is defense in depth — the network layer would also block it, but you want two gates, not one. This primarily mitigates **Information Disclosure (I)** and **Tampering (T)**.

---

### Phase 4 — Secrets Management

Never place key material or credentials as plaintext files in a project directory that Claude can read. Instead:

**How a session authenticates, in this project:** interactively, from inside the container. You run `./start.sh`, and the first thing you do in the session is log in through Claude Code's own OAuth flow. No Anthropic credential is passed into a container by any path.

**How a session gets its other credentials:** from a per-project store, encrypted at rest on the host with `age` and decrypted by `start.sh` at launch. Values reach the container the way `GH_TOKEN` always has — `-e NAME`, name only, so no value appears in host argv, in `ps`, or in shell history. An ambient `GH_TOKEN` in the launching shell is still forwarded, so the old path keeps working; the store is where the value should come from instead. See `docs/designs/0129-encrypted-credential-store.md`, and `creds.sh` for managing it.

Three properties are worth stating because they are what the design buys:

- **The store is never mounted.** It lives outside this repository by default, for the reason given at the end of this phase: a store inside it would be bind-mounted at `/workspace` by any session opened on claude-sandbox itself. `start.sh` aborts rather than launching if the resolved store lies inside the project directory.
- **Failure is closed, except where silence is the existing contract.** A project with no credential file starts silently, exactly as before. A file that is present but cannot be decrypted aborts the session, as does a missing `age` binary — a silent skip there would be indistinguishable from having no credentials at all.
- **What the store holds is a policy question, not a capability one.** The mechanism moves arbitrary bytes into an environment variable. `docs/designs/0129-encrypted-credential-store.md` §Sensitivity tiering policy is what decides whether a given credential belongs in it, and SSH private keys are named there as a tier that does not.

**What this does not do:** it does not stop the agent reading the value. A decrypted credential lands in the container's environment, where `echo $NAME` reaches it and `podman inspect` shows it. That is unchanged from `GH_TOKEN`'s exposure before this existed, and it is accepted knowingly rather than solved — see Change 26's residual list, and the proxy-substitution follow-up named there.

Two consequences follow, and neither is a defect:

- **A login does not survive the session.** Containers run with `--rm` and `~/.claude` inside them is not persisted anywhere, so every session begins with a login. This is the cost of ephemerality, paid knowingly.
- **The host's Anthropic credential is never in the container.** There is no API key in the container's environment, no credential file mounted from the host, and nothing in `start.sh` that could put one there. The credential store above does not change this: it forwards project credentials, and the identity protecting it never leaves the host process.

**On the API-key alternative:** Claude Code also accepts `ANTHROPIC_API_KEY` from the environment, and an earlier version of this document presented that as the mechanism:

```bash
docker run ... --env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" claude-sandbox
```

This project does not do that, and never did. It is recorded here as a road not taken rather than deleted, because it is a genuine option with a different trade: it removes the per-session login, and in exchange puts a long-lived credential into container environment state, readable by any process in the container and visible in the engine's inspect output. Adopting it would be a change to the launch path and would need its own STRIDE analysis. It is also a different billing and trust model — API-key access is not the subscription the interactive flow uses.

**For your research key material**, the rule is simpler: *never mount the directory containing it*. Your `~/.gnupg`, your HSM interface directory, your private key store — these directories are not in `$PROJECT_DIR` and therefore not mounted. The container literally cannot see them. This is the strongest possible control: not a permission check that could be misconfigured, but a physical absence of the data from the container's filesystem namespace.

The credential store obeys the same rule, and it is the rule that placed it. An earlier scoping put it in a `credentials/` directory inside this repository, gitignored. That is safe until someone opens a session on claude-sandbox itself, which is routine — `$PROJECT_DIR` is then the repository, and the store is mounted at `/workspace/credentials` with the wrapped identity and the project index beside the ciphertext. `.gitignore` governs tracking; the exposure here is mounting. Defaulting the store outside the repository restores physical absence, and the in-mount abort in `start.sh` turns an operator override into a refusal rather than a silent leak.

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
accompanying implementation files, in chronological order. The entries
themselves — each with its STRIDE delta and its residual list — are in
[`claude-code-security-plan-changelog.md`](claude-code-security-plan-changelog.md).

This index carries the number and title of each, so that a citation of the
form "Change 19" still lands somewhere that names what Change 19 was. Tracked
files across this repository cite changes by number, including `start.sh` and
three files under `tests/`.

| # | Change |
|---|---|
| 1 | Installation Method Corrected |
| 2 | Host Installation Reframed |
| 3 | Dockerfile Base Image Changed |
| 4 | `--add-host` Flag Removed |
| 5 | Network Section Clarified |
| 6 | Entrypoint Script Added (then Superseded) |
| 7 | UID Matching via Build Argument |
| 8 | Git Safe Directory Behaviour Documented |
| 9 | Domain-Specific Toolchain Added to Images |
| 10 | Single Image Replaced by Domain-Specific Image Hierarchy |
| 11 | SoftHSM2 Permission and Config Bugs Fixed |
| 12 | Inline Shell Comments Removed from RUN Instructions |
| 13 | Interpreter-Presence Health Check Added to Entrypoint |
| 14 | CMake and Node.js Native Addon Staleness Checks Added to Entrypoint |
| 15 | Squid Network Egress Proxy Actually Implemented |
| 16 | Container Engine Migrated from Docker to Rootless Podman/WSL2 |
| 17 | cgroups v2 Memory Delegation Gap Found and Fixed |
| 18 | Podman's `conmon` OOM Marker File Written to the Wrong Directory |
| 19 | Podman SELinux Mount-Labeling Gap on `/workspace` |
| 20 | Commit-msg Hook Drift Detection at Session Start |
| 21 | Hooks Directory Resolved Instead of Assumed |
| 22 | Deny List Moved to the Path Claude Code Actually Reads |
| 23 | Documented Credential Flow Replaced With the Real One |
| 24 | Planning-Research Tier Added to the Squid Allowlist |
| 25 | `bats` Added to the Base Image and Pinned in Both Places |
| 26 | Per-Project Encrypted Credential Store |
