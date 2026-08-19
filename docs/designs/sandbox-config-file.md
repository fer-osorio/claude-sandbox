# Sandbox Config File

## Status
Accepted (revision 2 — adds a layered override mechanism on top of the
previously drafted `config.sh`; the "what carries over from dev-env",
format, and Case classification decisions below are unchanged from
revision 1)

## Context

`claude-sandbox` has just completed its Docker → Podman migration
(`docs/designs/podman-migration.md`), which was explicitly step two of
three pre-merge tasks named in the testing SDD's own introduction:
*"testing → Podman migration → config evaluation"*
(`docs/designs/claude-sandbox-testing-module-sdd.md` line 51). This
document is that third task.

Today, profile and runtime configuration is hardcoded and duplicated
across two files:

- `build.sh` hardcodes the profile list via a `case` statement
  (`base|crypto|systems|research|squid`), the base-before-children build
  order, and a separate `ENGINE="${ENGINE:-podman}"` default.
- `start.sh` independently hardcodes `VALID_IMAGES="base crypto systems
  research"`, its own `ENGINE="${ENGINE:-podman}"` default, and the
  session's resource limits and log-driver options
  (`--memory="2g"`, `--cpus="2"`, `--log-opt max-size=...`) as literals.

The profile list already has to be kept in sync by hand across both
files — a real, pre-existing duplication problem independent of any
comparison to `dev-env`. That duplication is the concrete motivation for
this change; `dev-env` is the reference point because it's a sibling
project (see repo tour, previous turn in this conversation) solving an
adjacent problem — profile-aware containerized dev sessions — with a
`config.toml` + `helpers.py` layer that centralizes exactly this kind of
data.

The two projects' threat models and constraints diverge in ways that
matter for this design:

- `dev-env` targets a **managed corporate Windows/WSL2 laptop** with a
  security team that gates registry approval and reviews `config.toml`
  changes against an ADR/SDD. `claude-sandbox` targets a single-user
  local workstation (`docs/claude_code_security_plan.md`, Scope) — there
  is no external reviewing body and no registry-approval control in its
  existing threat model.
- `dev-env`'s `run.sh` constructs its `podman run` command in a way that
  makes a `forbidden_flags` runtime guard meaningful. `start.sh` has no
  equivalent input path — its sandboxing flags (`--cap-drop=ALL`,
  `--security-opt=no-new-privileges`, `--userns=keep-id`) are written
  directly into the one `run` invocation, not assembled from
  project-supplied input. There is nothing for a forbidden-flags check to
  guard against here.
- `dev-env` is a Python-using project (`helpers.py`, `tomllib`) with a
  named-project registry (`[projects.<name>]`, resolved via
  `$PROJECT_BASE`) and a `Makefile` as its sole public interface.
  `claude-sandbox` is pure Bash today (`build.sh`, `start.sh`, plus
  `tests/lib/engine.bash` for the bats-core harness), has no project
  registry — `start.sh <project_dir> [profile]` takes an ad-hoc directory
  positionally — and no `Makefile`. Per an explicit decision with the
  operator during design, this positional interface stays: v1 is scoped
  to profile/build/runtime config, not a project registry.

**Revision 2 addition.** After agreeing the above, the operator asked for
a second, orthogonal pattern on top of the single `config.sh`: a layered
override chain —

```
default_values  <-  config.sh  <-  config.local.sh  <-  env var
```

