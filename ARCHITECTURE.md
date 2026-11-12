# ARCHITECTURE.md — Architecture and Dependency Management

A reference for the claude-sandbox image hierarchy and toolchain.

---

## Image Hierarchy

The sandbox is structured as a hierarchy of container images, built and run
via `build.sh`/`start.sh`. Each image adds only what its domain requires. The
engine's layer cache means the base layers are built once and shared on disk
across all child images — you pay the storage cost once, not per image.

Both scripts route through `$ENGINE` (default `podman`, rootless under
WSL2; `ENGINE=docker` selects Docker instead). Examples in this document use
`docker` for the commands run directly against a container (`exec`, ad-hoc
`run`), since that's the longer-standing precedent — substitute `podman` if
that's your active engine. See `BUILDING.md` for Podman-specific setup and
`docs/designs/0025-podman-migration.md` for the full engine-swap design.

```
debian:bookworm-slim
    └── claude-base          git, gh, node, npm, python3, Claude Code
            └── claude-crypto    + openssl, p11-kit, softhsm2, gnutls
```

Web projects (Vite, Vitest, TypeScript) use **claude-base** directly. Vite
and Vitest are project-level devDependencies installed via `npm install`
inside /workspace — they don't need a dedicated image.

### Combinations

A project that needs two child profiles uses a named combination rather than
a Dockerfile of its own. `config.sh`'s `COMBOS` maps a name to an ordered
member list; `./build.sh <name>` builds base, the first member, then each
later member on the previous result, and `./start.sh` accepts the name
wherever it accepts a profile:

```
claude-base
    └── claude-<first member>
            └── claude-<combination>:part-2      (three or more members only)
                    └── claude-<combination>
```

Order is build order: files and `ENV` values set by a later member win.
`config.local.sh` may add a combination but not redefine a committed one. A
combination whose member has an overlay (`global-<member>/`) is refused until
overlays can be merged. No combination is committed yet, because `crypto` is
the only child profile. Full design:
[`docs/designs/0194-profile-composition.md`](docs/designs/0194-profile-composition.md).

### Directory layout

```
~/.claude-sandbox/
├── build.sh                  — builds all images (or a named target)
├── start.sh                  — launches a container for a given project
├── config/
│   ├── config.sh               — profile list, image prefix, engine default,
│   │                              resource/log-driver values, project
│   │                              registry (committed)
│   ├── config.local.sh.example — template for per-machine overrides (committed)
│   └── config.local.sh         — per-machine overrides (gitignored, absent
│                                  until created)
├── lib/
│   └── config.sh               — loads the two config layers and the registry
├── profiles/
│   ├── base/
│   │   └── Dockerfile
│   └── crypto/
│       └── Dockerfile
└── tests/            — bats-core integration test harness (see BUILDING.md)
```

`build.sh` and `start.sh` both load `config/config.sh` (then
`config/config.local.sh`, if present) through `lib/config.sh` rather than
hardcoding the profile list or runtime values themselves. A `config.local.sh`
left at the repository root, where it lived before #189, aborts the launch.
Precedence, later wins: hardcoded fallback in the scripts < `config.sh` <
`config.local.sh` < a matching env var at call time (e.g.
`ENGINE=docker ./start.sh ...`). Full design rationale:
[`docs/designs/0028-sandbox-config-file.md`](docs/designs/0028-sandbox-config-file.md).

`config.sh` also carries a named project registry — `PROJECT_PATH` /
`PROJECT_PROFILE`, addressed from `start.sh` as `@<name>` (e.g.
`./start.sh @mylib` in place of `./start.sh ~/projects/mylib crypto`).
`config.local.sh` may add entries for names `config.sh` doesn't already
have (a personal or scratch project not worth a reviewed commit); it may
not redefine one that's already there — `start.sh` reverts such an
attempt and warns. Full design rationale:
[`docs/designs/0030-named-project-registry.md`](docs/designs/0030-named-project-registry.md).

### Build all images (do this once, and after any Dockerfile change)

```bash
cd ~/.claude-sandbox
./build.sh
```

Build a single image and its dependencies:

```bash
./build.sh crypto     # rebuilds base first, then crypto
```

---

## The Core Mental Model

Docker images are immutable snapshots. When you run a container, you get a
perfectly reproducible copy of the image — every time, on every machine.
This is the property that makes the security guarantees in
`claude-code-security-plan.md` meaningful: there's nothing to drift, nothing
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
   - All projects → `profiles/base/Dockerfile`
   - Cryptography projects only → `profiles/crypto/Dockerfile`
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
`profiles/base/Dockerfile` LAYER 2 (GitHub CLI) — add a new named layer with the
keyring setup, then the `apt-get install`.

