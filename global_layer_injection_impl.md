# Global Layer Injection — Implementation Guide

> **Document type:** Implementation Guide
> **Companion document:** `global_layer_injection_sdd.md`
> **Prerequisite reading:** `claude_code_security_plan.md`, `squid_proxy_guide.md`
> **Audience:** The engineer implementing the design described in the companion SDD. Steps are
> ordered for a clean first-time implementation. A rollback note appears at the end of each
> phase for safe incremental application.

---

## Before You Begin

**What you will have when done:**

- A curated `global-claude/` directory whose contents Claude Code receives in every session
- Per-image overlay directories (`global-crypto/`, `global-systems/`, `global-research/`) for
  domain-specific additions
- A non-root entrypoint script baked into `claude-base` that merges these layers at startup
- A modified `start.sh` that mounts the right directories based on which image is selected
- An updated `settings.json` with a new `Write(/run/*)` deny rule
- All existing security properties preserved and extended

**Estimated time:** 30–45 minutes for a first implementation, including build time.

**Prerequisites:**

- The existing sandbox (`build.sh`, `start.sh`, all four Dockerfiles) is working correctly
- `docker images | grep claude` shows `claude-base`, `claude-crypto`, `claude-systems`,
  `claude-research`
- You are in `~/.claude-sandbox/` for all relative paths below

---

## Phase 1 — Create the Global Layer Directories

This phase creates the host-side directory tree that will be injected into containers. No
Docker changes yet — this phase is purely filesystem setup.

### Step 1.1 — Create the base global layer directory

```bash
mkdir -p ~/.claude-sandbox/global-claude/skills
mkdir -p ~/.claude-sandbox/global-claude/commands
```

### Step 1.2 — Create the initial `CLAUDE.md`

This is your cross-project operator instruction file. Start with a template and expand it over
time as you accumulate corrections from real sessions.

```bash
cat > ~/.claude-sandbox/global-claude/CLAUDE.md << 'EOF'
# Operator Instructions

## Identity and scope
You are running inside a sandboxed Docker container on a local development workstation.
The mounted project directory is /workspace. Do not reference paths outside /workspace
unless they are explicitly listed below.

## Security constraints
- Never suggest `chmod -R a+w` or equivalent broad permission changes.
- Never propose adding `safe.directory` to git config as a workaround for UID warnings.
  The correct response to that warning is to notify the operator so the image is rebuilt.
- Never attempt to read or write /run/claude-global or /run/claude-overlay.

## Coding standards
- Prefer explicit error handling over silent failures.
- Every shell script must include `set -euo pipefail` at the top.
- Inline shell comments inside backslash-continued RUN blocks in Dockerfiles are unreliable.
  Place all comments above the RUN instruction as Dockerfile-level comments.

## Commit conventions
- Commit messages follow Conventional Commits: type(scope): description
- Types: feat, fix, docs, refactor, test, chore
- Do not add Co-Authored-By trailers unless the operator explicitly requests them.

## Response format
- Prefer prose over bullet lists for explanations.
- Code blocks must include a language identifier.
- When proposing file changes, show the complete modified file, not a diff, unless the file
  exceeds 200 lines.
EOF
```

Adjust the contents to match your actual preferences. This template is a starting point, not a
prescription.

### Step 1.3 — Create the overlay directories

Create the overlay directories for each domain image. These start empty — you will populate them
as you identify domain-specific skills worth capturing.

```bash
mkdir -p ~/.claude-sandbox/global-crypto/skills
mkdir -p ~/.claude-sandbox/global-systems/skills
mkdir -p ~/.claude-sandbox/global-research/skills
```

### Step 1.4 — Create an example domain skill (crypto overlay)

This demonstrates the skill file format and gives the crypto image something concrete to inherit.
Create it now; refine the content based on your actual HSM workflow.

