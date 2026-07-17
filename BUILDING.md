# Building and Running

## Prerequisites

- Docker
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

The sandbox requires a Docker bridge network. Create it once:

```bash
docker network create --driver bridge claude-net
```

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
