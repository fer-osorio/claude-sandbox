# Building and Running

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
```

See `docs/designs/claude-sandbox-testing-module-sdd.md` for what each test
group covers and why.

## See also

- `ARCHITECTURE.md` — image hierarchy and dependency management strategy
- `docs/claude_code_security_plan.md` — threat model and security controls
- `docs/squid_proxy_guide.md` — outbound network policy via Squid proxy
- `docs/designs/claude-sandbox-testing-module-sdd.md` — bats-core test harness design