```bash
mkdir -p ~/.claude-sandbox/global-crypto/skills/pkcs11-patterns
cat > ~/.claude-sandbox/global-crypto/skills/pkcs11-patterns/SKILL.md << 'EOF'
---
name: pkcs11-patterns
description: PKCS#11 and SoftHSM2 workflow patterns for HSM development sessions. Use when
  initializing tokens, managing slots, or writing code that calls PKCS#11 via p11-kit.
---

# PKCS#11 Patterns

## Environment
- SoftHSM2 token is pre-initialized at image build time with label "dev-token"
- SO PIN and User PIN are both: 1234567890 (development sandbox only)
- SOFTHSM2_CONF is set to /etc/softhsm/softhsm2.conf by the container ENV

## Verifying the token

```bash
softhsm2-util --show-slots
p11-kit list-modules
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so -L
```

## Common failure modes
- `ERROR: Failed to enumerate object store` — SOFTHSM2_CONF is not set or points to a
  nonexistent file. Check the ENV in the running container: `echo $SOFTHSM2_CONF`
- Permission denied on /var/lib/softhsm/tokens — claude-agent is not in the softhsm group.
  This should not occur if the image was built correctly. Rebuild with `./build.sh crypto`.
EOF
```

### Step 1.5 — Verify the directory tree

```bash
find ~/.claude-sandbox/global-claude ~/.claude-sandbox/global-crypto \
     ~/.claude-sandbox/global-systems ~/.claude-sandbox/global-research \
     -type f | sort
```

Expected output (with the example skill):

```
/home/<you>/.claude-sandbox/global-claude/CLAUDE.md
/home/<you>/.claude-sandbox/global-crypto/skills/pkcs11-patterns/SKILL.md
```

The `global-systems/skills/` and `global-research/skills/` directories are empty at this stage.
That is correct.

**Rollback:** `rm -rf ~/.claude-sandbox/global-claude ~/.claude-sandbox/global-crypto ~/.claude-sandbox/global-systems ~/.claude-sandbox/global-research`. No other files have been modified yet.

---

## Phase 2 — Write the Entrypoint Script

### Step 2.1 — Create `base/entrypoint.sh`

```bash
cat > ~/.claude-sandbox/base/entrypoint.sh << 'EOF'
#!/usr/bin/env bash
# entrypoint.sh — Global layer injection for claude-sandbox containers.
#
# Runs as claude-agent (non-root) at container startup.
# Merges the base global layer and any per-image overlay into ~/.claude/
# before handing control to the CMD (claude).
#
# Mount points (both readonly):
#   /run/claude-global   — base global layer (always present if start.sh passes it)
#   /run/claude-overlay  — per-image overlay (present only when an overlay dir exists)
#
# The copy-on-start pattern gives Claude Code a writable ~/.claude/ without
# exposing the host source directories to writes.

set -euo pipefail

GLOBAL_SRC="/run/claude-global"
OVERLAY_SRC="/run/claude-overlay"
DEST="${HOME}/.claude"

echo "[entrypoint] Starting global layer injection"

mkdir -p "$DEST"

if [ -d "$GLOBAL_SRC" ] && [ "$(ls -A "$GLOBAL_SRC" 2>/dev/null)" ]; then
    cp -r "$GLOBAL_SRC/." "$DEST/"
    echo "[entrypoint] Base global layer applied from $GLOBAL_SRC"
else
    echo "[entrypoint] WARNING: $GLOBAL_SRC is absent or empty — no base layer applied"
fi

if [ -d "$OVERLAY_SRC" ] && [ "$(ls -A "$OVERLAY_SRC" 2>/dev/null)" ]; then
    cp -r "$OVERLAY_SRC/." "$DEST/"
    echo "[entrypoint] Overlay layer applied from $OVERLAY_SRC"
else
    echo "[entrypoint] No overlay present at $OVERLAY_SRC — skipping"
fi

echo "[entrypoint] ~/.claude contents:"
find "$DEST" -type f | sort | sed "s|^|[entrypoint]   |"

echo "[entrypoint] Injection complete. Starting: $*"
exec "$@"
EOF

chmod +x ~/.claude-sandbox/base/entrypoint.sh
```

**Why `exec "$@"` and not `claude` directly:** Using `exec` replaces the shell process with
Claude Code, so Claude runs as PID 1 of the session (or as the direct child of the Docker
runtime). This avoids a zombie shell process and ensures signals (SIGTERM on `docker stop`) are
delivered to Claude Code itself, allowing clean shutdown.

**Why the `ls -A` emptiness check:** A directory can exist but be empty if `start.sh` is run
without the mount being configured. The check prevents silently treating an empty mount as a
valid source, which would produce a no-op `cp` that is harder to diagnose.

