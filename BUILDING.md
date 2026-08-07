# Building and Running

## Prerequisites

- Docker (default), or rootless Podman under WSL2 — see
  [Podman prerequisites](#podman-prerequisites-rootless-wsl2) below
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
`build.sh`/`start.sh` will use (`docker` by default; `podman` if `$ENGINE` is
set — see below):

```bash
docker network create --driver bridge claude-net
# or, under Podman:
# podman network create --driver bridge claude-net
```

## Podman prerequisites (rootless, WSL2)

`build.sh` and `start.sh` both honor an `$ENGINE` environment variable
(default `docker`). Set `ENGINE=podman` to route every build/run invocation
through Podman instead — see `docs/designs/podman-migration.md` for the full
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

- **cgroups v2**, required for `--memory`/`--cpus` enforcement under
  rootless Podman. Confirm it's active:

  ```bash
  cat /sys/fs/cgroup/cgroup.controllers
  ```

  A non-empty list of controllers (e.g. `cpu memory ...`) confirms cgroups
  v2 is mounted and delegated.

- **systemd under WSL2**, required for the user session that cgroups v2
  delegation depends on. WSL2 does not enable this by default — add to
  `/etc/wsl.conf` on the WSL2 instance, then restart it (`wsl --shutdown`
  from Windows):

  ```ini
  [boot]
  systemd=true
  ```

Once these are in place, run the test suite against Podman to confirm your
setup before relying on it for a real session:

```bash
ENGINE=podman bats tests/
```

Docker remains the default and fully supported (`$ENGINE` unset, or
`ENGINE=docker` explicitly) until a separate, later decision retires it.

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
# Fast tier only (default local iteration loop)
bats --filter-tags fast tests/

# Full suite (pre-merge / pre-migration gate)
bats tests/

# Against Podman, once migrated
ENGINE=podman bats tests/
```

See `docs/designs/claude-sandbox-testing-module-sdd.md` for what each test
group covers and why.

## See also

- `ARCHITECTURE.md` — image hierarchy and dependency management strategy
- `docs/claude_code_security_plan.md` — threat model and security controls
- `docs/squid_proxy_guide.md` — outbound network policy via Squid proxy
- `docs/designs/claude-sandbox-testing-module-sdd.md` — bats-core test harness design
