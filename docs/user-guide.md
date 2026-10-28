# User Guide

Practical, day-to-day usage of claude-sandbox. For build/test commands see
[`BUILDING.md`](../BUILDING.md); for internals see
[`ARCHITECTURE.md`](../ARCHITECTURE.md).

## Choosing a profile

| Profile | Use for | Adds on top of `base` |
|---|---|---|
| `base` | Web, Python, TypeScript | — |
| `crypto` | HSM / cryptography | OpenSSL, p11-kit, SoftHSM2, GnuTLS |
| `systems` | C++ / CMake | CMake, GCC/Clang, GTest, sanitizers |
| `research` | LaTeX documents | TeX Live, latexmk |

Full hierarchy and rationale: [`ARCHITECTURE.md`](../ARCHITECTURE.md#image-hierarchy).

## Starting a session

```bash
./start.sh <project_directory> [profile]   # profile defaults to base
./start.sh @<name> [profile]               # registered project — see below
./start.sh --list                          # registered names, and where each is defined
```

If a project is registered by name in `config.sh` (or `config.local.sh`,
per-machine), `./start.sh @mylib` replaces typing the full path and
remembering its profile every time; an explicit `[profile]` still
overrides the registry's default. Register a project by adding it to
`config.sh`'s `PROJECT_PATH`/`PROJECT_PROFILE` (committed, shared with
everyone) or to `config.local.sh` (this machine only, never committed) —
`config.local.sh` can add a name `config.sh` doesn't have, but can't
redefine one that's already there. Full rationale:
[`docs/designs/0030-named-project-registry.md`](designs/0030-named-project-registry.md).

Each session is a fresh, ephemeral container: your project directory is
bind-mounted, the container runs non-root with capabilities dropped and
outbound network restricted to an allowlist (Anthropic API + package
registries), and the container is removed when the session ends. Nothing
in the container's own filesystem persists to the next session — only your
project directory does. See
[`docs/claude-code-security-plan.md`](claude-code-security-plan.md) for the
full threat model and [`docs/squid-proxy-guide.md`](squid-proxy-guide.md)
for the network allowlist mechanics.

## Authenticating a session

Log in from inside the session, through Claude Code's own OAuth flow, the
first time you use it after `./start.sh`. There is no host-side step that
avoids this: `start.sh` passes no Anthropic credential into the container
and does not mount your host `~/.claude`, and the container is removed on
exit, so the login does not carry over to the next session either.

Other credentials cross the boundary in two ways: `GH_TOKEN`, if it is set
in your shell when you run `start.sh`, and values stored for the project
with `./creds.sh`, which `start.sh` decrypts at launch and passes by name.
Assume the agent can read every one of them
([0129 §Sensitivity tiering policy](designs/0129-encrypted-credential-store.md)).

```bash
./creds.sh init                                    # once
pass show github/pat | ./creds.sh add @mylib GH_TOKEN
./creds.sh add @mylib GH_TOKEN --from-env GH_TOKEN
./creds.sh list --all                              # key names, never values
```

A value is never taken as an argument, because `ps` and shell history would
show it. Piping is only safer than typing when the producer is itself a
store: `echo "$SECRET" | ./creds.sh add …` puts the secret in your history.
`HISTCONTROL=ignorespace` is per-shell configuration, and it is silently
absent wherever it was never set.

If you have read Phase 4 of the security plan and are looking for the
`ANTHROPIC_API_KEY` flow: it is described there as an option this project
deliberately does not use. See Change 23.

## The global instruction layer

Every session gets `global-claude/CLAUDE.md` (and skills) copied into
`~/.claude/` at startup, plus a per-profile overlay (`global-<profile>/`,
if one exists) merged on top. This is how project-independent instructions
and skills reach every session without being part of any one project. The
copy is one-way and read-only from the container's perspective — edits
made inside a session never write back to the host source directories, and
sessions never see each other's copies. Full mechanism, isolation
guarantees, and STRIDE analysis: [`docs/designs/0003-global-layer-injection.md`](designs/0003-global-layer-injection.md).

To give a session only some skills, set `GLOBAL_SKILLS` to their names,
space-separated, in `config.local.sh` or the environment:

```bash
GLOBAL_SKILLS="design commit-convention" ./start.sh ~/projects/myapp
```

Unset, every skill is injected; `GLOBAL_SKILLS=""` injects none. A name
that is not a skill under `global-claude/skills/` stops the launch, and the
banner's `Skills:` line says what was injected. Overlay skills come with
the profile and are not selectable. See
[ADR 013](adr/013-skill-selection-and-external-skills.md).

## Adding a tool

Two options, covered in detail in `ARCHITECTURE.md`:

- **Strategy A (default):** add it to the relevant Dockerfile, rebuild.
  Reproducible, survives every future session.
- **Strategy B (experiment only):** `docker exec -u root` into a running
  container to try something without committing to it. Disappears when the
  container exits — never build a persistent artifact against it. See
  [`ARCHITECTURE.md`](../ARCHITECTURE.md#strategy-b--ephemeral-install-experiment-first)
  for the boundary between the two.

## Troubleshooting

- **"broken interpreter reference" / "stale CMake toolchain path" warnings
  at session start** — usually means a venv or CMake build directory in
  your project was built against a tool installed via Strategy B that was
  never promoted to the Dockerfile. The warning names the fix. Background:
  [`0006-interpreter-presence-health-check.md`](designs/0006-interpreter-presence-health-check.md),
  [`0007-workspace-artifact-staleness.md`](designs/0007-workspace-artifact-staleness.md).
- **Session start fails with "unknown image" or "image does not exist"** —
  check the profile name is one of `base`/`crypto`/`systems`/`research`,
  and that you've built it with `./build.sh <profile>`.
- **`docker network create` errors because `claude-net` already exists** —
  expected on any machine that's already run a session; safe to ignore.

## Running the test suite

See [`BUILDING.md`](../BUILDING.md#running-the-test-suite) for `bats`
invocation. What each test group validates and why:
[`docs/designs/0011-claude-sandbox-testing-module-sdd.md`](designs/0011-claude-sandbox-testing-module-sdd.md).