**Rollback:** `rm ~/.claude-sandbox/base/entrypoint.sh`. The Dockerfile has not been changed yet.

---

## Phase 3 — Modify the Base Dockerfile

### Step 3.1 — Add the entrypoint to `base/Dockerfile`

The Dockerfile currently ends with:

```dockerfile
USER claude-agent

CMD ["claude"]
```

Replace those two lines with the following block. The `COPY` and `chmod` must run as root
(before `USER claude-agent`); the `ENTRYPOINT` and `CMD` directives are metadata and are not
executed during the build.

```dockerfile
# ─────────────────────────────────────────────────────────────────────────────
# LAYER 5 — Entrypoint script for global layer injection
# The script runs as claude-agent (non-root). COPY and chmod run here as root
# because USER claude-agent is set immediately after.
# ─────────────────────────────────────────────────────────────────────────────
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER claude-agent

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
```

The complete modified end of `base/Dockerfile` should look like this:

```dockerfile
RUN groupadd -r claude-agent \
    && useradd -r -g claude-agent -m -d /home/claude-agent \
               -u $HOST_UID claude-agent

WORKDIR /workspace
RUN chown claude-agent:claude-agent /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER claude-agent

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
```

### Step 3.2 — Rebuild all images

Because the entrypoint is in `claude-base`, all child images inherit it and must be rebuilt.

```bash
cd ~/.claude-sandbox
./build.sh
```

To rebuild only base and one child during development:

```bash
./build.sh crypto
```

### Step 3.3 — Verify the entrypoint is present in the image

```bash
docker run --rm claude-base ls -la /usr/local/bin/entrypoint.sh
```

Expected: `-rwxr-xr-x 1 root root ... /usr/local/bin/entrypoint.sh`

**Rollback:** Revert the Dockerfile change (remove the COPY, chmod, ENTRYPOINT lines, restore
`USER claude-agent` and `CMD ["claude"]`), then `./build.sh`.

---

## Phase 4 — Modify `start.sh`

Replace the current `start.sh` with the version below. The changes are:

- New variables for global layer paths
- Preflight checks with clear warnings
- Conditional overlay mount logic using an array
- All security flags preserved exactly

```bash
cat > ~/.claude-sandbox/start.sh << 'EOF'
#!/usr/bin/env bash
# Usage: start.sh <project_directory> [image]
#
# Arguments:
#   project_directory  — path to the project to mount (default: current dir)
#   image              — which sandbox image to use (default: base)
#                        one of: base, crypto, systems, research
#
# Global layer directories (relative to this script's location):
#   global-claude/        — base layer, injected into every session
#   global-<image>/       — per-image overlay, injected when present
#
# Examples:
#   ./start.sh ~/projects/mylib crypto      — HSM / cryptography work
#   ./start.sh ~/projects/myapp systems     — C++ / CMake projects
#   ./start.sh ~/projects/paper research    — LaTeX documents
#   ./start.sh ~/projects/webapp            — web / Python (uses base)
#
# Before running this for the first time, ensure the network exists:
#   docker network create --driver bridge claude-net

set -euo pipefail

SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"
IMAGE_TAG="${2:-base}"

VALID_IMAGES="base crypto systems research"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: '$PROJECT_DIR' is not a directory."
    exit 1
fi

if ! echo "$VALID_IMAGES" | grep -qw "$IMAGE_TAG"; then
    echo "Error: unknown image '$IMAGE_TAG'."
    echo "Valid options: $VALID_IMAGES"
    exit 1
fi

IMAGE_NAME="claude-${IMAGE_TAG}"

if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    echo "Error: image '$IMAGE_NAME' does not exist."
    echo "Build it first with: ./build.sh $IMAGE_TAG"
    exit 1
fi

GLOBAL_BASE="${SANDBOX_DIR}/global-claude"
GLOBAL_OVERLAY="${SANDBOX_DIR}/global-${IMAGE_TAG}"

echo "Project:  $PROJECT_DIR"
echo "Image:    $IMAGE_NAME"
echo "Network:  claude-net (Anthropic API + package registries only)"

if [ -d "$GLOBAL_BASE" ]; then
    echo "Global:   $GLOBAL_BASE"
else
    echo "Global:   WARNING — $GLOBAL_BASE not found; session will have no global layer"
fi

if [ -d "$GLOBAL_OVERLAY" ] && [ "$IMAGE_TAG" != "base" ]; then
    echo "Overlay:  $GLOBAL_OVERLAY"
else
    echo "Overlay:  none for image '$IMAGE_TAG'"
fi

echo ""

MOUNT_ARGS=(
    "--mount" "type=bind,source=${PROJECT_DIR},target=/workspace"
)

if [ -d "$GLOBAL_BASE" ]; then
    MOUNT_ARGS+=(
        "--mount" "type=bind,source=${GLOBAL_BASE},target=/run/claude-global,readonly"
    )
fi

if [ -d "$GLOBAL_OVERLAY" ] && [ "$IMAGE_TAG" != "base" ]; then
    MOUNT_ARGS+=(
        "--mount" "type=bind,source=${GLOBAL_OVERLAY},target=/run/claude-overlay,readonly"
    )
fi

docker run \
    --rm \
    -it \
    --name "claude-$(basename "$PROJECT_DIR")-$(date +%s)" \
    "${MOUNT_ARGS[@]}" \
    --network claude-net \
    --memory="2g" \
    --cpus="2" \
    --security-opt=no-new-privileges \
    --cap-drop=ALL \
    "$IMAGE_NAME"
EOF

chmod +x ~/.claude-sandbox/start.sh
```

