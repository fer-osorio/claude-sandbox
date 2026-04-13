# AGENTS.md — Dependency Management for the Claude Sandbox

A reference for managing the toolchain in the claude-sandbox image hierarchy.

---

## Image Hierarchy

The sandbox is structured as a hierarchy of Docker images. Each image adds
only what its domain requires. Docker's layer cache means the base layers are
built once and shared on disk across all child images — you pay the storage
cost once, not per image.

```
debian:bookworm-slim
    └── claude-base          git, gh, node, npm, python3, sqlite3, Claude Code
            ├── claude-crypto    + openssl, p11-kit, softhsm2, gnutls
            ├── claude-systems   + cmake, gcc/g++, gtest, ninja
            └── claude-research  + texlive, latexmk
```

Web projects (Vite, Vitest, TypeScript) use **claude-base** directly. Vite
and Vitest are project-level devDependencies installed via `npm install`
inside /workspace — they don't need a dedicated image.

### Directory layout

```
~/.claude-sandbox/
├── build.sh          — builds all images (or a named target)
├── start.sh          — launches a container for a given project
├── base/
│   └── Dockerfile
├── crypto/
│   └── Dockerfile
├── systems/
│   └── Dockerfile
└── research/
    └── Dockerfile
```

### Build all images (do this once, and after any Dockerfile change)

```bash
cd ~/.claude-sandbox
./build.sh
```

Build a single image and its dependencies:

```bash
./build.sh crypto     # rebuilds base first, then crypto
./build.sh systems
./build.sh research
```

---

## The Core Mental Model

Docker images are immutable snapshots. When you run a container, you get a
perfectly reproducible copy of the image — every time, on every machine.
This is the property that makes the security guarantees in
`claude_code_security_plan.md` meaningful: there's nothing to drift, nothing
to accidentally update, no state from a previous session that can carry
contamination forward.

Dependency management in Docker is really the question of *where* in the
lifecycle a tool gets installed:

| When | Mechanism | Survives restart? | Reproducible? |
|------|-----------|-------------------|---------------|
| Build time | Dockerfile RUN | Yes — baked into image | Yes |
| Runtime (ephemeral) | apt-get inside container | No | N/A |
| Runtime (persistent) | docker commit | Yes | No ✗ |

The right answer for most tools is **build time**. The ephemeral pattern is
useful for experimentation. The persistent-runtime pattern should be avoided
— it trades away reproducibility for convenience, which is the wrong trade
for a security-sensitive sandbox.

---

## Strategy A — Rebuild the Image (Recommended Default)

**The workflow:**

1. Decide which image the tool belongs in. Ask: which project types need it?
   - All projects → `base/Dockerfile`
   - Cryptography projects only → `crypto/Dockerfile`
   - C++ projects only → `systems/Dockerfile`
   - LaTeX/research projects only → `research/Dockerfile`
2. Add the package to the appropriate `apt-get install` block.
3. Rebuild:
   ```bash
   ./build.sh             # rebuild everything
   ./build.sh crypto      # rebuild only base + crypto
   ```
4. Start a new session. The tool is available.

**Why this is the right default:**

- The image remains fully reproducible from source.
- Layer caching makes most rebuilds fast. Docker only re-executes layers
  that come after the first changed line. Adding one apt package to an
  existing block typically takes 30–90 seconds on a warm cache.
- The Dockerfile hierarchy is your dependency manifest — a set of plain
  text files that describe exactly what is in each image.

**Where to add things:**

If a tool requires a third-party apt repository, follow the pattern in
`base/Dockerfile` LAYER 2 (GitHub CLI) — add a new named layer with the
keyring setup, then the `apt-get install`.

If it's a pip package:
```dockerfile
RUN pip3 install --break-system-packages <package>
```
The `--break-system-packages` flag is required on Debian bookworm because
pip is managed alongside the system Python.

If it's an npm global tool, add it to the `npm install -g` invocation in
`base/Dockerfile` LAYER 3, or add a new `RUN npm install -g <pkg>` line.

---

## Strategy B — Ephemeral Install (Experiment First)

You need a tool for a task but aren't sure if you'll keep it. Install it
inside the running container to evaluate it, without touching any image.

The container runs as `claude-agent`, a non-root user, so you can't run
`apt-get` directly from the Claude session. Open a second shell into the
same running container as root from your host:

```bash
# From your host, while the container is running:
docker exec -u root -it <container-name> bash

# Now install:
apt-get update && apt-get install -y <package>
```

The Claude session in the other terminal gains access to the tool
immediately — no restart needed. When the container exits, the installation
disappears. If it was useful, add it to the appropriate Dockerfile and rebuild.

**Security note:** `docker exec -u root` runs as root inside the container's
namespace — it does not affect your host. This is an acceptable
operator-level action for your own sandbox. Claude Code itself never has
root access.

---

## Cheat Sheet

```
Start a session (pick the right image for your project type):
  ./start.sh ~/projects/myproject crypto      — HSM / cryptography work
  ./start.sh ~/projects/myproject systems     — C++ / CMake projects
  ./start.sh ~/projects/myproject research    — LaTeX documents
  ./start.sh ~/projects/myproject base        — Python, web, TypeScript

Add a tool permanently:
  Edit the appropriate Dockerfile, add to the relevant layer
  ./build.sh [base|crypto|systems|research]

Try a tool without committing:
  docker exec -u root -it <container-name> bash
  apt-get update && apt-get install -y <tool>

Update all apt packages to latest versions:
  ./build.sh --no-cache     (add --no-cache to force fresh apt-get update)
  or: docker build --no-cache ... for a specific image

Inspect what's installed in an image:
  docker run --rm claude-crypto dpkg -l
  docker run --rm claude-base pip3 list
  docker run --rm claude-base npm list -g --depth=0
```

---

## What Not to Do

**`docker commit`** saves a running container as a new image. Avoid it:

- The result is not reproducible from source. You can't see what was
  installed or when from the image alone.
- It bypasses the Dockerfile hierarchy as the single source of truth.
- It accumulates layers without the cleanup a proper RUN layer includes
  (the `rm -rf /var/lib/apt/lists/*` step), so committed images grow
  unnecessarily.
- It breaks the auditability of your build process — a committed image
  has no manifest.

The ephemeral install pattern (Strategy B) gives you the same in-session
flexibility without any of these downsides.
