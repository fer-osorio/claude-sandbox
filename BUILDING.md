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

Full design rationale: [`docs/designs/sandbox-config-file.md`](docs/designs/sandbox-config-file.md).

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
[`docs/designs/named-project-registry.md`](docs/designs/named-project-registry.md).

## Prerequisites

- Rootless Podman under WSL2 (default) — see
  [Podman prerequisites](#podman-prerequisites-rootless-wsl2) below, or
- Docker (`ENGINE=docker`), fully supported as a fallback
- GitHub CLI (`gh`) — optional, for issue and PR management

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
through Docker instead — see `docs/designs/podman-migration.md` for the full
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
`docs/designs/podman-migration.md` §9 for the open question on that gap.

## Authentication

Claude Code requires an Anthropic API key. On first use, authenticate on
the host and pass the key into containers via the `ANTHROPIC_API_KEY`
environment variable. See `docs/claude_code_security_plan.md` §Phase 1
for the full authentication setup procedure.

## Running the test suite

Requires [`bats-core`](https://github.com/bats-core/bats-core) on the host —
a TAP-compliant testing framework for Bash. It was chosen because it's
shell-native: `build.sh`, `start.sh`, and `entrypoint.sh` are already all
Bash, so tests can drive and assert on them directly without pulling in a
new language runtime just for testing.

**Install** (pick one):

```bash
# Debian / Ubuntu
sudo apt-get install bats

# Fedora / RHEL / CentOS (via EPEL if not already enabled)
sudo dnf install epel-release   # RHEL/CentOS only; Fedora ships bats directly
sudo dnf install bats

# Any distro — canonical upstream install, not tied to a distro package version
git clone https://github.com/bats-core/bats-core.git
cd bats-core && sudo ./install.sh /usr/local
```

Verify with `bats --version`.

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
| `hostonly` | Needs **no** engine daemon and **no** image | `test_config.bats` C-1, `test_docs_integrity.bats` D-1, `test_control_declarations.bats` G-6 |

`fast` does not imply `hostonly`. Several `fast` tests still require a
running Podman and a pre-built image, which is why CI filters on `hostonly`
rather than on `fast` — see `.github/workflows/ci.yml`.

Which axis a test lands on is a property of the *file*, not of the test:
`setup()` runs for every selected test in a file, so one engine-gated
`setup()` puts every test in that file outside CI. Adding a `hostonly` tag
does not rescue it — the test gets selected and then fails in `setup()`.
An assertion that reads only tracked files therefore belongs in
`test_control_declarations.bats`, which gates on nothing. The placement
rule is in the SDD, §6.2.

See `docs/designs/claude-sandbox-testing-module-sdd.md` for what each test
group covers and why.

## See also

- `ARCHITECTURE.md` — image hierarchy and dependency management strategy
- `docs/claude_code_security_plan.md` — threat model and security controls
- `docs/squid_proxy_guide.md` — outbound network policy via Squid proxy
- `docs/designs/claude-sandbox-testing-module-sdd.md` — bats-core test harness design