**Why `SANDBOX_DIR` instead of `$HOME`:** Using the script's own location makes `start.sh`
work correctly if the sandbox directory is moved or if it is invoked from a path other than
`~/.claude-sandbox/`. This is more robust than hardcoding `$HOME/.claude-sandbox`.

**Why an array for `MOUNT_ARGS`:** Shell arrays avoid quoting bugs in paths with spaces. Each
`--mount` flag and its argument are stored as separate array elements, which `"${MOUNT_ARGS[@]}"`
expands correctly regardless of whitespace in directory names.

**Rollback:** Restore the previous `start.sh` from version control or from the copy you made
before this step.

---

## Phase 5 — Update `settings.json`

Add `Write(/run/*)` to the `permissions.deny` list. This is defense in depth — the readonly
mount already enforces this at the OS level, but a second application-level gate follows the
design principle that no single control carries the full burden.

Current `settings.json`:

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

Updated `settings.json`:

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
      "Write(../*)",
      "Write(/run/*)"
    ]
  }
}
```

Note: `settings.json` at the project level is copied into `/workspace/.claude/settings.json`
when you start a session. Place this updated file in your project directories, or maintain a
template in `~/.claude-sandbox/` and copy it when starting a new project.

---

## Phase 6 — Smoke Test

Run these tests in order. Each one verifies a specific property of the implementation before
you rely on it for real work.

### Test 1 — Base layer is present in a new session

```bash
./start.sh ~/projects/any-project base
```

Inside the container, before Claude Code's interactive mode starts, you should see entrypoint
log lines:

```
[entrypoint] Starting global layer injection
[entrypoint] Base global layer applied from /run/claude-global
[entrypoint] No overlay present at /run/claude-overlay — skipping
[entrypoint] ~/.claude contents:
[entrypoint]   /home/claude-agent/.claude/CLAUDE.md
[entrypoint] Injection complete. Starting: claude
```

Then verify directly:

```bash
# In a second terminal while the container is running:
docker exec -it <container-name> cat /home/claude-agent/.claude/CLAUDE.md
```

The contents should match your `global-claude/CLAUDE.md`.

### Test 2 — Overlay is applied for domain images

```bash
./start.sh ~/projects/mylib crypto
```

Expected entrypoint output:

```
[entrypoint] Base global layer applied from /run/claude-global
[entrypoint] Overlay layer applied from /run/claude-overlay
[entrypoint] ~/.claude contents:
[entrypoint]   /home/claude-agent/.claude/CLAUDE.md
[entrypoint]   /home/claude-agent/.claude/skills/pkcs11-patterns/SKILL.md
```

### Test 3 — `/run/` mount points are readonly

```bash
# While a container is running:
docker exec -it <container-name> bash -c "touch /run/claude-global/test-write 2>&1"
```

Expected: `touch: cannot touch '/run/claude-global/test-write': Read-only file system`

### Test 4 — Auto-memory writes to the working copy, not the host

```bash
# Inside the container, simulate Claude writing auto-memory:
docker exec -it <container-name> bash -c \
    "mkdir -p ~/.claude/memory && echo 'test' > ~/.claude/memory/test.md"

