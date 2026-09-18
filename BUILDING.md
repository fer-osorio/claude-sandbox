# Building and Running

## Configuration

Profile list, image tag prefix, default engine, and `start.sh`'s resource
limits / log-driver settings come from `config.sh` (committed) and,
optionally, `config.local.sh` (gitignored — per-machine overrides, never
committed). Precedence, later wins:

```
hardcoded defaults in build.sh/start.sh  <  config.sh  <  config.local.sh  <  env var
```

To override something on your own machine only (e.g. more memory, or a
different default engine) without touching the shared, reviewed
`config.sh`:

```bash
cp config.local.sh.example config.local.sh
$EDITOR config.local.sh   # uncomment and edit only what you need
```

Full design rationale: [`docs/designs/0028-sandbox-config-file.md`](docs/designs/0028-sandbox-config-file.md).

`config.sh` also holds a named project registry (`PROJECT_PATH`/
`PROJECT_PROFILE`, addressed as `./start.sh @<name>`), resolved against
`PROJECT_BASE` — an env var, defaulting to `$HOME/projects`, that keeps
the committed registry's paths portable across machines. It's optional:
nothing here is required for a basic setup, and only matters if you (or a
teammate) register a project. If your projects don't live under
`$HOME/projects`, `export PROJECT_BASE=...` before running `start.sh` (in
your shell profile, so it's always set). Setting `PROJECT_BASE` inside
`config.local.sh` instead does *not* work for this — `config.sh`'s
`PROJECT_PATH` entries expand `${PROJECT_BASE}` when `config.sh` is
sourced, before `config.local.sh` is, so a later assignment there comes
too late to affect them. Full design rationale:
[`docs/designs/0030-named-project-registry.md`](docs/designs/0030-named-project-registry.md).

## Prerequisites

- Rootless Podman under WSL2 (default) — see
  [Podman prerequisites](#podman-prerequisites-rootless-wsl2) below, or
- Docker (`ENGINE=docker`), fully supported as a fallback
- GitHub CLI (`gh`) — optional, for issue and PR management

### What this project assumes of the host

Two tiers. **Minimal** is what a session needs to start and for the
security controls to hold; below it something visibly breaks, and you find
out immediately. **Ideal** is what the design assumes when it claims a
control is *enforced*. Between the two, things look like they work while a
guarantee is quietly absent — this project's characteristic failure is
silent degradation rather than a crash, so the gap is worth stating.

**Minimal**

| Assumption | Where it lives | If absent |
|---|---|---|
| A container engine: rootless Podman, or Docker via `ENGINE=docker` | `start.sh` | No session starts |
| Container UID matches the host UID owning the mounted project | Build-time `HOST_UID` under Docker; `--userns=keep-id` under Podman (`start.sh`) | Git reports an ownership warning. Rebuild the image — never work around it with `safe.directory` or `chmod -R a+w` |
| ~2 GiB RAM and 2 CPUs per session | `start.sh:58-59`, overridable via `config.local.sh` or the environment | Sessions are killed or crawl |
| Egress reaches the Squid allowlist | `squid/squid.conf` | Network calls are refused at the proxy, visibly |
| SELinux hosts relabel bind mounts | [SELinux relabeling](#selinux-relabeling-fedora--other-selinux-enforcing-hosts) — automatic under Podman | `EACCES` on the mounted project |
| `bats-core` on the host, to run the engine-gated test tiers | [Running the test suite](#running-the-test-suite) | Only the `hostonly` tier runs, from inside a session or in CI; everything needing an image or a container does not |

**Ideal**

| Assumption | Where it lives | If absent |
|---|---|---|
| The kernel delegates cgroups v2 `memory` to the user session | R-6 in `tests/test_runtime_posture.bats`; [Podman prerequisites](#podman-prerequisites-rootless-wsl2) | **Podman accepts `--memory` and never enforces it.** The container looks healthy and the limit is decorative. Only a deliberate OOM probe finds it — this is the worked example of the gap between the tiers, and under WSL 2.5.x it is an upstream regression rather than a one-time setup error |
| Toolchains are baked into the image, never installed at runtime | §Interpreter discipline in the injected `global-claude/CLAUDE.md` | Build artifacts outlive the interpreter they were built against |
| `GH_TOKEN` is exported on the host | Forwarded conditionally by `start.sh:236` | Issue and PR work fails inside the session, though everything else runs |
| The model driving the session holds the judgment rules the instruction layer asks for | Nowhere | Unknown. Nothing records which capability tier those rules were written against, or which degrades first under a weaker one — a named gap, with no mechanism proposed |

The last row has no home other than this table, and is deliberately left as
an open question rather than an implied promise.

## Build all images

Run once, and again after any Dockerfile change:

```bash
./build.sh
```

Build a single image and its dependencies:

```bash
./build.sh base      # base image only
./build.sh crypto    # base + crypto
./build.sh systems   # base + systems
./build.sh research  # base + research
```

Add `--no-cache` to force a full rebuild (pulls updated apt packages):

```bash
./build.sh --no-cache
```

## Start a session

```bash
./start.sh <project_directory> [image]
```

`image` defaults to `base`. Valid options: `base`, `crypto`, `systems`, `research`.

```bash
./start.sh ~/projects/mylib crypto      # HSM / cryptography work
./start.sh ~/projects/myapp systems     # C++ / CMake projects
./start.sh ~/projects/paper research    # LaTeX documents
./start.sh ~/projects/webapp            # web / Python / TypeScript
```

## First-time network setup

The sandbox requires a bridge network. Create it once, using the same engine
`build.sh`/`start.sh` will use (`podman` by default; `docker` if
`ENGINE=docker` is set):

```bash
podman network create --driver bridge claude-net
# or, under Docker:
# docker network create --driver bridge claude-net
```

## Podman prerequisites (rootless, WSL2)

`build.sh` and `start.sh` both honor an `$ENGINE` environment variable
(default `podman`). Set `ENGINE=docker` to route every build/run invocation
through Docker instead — see `docs/designs/0025-podman-migration.md` for the full
design. Rootless Podman needs a few things Docker's rootless setup doesn't
require you to think about directly:

- **subuid/subgid delegation.** Podman's user-namespace remapping needs a
  range of UIDs/GIDs delegated to your user. Check for an existing entry:

  ```bash
  grep "^$(whoami):" /etc/subuid /etc/subgid
  ```

  If either file has no entry for your user, add one (as root):

  ```bash
  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$(whoami)"
  ```

- **systemd under WSL2**, required for the user session that cgroups v2
  delegation depends on. WSL2 does not enable this by default — add to
  `/etc/wsl.conf` on the WSL2 instance, then restart it (`wsl --shutdown`
  from Windows):

  ```ini
  [boot]
  systemd=true
  ```

- **cgroups v2 `memory` delegation**, required for `--memory`/`--cpus` to
  actually be *enforced* under rootless Podman, not just accepted. Checking
  `cat /sys/fs/cgroup/cgroup.controllers` is **not sufficient** — that only
  shows which controllers exist on the machine, not whether `memory` has
  been delegated down to your own user session. Check the delegation chain
  instead:

  ```bash
  cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/cgroup.subtree_control
  ```

  If `memory` is missing from that list (it commonly is — systemd does not
  delegate it to user sessions by default on many distros), `--memory`
  limits will be silently unenforced: a container can be killed by some
  other, unscoped boundary without Podman's own `OOMKilled` bookkeeping
  ever reflecting it (see `docs/claude_code_security_plan.md` Change 17).
  Fix it:

  ```bash
  sudo mkdir -p /etc/systemd/system/user@.service.d
  printf '[Service]\nDelegate=memory pids cpu io\n' \
    | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
  sudo systemctl daemon-reload
  ```

  Then fully restart the WSL2 instance so `user@<uid>.service` restarts
  with delegation active — a live session will not pick this up
  retroactively:

  ```bash
  # From Windows PowerShell:
  wsl --shutdown
  # then reopen your WSL2 terminal and re-check cgroup.subtree_control above
  ```

  `tests/test_runtime_posture.bats` R-6 regression-tests this
  automatically — run `bats tests/` after the fix to confirm.

Once these are in place, run the test suite against Podman to confirm your
setup before relying on it for a real session:

```bash
bats tests/   # ENGINE unset — podman is now the default
```

Docker remains fully supported as a fallback via `ENGINE=docker`, until a
separate, later decision retires it.

## SELinux relabeling (Fedora / other SELinux-enforcing hosts)

If your host enforces SELinux (common on Fedora and RHEL-family distros;
check with `getenforce` — `Enforcing` means it applies here), Podman does
not automatically relabel bind-mounted host directories. Without a relabel,
a mount keeps its original SELinux context and the container is denied
access at the MAC layer regardless of correct POSIX permissions — you'd see
`EACCES` on `/workspace` even though `ls -la` shows the right owner and
mode.

`start.sh` handles this automatically as of
`docs/claude_code_security_plan.md` Change 19: under `ENGINE=podman`, its
bind mounts carry a `relabel=shared` option, which is a no-op on hosts where
SELinux isn't enforcing. You shouldn't need to do anything for a normal
`./start.sh` session.

If you're invoking `podman run` yourself (bypassing `start.sh`) and hit
`EACCES` on a bind-mounted path with otherwise-correct permissions, check:

```bash
getenforce                       # is SELinux actually enforcing?
ls -Z /path/on/host              # what context does the host path have?
```

and add `relabel=shared` (or the `:z` suffix on `-v`) to your own mount.

Docker's fallback path (`ENGINE=docker`) does not currently get this fix —
Docker's `--mount` has no relabel suboption — so the same issue is possible
there on an SELinux-enforcing host. See
`docs/designs/0025-podman-migration.md` §9 for the open question on that gap.

## Authentication

Log in from inside the session, through Claude Code's own OAuth flow, the
first time you use it after `./start.sh`. See `docs/user_guide.md`
§Authenticating a session, and Change 23 in
`docs/claude_code_security_plan.md` for why the `ANTHROPIC_API_KEY` flow is
deliberately not used.

## Running the test suite

Uses [`bats-core`](https://github.com/bats-core/bats-core) — a TAP-compliant
testing framework for Bash. It was chosen because it's shell-native:
`build.sh`, `start.sh`, and `entrypoint.sh` are already all Bash, so tests
can drive and assert on them directly without pulling in a new language
runtime just for testing.

`bats` ships in `claude-base`, so a session can run the `hostonly` tier
itself. Running the engine-gated tiers still needs it on the host, because
those build images and start containers.

**Install on the host** (pick one):

```bash
# Debian / Ubuntu
sudo apt-get install bats

# Fedora / RHEL / CentOS (via EPEL if not already enabled)
sudo dnf install epel-release   # RHEL/CentOS only; Fedora ships bats directly
sudo dnf install bats

# Any distro — upstream, pinned to the commit the image and CI both install.
# BATS_VERSION and BATS_COMMIT are declared in base/Dockerfile; use those
# values rather than copying them here, so this file cannot drift from them.
git clone --depth 1 --branch <BATS_VERSION> \
  https://github.com/bats-core/bats-core.git
cd bats-core
test "$(git rev-parse HEAD)" = "<BATS_COMMIT>"
sudo ./install.sh /usr/local
```

Verify with `bats --version`.

A distro package is a different version from the pinned one. That is
tolerable for local iteration and is why both options are still listed, but
CI and the image are the versions that decide a merge.

```bash
# Fast tier only (default local iteration loop) — runs against Podman
bats --filter-tags fast tests/

# Full suite (pre-merge gate) — runs against Podman
bats tests/

# Against the Docker fallback
ENGINE=docker bats tests/

# Everything that needs no container engine at all — what CI runs
bats --filter-tags hostonly tests/
```

### Tag axes

`fast`/`slow` and `hostonly` are two independent axes, and it is worth not
confusing them:

| Tag | Means | Example |
|---|---|---|
| `fast` | Completes in seconds | `test_global_layer.bats` G-1 — but it still needs a built `claude-base` image |
| `slow` | Builds images or starts containers | `test_squid_isolation.bats` S-1 |
| `hostonly` | Needs **no** engine daemon and **no** image | `test_config.bats` C-1, `test_docs_integrity.bats` D-1 |

`fast` does not imply `hostonly`. Several `fast` tests still require a
running Podman and a pre-built image, which is why CI filters on `hostonly`
rather than on `fast` — see `.github/workflows/ci.yml`.

See `docs/designs/0011-claude-sandbox-testing-module-sdd.md` for what each test
group covers and why.

## See also

- `ARCHITECTURE.md` — image hierarchy and dependency management strategy
- `docs/claude_code_security_plan.md` — threat model and security controls
- `docs/squid_proxy_guide.md` — outbound network policy via Squid proxy
- `docs/designs/0011-claude-sandbox-testing-module-sdd.md` — bats-core test harness design