— where `config.sh` stays committed (as designed below), and
`config.local.sh` is a new, gitignored, per-machine file: "committed in a
particular user instance" but never in the project itself. This is
motivated by real per-machine variance this project's own docs already
document (WSL2 vs. Fedora, SELinux enforcement, subuid ranges, cgroups v2
delegation quirks — `BUILDING.md`'s Podman-prerequisites section) — an
operator may reasonably want a different default `ENGINE`, or different
`MAIN_MEMORY`/`MAIN_CPUS`, on their own machine without editing a file
that's under code review.

## Decision

### What carries over vs. what doesn't

| dev-env element | Carries over? | Rationale |
|---|---|---|
| Per-profile block shape (`containerfile_dir`, `image_name`, `image_version`, optional `base` dependency edge) | **Yes** | Directly maps onto `build.sh`'s existing base/crypto/systems/research hierarchy; removes the two-file duplication that motivated this change. |
| A single source of truth read by both build and run scripts | **Yes** | Same problem dev-env solved (`setup.sh`/`run.sh` never hand-hardcode profile data); this is the core reusable idea, independent of file format. |
| `[defaults]` username / workspace_mount | **No** | `claude-sandbox`'s user (`claude-agent`) and mount point (`/workspace`) are baked into the Dockerfiles and referenced directly by `start.sh`/`ARCHITECTURE.md`; there's no second consumer that needs them centralized, and `--userns=keep-id:uid=1000,gid=1000` already hardcodes the UID convention per `podman-migration.md` §3.A. |
| `[registry] allowed[] / default` | **No** | This is a corporate approved-registry control gated by a security team review process `claude-sandbox` doesn't have. `claude-sandbox`'s equivalent control is digest-pinning the base image (`podman-migration.md` §5.3), a different and already-implemented mechanism. |
| `runtime.forbidden_flags[]` + `check-forbidden-flags` guard | **No** | No analogue: `start.sh` never assembles its container-run command from project- or user-supplied flags, so there's nothing to check against a denylist. |
| `[projects.<name>]` registry + `$PROJECT_BASE` | **No (v1)** | Confirmed out of scope with the operator — `start.sh`'s positional `<project_dir>` interface stays as-is. |
| `helpers.py` as a Python CLI layer | **No** | See format decision below — introducing Python as a new host dependency isn't justified here. |
| `Makefile` as sole public interface | **No** | `claude-sandbox` has no `Makefile` today and `ARCHITECTURE.md`'s documented Cheat Sheet already treats `build.sh`/`start.sh` as the direct entry points; adding an interface layer is out of scope for a config-centralization change. |
| TOML as the format | **No** | See below. |
| Resource limits / log-driver options as named, version-controlled fields | **Yes (spirit)** | Not present in dev-env's config at all, but the same principle — these are exactly the kind of value dev-env's config.toml header calls "security-relevant and version-controlled" — applies to `start.sh`'s `--memory`/`--cpus`/log-opt literals, which are currently undocumented magic strings. |

### Format: a sourced Bash config, not TOML+Python

`dev-env` uses TOML parsed by `helpers.py` (Python's `tomllib`) because it
was already reasonable to assume a Python toolchain there. `claude-sandbox`
has no Python anywhere — not in `build.sh`, not in `start.sh`, not in the
bats-core test harness. Its established pattern for cross-script shared
logic is `tests/lib/engine.bash`: a plain Bash library, sourced directly,
no parser needed.

**Decision: `config.sh` at the repo root, a plain Bash file defining
arrays and variables, sourced directly by `build.sh` and `start.sh`.**

```bash
# config.sh — profile and runtime defaults for claude-sandbox.
# Sourced directly by build.sh and start.sh. Bash arrays, not a data
# format, so no parser dependency is introduced — consistent with
# tests/lib/engine.bash, this project's existing sourced-library pattern.
#
# Security-relevant values (resource limits, log options) are
# version-controlled here; treat changes to this file with the same care
# as a Dockerfile change.

PROFILES=(base crypto systems research)

# Maps a profile to its base-image dependency. A profile absent from this
# map builds directly (currently only "base" itself).
declare -A PROFILE_BASE=(
    [crypto]=base
    [systems]=base
    [research]=base
)

IMAGE_PREFIX="claude"          # image tag = "${IMAGE_PREFIX}-${profile}"
ENGINE_DEFAULT="podman"        # ENGINE env var still overrides at call time

MAIN_MEMORY="2g"
MAIN_CPUS="2"
MAIN_LOG_MAX_SIZE="50m"
MAIN_LOG_MAX_FILE="5"

PROXY_LOG_MAX_SIZE="10m"
PROXY_LOG_MAX_FILE="3"
```

This gives every consumer (`build.sh`, `start.sh`, and any future bats
test) the same data with zero new host prerequisites — `BUILDING.md`'s
Prerequisites list stays exactly as it is (Podman/Docker, `gh`,
`bats-core`); no `python3` or `yq` binary needs to be added to it.

### Layered overrides: `default_values ← config.sh ← config.local.sh ← env var`

Same mechanism as above — no new format, no new dependency — extended to
four layers instead of one. Each later layer wins over the one before it.

**Layer 1 — `default_values`.** Hardcoded literals at the top of
`build.sh`/`start.sh` themselves, identical in value to what `config.sh`
will also set. This means the scripts still run correctly even if
`config.sh` is deleted or missing — the project doesn't become
non-functional from a missing file.

**Layer 2 — `config.sh`.** Committed, project-wide, reviewed — exactly as
designed above.

**Layer 3 — `config.local.sh`.** New. Gitignored. One operator's
per-machine overrides. Same variable names as `config.sh`, only the
fields the operator actually wants to change:

```bash
# config.local.sh.example — copy to config.local.sh and edit.
# config.local.sh is gitignored — it is never committed to this project.
# Uncomment only the values you want to override on this machine.
# Precedence: default_values < config.sh < config.local.sh < env var.

# ENGINE_DEFAULT="docker"      # prefer Docker over Podman on this host
# MAIN_MEMORY="4g"             # this machine has more RAM to spare
# MAIN_CPUS="4"
```

`config.local.sh.example` (the template above, with every field commented
out) is committed — it's the discoverable list of what's overridable,
the same role `dev-env`'s commented-out `[projects.another-project]`
block plays in its `config.toml`. `config.local.sh` itself is never
committed.

**Layer 4 — env var.** Highest precedence, resolved last, at the point of
use in `build.sh`/`start.sh` — matching the existing `ENGINE` convention
(`ENGINE=docker ./start.sh ...`) rather than adding CLI flag parsing
(confirmed with the operator: `start.sh`'s interface has been purely
positional since the project began, and this change doesn't reopen that).

**Mechanism detail that matters for correctness.** A naive
`VAR="${VAR:-default}"` placed *after* sourcing `config.sh`/`config.local.sh`
does not work as a layer-4 override: once `config.sh` assigns `VAR`, it is
no longer unset, so a later `${VAR:-...}` is a no-op regardless of
whether the operator exported an env var. The env var has to be captured
*before* the two files are sourced, then re-applied after:

```bash
# In build.sh / start.sh, before sourcing anything:
_ENV_ENGINE="${ENGINE:-}"
_ENV_MAIN_MEMORY="${MAIN_MEMORY:-}"
# ... one capture per overridable scalar

# Layer 1: hardcoded defaults
ENGINE="podman"
MAIN_MEMORY="2g"
# ...

# Layer 2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SCRIPT_DIR}/config.sh" ] && source "${SCRIPT_DIR}/config.sh"

# Layer 3
[ -f "${SCRIPT_DIR}/config.local.sh" ] && source "${SCRIPT_DIR}/config.local.sh"

# Layer 4: env var wins over everything sourced above
ENGINE="${_ENV_ENGINE:-$ENGINE}"
MAIN_MEMORY="${_ENV_MAIN_MEMORY:-$MAIN_MEMORY}"
```

**Scope of layer 4:** applies to scalar values only (`ENGINE`,
`IMAGE_PREFIX`, `MAIN_MEMORY`, `MAIN_CPUS`, `MAIN_LOG_MAX_SIZE`,
`MAIN_LOG_MAX_FILE`, `PROXY_LOG_MAX_SIZE`, `PROXY_LOG_MAX_FILE`). Bash's
associative array (`PROFILE_BASE`) and indexed array (`PROFILES`) are not
made env-var-overridable — exporting a shell array through the
environment is not a well-supported cross-shell pattern, and there's no
existing need to override the profile list itself from a single
invocation. Profile changes go through `config.sh` or `config.local.sh`
only.

**`.gitignore`.** `claude-sandbox` has no `.gitignore` today (checked:
none exists at the repo root). This change adds one, with
`config.local.sh` as its first entry. `config.local.sh.example` is
committed normally (not ignored).

**On the risk of accidentally committing `config.local.sh`:** a
`.gitignore` entry is the right amount of protection here, not more.
`settings.json`'s `Write(../*)`-style denylist entries guard against
Claude Code writing outside the project directory — a different threat
(a runaway agent action) from an operator manually `git add`-ing a file
that they, not Claude, created and control. This project's own threat
model scope (`docs/claude_code_security_plan.md`) is a single-user local
workstation with no external reviewer — a `.gitignore` entry (plus, if
it's ever committed by accident, `git rm --cached` and the normal review
process catching an unexpected diff) is proportionate. Building a
pre-commit hook or a `settings.json` write-guard for this would be
over-engineering for a file whose worst-case content is "a different
memory limit."

### v1 scope

**Becomes config-driven:**
- Profile list and base-image dependency edges (replaces `build.sh`'s
  `case` statement and `start.sh`'s `VALID_IMAGES` string).
- Image tag prefix (replaces the hardcoded `claude-` string appearing in
  both files).
- `ENGINE` default (replaces the duplicated `"${ENGINE:-podman}"` line in
  both files — env var override behavior is unchanged).
- Main-container and proxy-container resource limits and log-driver
  options (replaces the literals in `start.sh`'s `run` invocations).
- All of the above, layered four ways (`default_values ← config.sh ←
  config.local.sh ← env var`) rather than a single committed file.

**Stays exactly as it is, out of scope for v1:**
- `squid/squid.conf`'s domain allowlist — explicitly deferred per
  `squid-proxy-integration.md` §3/§9 and reaffirmed in
  `podman-migration.md` §3.C; this document doesn't reopen it.
- The `global-claude/` / `global-<profile>/` overlay mechanism
  (`docs/designs/global-layer-injection.md`) — `config.sh`'s profile
  block adds *build* metadata (Dockerfile dir, image name, base). It does
  not touch, replace, or duplicate the overlay-injection logic, which
  keeps discovering `global-<profile>/` by directory presence exactly as
  today.
- `claude-squid`'s build — stays a special case in `build.sh`, not a
  `PROFILES` entry, matching its existing separate handling (no base
  dependency, no `start.sh`-selectable profile, no UID-matching need).
- A named project registry (confirmed out of scope with the operator,
  see Context).
- A `helpers.py`-equivalent CLI (`list-sessions`, `stop-session`,
  `status`, etc.) — `claude-sandbox` has no `make stop`/`make status`
  today and none was requested; a plain sourced `config.sh` needs no CLI
  wrapper since `build.sh`/`start.sh` read the arrays directly.

### Case classification (docs-as-code-workflow.md)

This is **Case C** — a structural change spanning `build.sh` and
`start.sh`, introducing a new shared component (`config.sh`) that future
changes will build on.

It does **not** trigger **Case E** under this project's own definition:
Case E's trigger list is `base/Dockerfile`, `base/entrypoint.sh`,
`squid/squid.conf`, or the `permissions` block in `settings.json`
specifically — none of which this change touches. The resource-limit and
log-driver *values* are security-relevant, but they are being relocated
verbatim (`2g`/`2`/`50m`/`5`/`10m`/`3` — unchanged from today), not
altered — this is a refactor of where the values live, not a change to
container security posture. No STRIDE section is required. If a future
change to `config.sh` actually *changes* one of these values (not just
moves it), that change should be evaluated against Case E's criteria at
that time, since it would then be altering runtime security posture.

## Consequences

**Easier:**
- Adding a profile becomes one `config.sh` edit (array entry + optional
  `PROFILE_BASE` entry) instead of two hand-synced edits across
  `build.sh`'s `case` statement and `start.sh`'s `VALID_IMAGES` string —
  removes an existing drift hazard.
- Resource limits and log options become named, documented,
  version-controlled values instead of literals buried in `start.sh`'s
  `run` invocation — easier to review and to cite in future STRIDE
  updates to `claude_code_security_plan.md`.
- `ARCHITECTURE.md`'s Strategy A workflow ("add to the relevant
  Dockerfile, rebuild") gets a small, natural extension: also add the
  profile to `config.sh`.
- An operator can tune resource limits or their preferred engine for
  their own machine (`config.local.sh`) without touching a file under
  code review, and without that preference leaking into anyone else's
  checkout or the project's git history.

**Harder / trade-offs:**
- One more file to keep in sync with the Dockerfile directories
  (`base/`, `crypto/`, `systems/`, `research/`) — mitigated by the bats
  regression test in the implementation plan below, which asserts
  `config.sh`'s `PROFILES` matches the directories actually present.
- `config.sh` is executable Bash sourced into two scripts' process state
  — a typo (e.g. a stray command instead of a variable assignment) fails
  differently than a TOML syntax error would (a TOML parser fails
  loudly and immediately; a sourced Bash file can silently execute
  something unintended). Mitigated by keeping `config.sh` data-only (no
  logic, no command substitution beyond simple literals) and by the same
  bats regression test.
- Four layers is more to reason about when debugging "why is my session
  using 4g of memory" — mitigated by having `start.sh` print which value
  it resolved (not just the flag) in its existing startup summary, and by
  the precedence order being identical and documented in one place
  (`config.sh`'s own header comment) rather than different per script.
- `config.local.sh` is, by design, never code-reviewed — it's gitignored
  specifically so it can diverge per machine. This is an accepted,
  deliberate trade-off for a single-user local tool (see the `.gitignore`
  discussion above), not an oversight, but it does mean this project's
  otherwise-universal "everything is version-controlled and auditable"
  property has one narrow, intentional exception.
- The capture-before-source idiom for layer 4 (see above) adds a few
  lines of boilerplate per overridable scalar in both `build.sh` and
  `start.sh` — mechanical, but real line count, and a new contributor
  needs to understand *why* it's not just a trailing `${VAR:-default}`.

## Alternatives considered

- **Port `helpers.py` + TOML as-is.** Rejected: introduces Python as a
  new host prerequisite for a project that is currently pure Bash
  end-to-end, for no benefit `config.sh` doesn't already provide at this
  scope. Revisit only if a future need (e.g. genuinely complex nested
  config, or a CLI wrapper with many subcommands like dev-env's) justifies
  the added dependency.
- **`yq` (YAML/TOML/JSON CLI parser).** Rejected: adds a new host binary
  dependency for the same reason a Python parser would, without even the
  benefit of a language already used elsewhere in the stack.
- **JSON + `jq`.** Same objection as `yq`; also `jq` is not currently in
  `BUILDING.md`'s prerequisites, so it's a wash on shell-nativeness.
- **Add fields to `settings.json`.** Rejected: `settings.json` is
  explicitly scoped in this project's own workflow doc as the file
  governing the Claude Code permission denylist (Case E trigger); mixing
  build/runtime profile config into it would blur that boundary and
  incorrectly widen what counts as a Case E change.
- **Only one committed `config.sh`, no local layer.** Rejected: gives no
  way to tune per-machine values (resource limits, preferred engine)
  without editing a file under code review — an operator would have to
  either commit a personal preference project-wide or keep a local diff
  they must remember to never commit. `config.local.sh` solves this
  directly.
- **A `.env`-style `KEY=value` file for the local layer instead of sourced
  Bash.** Rejected: would require a second read mechanism (a `.env`
  parser) alongside the sourced-Bash `config.sh`, for no real gain —
  `config.local.sh` needs the exact same shape as `config.sh` (it's
  overriding the same variables), so reusing the identical `source`
  mechanism keeps this to one pattern, not two.
- **CLI flags (`--memory=4g`) as the layer-4 override.** Rejected per the
  operator's explicit choice — env vars keep `start.sh` purely positional,
  matching its interface since the project began, and reuse the existing
  `ENGINE=` mental model rather than introducing a new one.

## Implementation plan

1. Add `config.sh` at the repo root with the shape shown above,
   populated with today's actual values (`PROFILES`, `PROFILE_BASE`,
   `IMAGE_PREFIX=claude`, `ENGINE_DEFAULT=podman`, and the resource/log
   values currently hardcoded in `start.sh`), plus a header comment
   stating the full precedence chain (`default_values < config.sh <
   config.local.sh < env var`). No behavior change yet — single-file
   atomic commit.
2. Add `.gitignore` (new file) with `config.local.sh` as its first entry.
   Add `config.local.sh.example` (committed template, all fields
   commented out, per the shape shown above). Single commit.
3. Update `build.sh`: capture pre-set env-var overrides, set layer-1
   hardcoded defaults, `source config.sh` then `source config.local.sh`
   (both guarded by `[ -f ... ]`), re-apply the captured env-var layer,
   replace the `case` statement's per-profile `build_*` dispatch with a
   loop driven by `PROFILES` + `PROFILE_BASE`. `build_squid` stays a
   distinct function, not part of the loop. Regression gate:
   `bats tests/test_build.bats` (`ENGINE=docker` and `ENGINE=podman`)
   must still pass unchanged.
4. Update `start.sh` with the same four-layer resolution, replace
   `VALID_IMAGES` with `PROFILES` (and its derived error message), and
   replace the `--memory`/`--cpus`/log-opt literals with the resolved
   values. Regression gate: `bats tests/test_runtime_posture.bats
   tests/test_global_layer.bats` unchanged.
5. Add a bats regression test (new `tests/test_config.bats` or an
   addition to an existing file) asserting: (a) `config.sh`'s `PROFILES`
   matches the profile directories actually present in the repo root,
   (b) `build.sh`/`start.sh` derive identical profile lists from it, and
   (c) an env var override (e.g. `ENGINE=docker`) still wins even when
   `config.sh`/`config.local.sh` set a different value — the specific
   correctness property the capture-before-source idiom exists for.
6. Update `ARCHITECTURE.md`'s "Add a tool permanently" / Strategy A
   section and `BUILDING.md` to mention `config.sh`, `config.local.sh`,
   the precedence chain, and the (now one-file-for-shared,
   one-file-for-personal) procedure for adding or tuning a profile.
7. Single commit closing the tracking issue, per Case C convention.