# Verify it does NOT appear on the host:
ls ~/.claude-sandbox/global-claude/
```

The host directory should not contain a `memory/` subdirectory or `test.md`.

### Test 5 — Session isolation between concurrent containers

```bash
# Terminal 1:
./start.sh ~/projects/project-a base &
# Inside container A, write something to ~/.claude/
docker exec claude-project-a-<ts> bash -c "echo 'from-A' > ~/.claude/isolation-test.md"

# Terminal 2:
./start.sh ~/projects/project-b base &
# Inside container B, verify the file does not exist:
docker exec claude-project-b-<ts> bash -c "cat ~/.claude/isolation-test.md 2>&1"
```

Expected in terminal 2: `cat: /home/claude-agent/.claude/isolation-test.md: No such file or directory`

### Test 6 — `settings.json` deny rule blocks writes to `/run/`

Start a session and ask Claude to write a file to `/run/claude-global/`. Verify that Claude Code
reports the action was blocked by the permission policy rather than failing at the OS level.
This confirms the application-layer gate is active independently of the readonly mount.

---

## Phase 7 — Initialize Version Control for the Global Layer

The global layer directories should be tracked in the same git repository as the sandbox
infrastructure. This provides the audit trail described in the SDD's Repudiation control.

```bash
cd ~/.claude-sandbox

# If the sandbox is already a git repo:
git add global-claude/ global-crypto/ global-systems/ global-research/
git add base/entrypoint.sh base/Dockerfile
git add start.sh settings.json
git commit -m "feat(global-layer): add entrypoint-based global layer injection

Implements Strategy 3 (entrypoint copy injection) and Strategy 4
(per-image overlay). See docs/global_layer_injection_sdd.md.

- global-claude/: base layer injected into every session
- global-{crypto,systems,research}/: per-image overlays
- base/entrypoint.sh: merges layers at container startup
- start.sh: conditionally mounts base and overlay directories
- settings.json: adds Write(/run/*) deny rule"
```

---

## Maintenance Procedures

### Adding a new cross-project instruction

Edit `~/.claude-sandbox/global-claude/CLAUDE.md`. Commit the change. The next session picks it
up automatically — no rebuild required, because the file is injected via a bind mount at runtime,
not baked into the image.

### Adding a new cross-project skill

```bash
mkdir -p ~/.claude-sandbox/global-claude/skills/<skill-name>
# write SKILL.md
git add global-claude/skills/<skill-name>/
git commit -m "feat(global-layer): add <skill-name> skill to base layer"
```

No rebuild required.

### Adding a domain-specific skill

```bash
mkdir -p ~/.claude-sandbox/global-crypto/skills/<skill-name>
# write SKILL.md
git add global-crypto/skills/<skill-name>/
git commit -m "feat(global-layer): add <skill-name> skill to crypto overlay"
```

No rebuild required.

### Adding a new image type

1. Create the Dockerfile in `~/.claude-sandbox/<newtype>/Dockerfile` (inherits from `claude-base`;
   the entrypoint is inherited automatically).
2. Create `~/.claude-sandbox/global-<newtype>/` and populate it.
3. Add `<newtype>` to the `VALID_IMAGES` list in `start.sh`.
4. Add a `build_<newtype>` function and case entry to `build.sh`.
5. Run `./build.sh <newtype>`.

### Reviewing what Claude was instructed in a past session

```bash
# Check out the state of global-claude at the time of the session:
git log --oneline global-claude/
git show <commit-hash>:global-claude/CLAUDE.md
```

### Pruning stale auto-memory

Auto-memory does not persist between sessions in this design (it lives in the ephemeral working
copy). No cleanup procedure is needed. If you identify a Claude insight worth preserving, add it
manually to `global-claude/CLAUDE.md` and commit.

---

## Changelog

### Version 1.0 — 2026-05-20
Initial implementation guide. Covers all six phases from directory creation through version
control initialization. Companion to `global_layer_injection_sdd.md` v1.0.