If it's a pip package:
```dockerfile
RUN pip3 install --break-system-packages <package>
```
The `--break-system-packages` flag is required on Debian bookworm because
pip is managed alongside the system Python.

If it's an npm global tool, add it to the `npm install -g` invocation in
`profiles/base/Dockerfile` LAYER 3, or add a new `RUN npm install -g <pkg>` line.

**Adding an entirely new profile** (not just a tool inside an existing
one) is a different, smaller step since the Podman migration: create the
`profiles/<profile>/Dockerfile`, then register the profile in
`config/config.sh` (add it to `PROFILES`, and to `PROFILE_BASE` if it builds
on top of `base`).
`build.sh` and `start.sh` both pick it up automatically — no other file
needs editing. The Dockerfile must follow the profile contract, which C-41
checks: it is built on `${PARENT_IMAGE}`, brackets its root work with
`USER root` and `USER claude-agent`, sets no `ENTRYPOINT` or `CMD`, and
extends `PATH` ([ADR 014](docs/adr/014-the-profile-contract.md)). A profile
that follows it can be a combination member. Add its smoke command to
`tests/lib/profiles.bash`, which T-4 runs for each combination's members. See [`config/config.sh`](config/config.sh) and
[`docs/designs/0028-sandbox-config-file.md`](docs/designs/0028-sandbox-config-file.md).

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

**Boundary with Strategy A:** Strategy B is for *evaluating* a tool, not for building anything
durable against it. If a venv, compiled binary, or any other artifact persisted to `/workspace`
will depend on the ephemerally-installed tool's exact path or version, promote it via Strategy A
first. An artifact built against a Strategy B install silently inherits a dependency the image
itself does not have — the artifact will outlive the container, the tool will not.

---

## Cheat Sheet

```
Start a session (pick the right image for your project type):
  ./start.sh ~/projects/myproject crypto      — HSM / cryptography work
  ./start.sh ~/projects/myproject base        — Python, web, TypeScript

Start a session for a registered project:
  ./start.sh @mylib                — registry path + registry profile
  ./start.sh @mylib base           — registry path, profile overridden

Add a tool permanently:
  Edit the appropriate Dockerfile, add to the relevant layer
  ./build.sh [base|crypto]

Add a new profile:
  Create profiles/<profile>/Dockerfile, register it in config/config.sh
  (PROFILES + PROFILE_BASE) — build.sh/start.sh pick it up automatically.
  It must follow the profile contract (ADR 014)

Combine profiles into one image:
  Add COMBOS[<name>]="<member> <member>..." to config/config.sh
  ./build.sh <name>, then ./start.sh <project> <name>

Register a project name:
  Add it to config/config.sh's PROJECT_PATH/PROJECT_PROFILE (committed,
  shared), or to config/config.local.sh (this machine only) — never committed

Tune resource limits or engine for this machine only:
  cp config/config.local.sh.example config/config.local.sh, edit — never committed

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

**Don't build workspace artifacts against ephemeral toolchains.** The
entrypoint checks three artifact classes at every session start, each
with a documented detection ceiling:

- **Python venvs** — checked by testing the `bin/python3*` interpreter
  binary directly. Full detection (Tier 1).
- **CMake build directories** — checked by reading `CMakeCache.txt` and
  testing whether the recorded compiler paths are executable. Full
  detection for compiler-path staleness (Tier 1). Does not detect other
  forms of CMake cache staleness (changed system headers, changed
  `find_package` results).
- **Node.js native addons** (`.node` files) — presence warning only
  (Tier 2). Full ABI verification would require executing the addon or
  parsing its ELF NAPI tag, both of which are unsafe or impractical
  from the entrypoint. If a `.node` file is present, it *may* need
  recompilation; the check does not confirm it.

**`ldd` is permanently out of scope.** Running `ldd` against a
workspace-resident binary causes the dynamic linker to execute that
binary's `.init` sections — making a crafted ELF in `/workspace` a
code-execution vector before Claude Code has started. This is a hard
architectural limit (Tier 3), not a deferred implementation task. If
you need to verify shared library dependencies of a compiled binary,
do so manually with `docker exec -u root` after the session starts,
using `readelf -d`, with full awareness of what you are inspecting and
why. See `0007-workspace-artifact-staleness.md` §6.3 for the full ruling.
