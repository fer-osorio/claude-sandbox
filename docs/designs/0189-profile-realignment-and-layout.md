# Profile realignment and repository layout

## Status
Accepted

## Context

The `systems` (C/C++) and `research` (LaTeX) profiles are not in use. This is
the problem that the dev-env project's planning scope and charter (Go on
2026-09-15) already settled for its own `cpp` and `research` profiles. The
same reasoning applies here. In this repository an unused profile also costs:

- **Egress.** `squid/squid.conf` allows `en.cppreference.com`, `cmake.org`,
  `ctan.org` and `tug.org` for every session, whatever its profile.
- **CI.** Every profile is built by the container tier, and T-2 and T-3 run
  against them, on every control-touching pull request and nightly.
- **Image surface.** `sqlite3` and `libsqlite3-dev` ship in `claude-base` for
  the benefit of these two profiles (`base/Dockerfile` header) and have no
  other user.

Separately, profile build contexts and configuration files sit at the
repository root next to the scripts. `dev-env` already groups its profiles
under `profiles/`, and the planned profile composition work is easier to
build on top of a `profiles/` directory.

## Decision

1. **Retire `systems` and `research`.**
   - Delete the build contexts, fixtures `cpp-minimal` and
     `research-minimal`, and tests T-2 and T-3.
   - Remove the four allowlist hosts listed under §Context.
   - Drop `sqlite3` and `libsqlite3-dev` from `claude-base`. Python's
     `sqlite3` module keeps working: `libsqlite3-0` is a dependency of
     `python3`.
   - Tests that enumerate profiles (C-3, B-3, R-5) derive the list from
     `PROFILES` instead of a literal, so they cover a future profile without
     edits.
2. **Move profile build contexts to `profiles/<name>/`.**
   - The path is derived from the profile name. No per-profile directory key
     is added.
   - `squid/` stays at the root: it is not a profile, and `build.sh` builds it
     separately.
3. **Move configuration to `config/`.**
   - `config/config.sh` and `config/config.local.sh.example` keep their
     basenames, so messages and the tests that assert them stay as they are.
   - `build.sh` and `check-auto-memory.sh` source `lib/config.sh` instead of
     sourcing both files themselves. That leaves one copy of layers 2 and 3.
   - `lib/config.sh` aborts when a `config.local.sh` exists at the old root
     path. Silently ignoring it would revert an operator's overrides to their
     defaults.
   - `.gitignore` keeps ignoring the old path, so a stale file cannot be
     committed by accident.

## STRIDE impact

| Threat | Change |
|---|---|
| **Information Disclosure (I)** | **Improved.** Four fewer egress destinations are reachable from every session. |
| **Tampering (T)** | **Improved, marginally.** Fewer packages in `claude-base`, and two fewer images built from unpinned apt indexes. |
| **S, R, D, E** | No change. No mount, capability, user or runtime flag changes. |

Moves 2 and 3 change no runtime control. Their risk is a gate that silently
stops firing, so the following move with the files:

- `container.yml`'s `paths:` filter (`profiles/**`, `config/**`);
- the Case E trigger list in `docs/designs/docs-as-code-workflow.md`
  §3, §4 and §6 (`profiles/base/Dockerfile`, `profiles/base/entrypoint.sh`);
- D-9's list of repository-only path prefixes (`profiles`, `config`). Without
  it, a global-layer file citing `profiles/base/Dockerfile` would pass.

**Residual.** The allowlist remains global rather than per profile. A future
Rust profile adds the crates.io hosts to every session.

## Consequences

- `CONTAINER_FLOOR` drops from 31 to 29.
- R-5 skips whenever every non-base profile is built. With only `crypto`
  left, that covers more hosts than before; the skip already exists (#159).
- Operators with a root-level `config.local.sh` must move it once. The abort
  message says how.
- `build.sh` now applies the registry checks in `lib/config.sh`, so it prints
  the same redefinition warning `start.sh` does.
- Historical design documents and plans keep the old paths. They are records,
  and D-11 does not check non-`docs/` paths.

## Alternatives considered

- **Keep `research` under a less ambiguous name (`latex`).** Rejected: the
  profile is not in use, and renaming leaves its CI and egress costs in
  place.
- **A per-profile directory key, as in dev-env's `containerfile_dir`.**
  Rejected: it would add a way to point a build at an arbitrary directory,
  for no current need.
- **Rename to `config/defaults.sh` and `config/local.sh`.** Rejected: more
  churn in messages and test assertions, for a cosmetic gain.
- **Warn on a legacy `config.local.sh` instead of aborting.** Rejected: a
  warning scrolls past, and the session would then run with silently reverted
  limits or engine.

## Implementation plan

Stacked branches, one pull request each.

1. `chore/0189-retire-systems-research`
   1. `docs: design for profile realignment and repository layout (#0189)`
   2. `chore(profiles): retire the systems and research profiles (#0189)`
   3. `build(squid): remove the systems and research allowlist entries (#0189)`
   4. `build(base): drop sqlite3 and libsqlite3-dev (#0189)`
   5. `docs: record Change 27 and update docs for the retired profiles (#0189)`
2. `refactor/0189-profiles-dir`, on top of 1
   1. `refactor: move profile build contexts under profiles/ (#0189)`
   2. `docs: update paths for profiles/ (#0189)`
3. `refactor/0189-config-dir`, on top of 2
   1. `refactor(config): move config files under config/ (#0189)`
   2. `docs: update paths for config/ (closes #0189)`
