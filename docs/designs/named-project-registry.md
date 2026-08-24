# Named Project Registry

## Status
Draft

## Context

`docs/designs/sandbox-config-file.md` centralized profile, image, engine,
and resource configuration into `config.sh`, layered four ways
(`default_values ← config.sh ← config.local.sh ← env var`). That document
explicitly scoped out one element of the `dev-env` config pattern it drew
from — a named project registry:

> | `[projects.<name>]` registry + `$PROJECT_BASE` | **No (v1)** | Confirmed out of scope with the operator — `start.sh`'s positional `<project_dir>` interface stays as-is. |
>
> — `sandbox-config-file.md` line 93, reaffirmed at line 275

That row is worth re-reading against its neighbours. Every other declined
element in that table carries a substantive argument: `runtime.forbidden_flags`
has no analogue because `start.sh` never assembles its run command from
supplied input; `[registry] allowed[]` duplicates a control already
implemented as digest-pinning; `[defaults]` has no second consumer. The
projects row has no such argument — it records a scoping decision, not a
rejection on merits. This document reopens it on that basis, and supersedes
that single row.

### What exists today

`start.sh` takes its target directory positionally and resolves it against
the current working directory:

```bash
PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"
IMAGE_TAG="${2:-base}"
```

— `start.sh` lines 75–77

The directory is then validated (lines 85–88), the profile is checked
against `PROFILES` (lines 90–94), and `PROJECT_DIR` is bind-mounted at
`/workspace` (line 162).

### The problem

Two distinct problems, of unequal weight.

**1. Repetition (the real motivation).** Every session requires typing a
full path and remembering the correct profile. `./start.sh ~/projects/mylib crypto`
is retyped or shell-history-searched on every invocation, and the path is
machine-specific.

**2. The project→profile pairing is undocumented and unenforced (the
partial motivation).** Nothing anywhere in the repository records that
`mylib` is a cryptography project that belongs on the `crypto` profile.
Running `./start.sh ~/projects/mylib base` succeeds silently and gives the
session a toolchain missing everything the project needs. The correct
pairing lives only in the operator's memory and shell history.

### Honest scope of the auditability claim

This change makes the project→profile mapping a declarative,
version-controlled, diffable fact. That is a genuine improvement over
shell history.

It is **not** an enforcement control, and this document does not claim it
as one. `start.sh` must keep accepting arbitrary paths for ad-hoc work —
scratch directories, one-off clones, `$(pwd)` with no arguments — so the
registry is bypassable by construction: an operator who types a path
instead of a registry name skips it entirely. An audit trail with a
one-token bypass documents intent; it does not enforce it.

Making it an actual control would require a strict mode that rejects
unregistered paths. That is rejected below — it is the wrong shape for a
single-user local workstation whose threat model
(`docs/claude_code_security_plan.md`, Scope) has no external reviewing
body, and it would break the ad-hoc workflow the tool is used for daily.

## Decision

Add a named project registry to `config.sh`, addressed through a `@name`
sigil in `start.sh`'s existing first positional argument. `config.local.sh`
may additively extend the registry with machine-local entries, under the
add-only constraint in "Layering: `config.local.sh` may add, not override"
below.

### Data structure: two parallel associative arrays

Bash has no nested data structures, so `dev-env`'s `[projects.<name>]`
block — which carries both a path and a profile per project — maps onto
two associative arrays keyed identically:

```bash
# ── Project Registry ─────────────────────────────────────────────
# Maps a project name to its path and its default profile. Addressed
# from start.sh as "@<name>" (e.g. ./start.sh @mylib).
#
# ${PROJECT_BASE} keeps this file portable across machines: it is the
# one machine-specific value, and it is resolved from the environment
# with a sensible default rather than being hardcoded here.

PROJECT_BASE="${PROJECT_BASE:-$HOME/projects}"

declare -A PROJECT_PATH=(
    [mylib]="${PROJECT_BASE}/mylib"
)

declare -A PROJECT_PROFILE=(
    [mylib]=crypto
)
```

Two arrays rather than one delimited array (`[mylib]="crypto:${PROJECT_BASE}/mylib"`)
because a delimiter would need parsing and would break on any path
containing the delimiter character. The cost of the two-array form is that
they can fall out of sync — a name present in one and absent from the
other — which is handled by explicit validation below rather than left as
a latent failure.

### `${PROJECT_BASE}` and machine portability

The registry's committed core lives in `config.sh` (reviewed, shared by
everyone); `config.local.sh` may additively extend it per-machine, under
the add-only constraint described below in "Layering: `config.local.sh`
may add, not override". Both files benefit from the same portability
mechanism, so it is established here regardless of which file a given
entry lives in.

That placement is only tenable with the `${PROJECT_BASE}` indirection.
Writing `/home/fernando/projects/mylib` into a committed, shared file
hardcodes one operator's filesystem layout into project-wide
configuration; writing `${PROJECT_BASE}/mylib` does not. This is precisely
why `dev-env`'s `config.toml` uses the same mechanism (lines 96–105 of
that file) and can claim to be "identical across all machines".

`claude-sandbox` gets the expansion for free where `dev-env` needed
`os.path.expandvars()`: `config.sh` is sourced Bash, so `"${PROJECT_BASE}/mylib"`
expands at source time with no parser involved.

**Unset behavior:** `PROJECT_BASE` defaults to `$HOME/projects` when not
exported. Confirmed with the operator. This fails safe — if the default is
wrong for a given machine, the resolved path does not exist and
`start.sh`'s existing directory check (lines 85–88) rejects it before any
mount is constructed. No new failure mode is introduced, and no mandatory
setup step is added to `BUILDING.md`.

### Interface: the `@name` sigil

**This is the part of the design that matters most, and the reason a bare
name is rejected.**

`start.sh`'s first positional argument is currently always a path,
resolved through `realpath` against the current working directory. If it
could *also* be a registry name, the two interpretations collide — and not
hypothetically:

```bash
cd ~/.claude-sandbox
./start.sh crypto     # the ./crypto Dockerfile directory? or a project named crypto?
```

`crypto/`, `systems/`, `research/`, and `base/` are all real directories in
the repository root, and all are plausible project names. Any
disambiguation heuristic ("look up the registry only if the argument
contains no `/` and does not resolve to an existing directory") has a
silent-wrong-answer branch: from the repo root, `./start.sh crypto` would
resolve to the Dockerfile directory and shadow the registry entry entirely.

The consequence of a wrong resolution here is not a confusing error — it
is the **wrong host directory bind-mounted at `/workspace`**, which is the
entire trust boundary of the sandbox. Of every input this script accepts,
this is the one where a silent wrong answer costs the most. Adding
ambiguity to it in the name of auditability would be a net negative on
exactly the axis this change exists to improve.

The sigil is unambiguous by construction — no heuristic, no precedence
rule, no collision case:

```
./start.sh @mylib                    # registry path + registry profile
./start.sh @mylib systems            # registry path, profile overridden positionally
./start.sh ~/projects/thing crypto   # unchanged
./start.sh                           # unchanged — defaults to $(pwd), base
```

It also keeps `start.sh`'s interface **purely positional**, which matters:
`sandbox-config-file.md` lines 186–187 records that the no-flag-parsing
decision was confirmed with the operator, on the grounds that the
interface has been positional since the project began. A `--project`
flag would reopen that decision; `@` does not. The sigil is additionally
self-documenting at the call site — reading a command in shell history
tells you immediately whether it used the registry.

A leading `@` is legal in a POSIX filename, so a directory literally named
`@mylib` becomes unaddressable by relative path. This is accepted: such a
name is vanishingly rare, and the escape hatch is to pass an absolute or
`./`-prefixed path, which is unaffected.

### Resolution and validation

Registry resolution happens after the config layers are sourced and
before the existing directory check, so that a resolved registry path
flows into exactly the same validation an explicit path receives.

```bash
PROJECT_ARG="${1:-$(pwd)}"
IMAGE_TAG="${2:-}"

if [[ "$PROJECT_ARG" == @* ]]; then
    PROJECT_NAME="${PROJECT_ARG#@}"

    if [ -z "$PROJECT_NAME" ]; then
        echo "Error: '@' is not a project name."
        exit 1
    fi

    # ':-' is required: under 'set -u' a lookup on a missing associative
    # array key aborts the script with a bash error instead of reaching
    # the message below.
    RESOLVED_PATH="${PROJECT_PATH[$PROJECT_NAME]:-}"
    if [ -z "$RESOLVED_PATH" ]; then
        echo "Error: unknown project '$PROJECT_NAME'."
        echo "Registered projects: ${!PROJECT_PATH[*]}"
        echo "Add it to config.sh, or pass a path instead."
        exit 1
    fi

    RESOLVED_PROFILE="${PROJECT_PROFILE[$PROJECT_NAME]:-}"
    if [ -z "$RESOLVED_PROFILE" ]; then
        echo "Error: project '$PROJECT_NAME' has a path but no profile in config.sh."
        exit 1
    fi

    PROJECT_ARG="$RESOLVED_PATH"
    IMAGE_TAG="${IMAGE_TAG:-$RESOLVED_PROFILE}"
fi

PROJECT_DIR="$(realpath "$PROJECT_ARG")"
IMAGE_TAG="${IMAGE_TAG:-base}"
```

Four properties this establishes:

1. **`set -u` safety.** `start.sh` runs under `set -euo pipefail` (line
   32). Every registry read is `:-`-guarded, so an unknown name produces
   the intended message rather than `bad array subscript`.
2. **Array sync is checked, not assumed.** A name in `PROJECT_PATH` with
   no `PROJECT_PROFILE` entry is reported explicitly — the failure mode
   the two-array structure introduces is closed at its only read site.
3. **Positional override is preserved.** `IMAGE_TAG` is defaulted only
   after registry resolution, so an explicit second argument wins over the
   registry's profile. The registry supplies a *default*, not a lock.
4. **No validation is bypassed.** The resolved path goes through the same
   `realpath`, the same directory check (lines 85–88), and the same
   profile check against `PROFILES` (lines 90–94) as any explicit path.
   `start.sh` gains a resolution step, not a second code path.

### Layering: `config.local.sh` may add, not override

**Revised from the original draft.** This document originally kept the
registry `config.sh`-only and documented — but did not enforce — that
`config.local.sh` should not touch it. Revisited: `dev-env`'s
`config.local.toml` (`automation-sdd-v3.1-config-local-override.md`) faced
the identical underlying need, and its own motivating problem was an
unprotected, untracked `configuracion.toml` holding an operator's real
per-machine project list — exactly the failure mode of leaving
`claude-sandbox`'s equivalent undocumented rather than designed for. That
precedent, plus the fact that Bash's inability to seal an array meant the
original prohibition was unenforced prose to begin with, is why this
document now designs the extension in rather than declining it.

**What's allowed:** a name present only in `config.local.sh` — not in
`config.sh`'s `PROJECT_PATH` — is added to the registry unrestricted, same
resolution path as any committed entry.

**What's not allowed:** `config.local.sh` redefining a name `config.sh`
already registers. This is not the same hazard class as `dev-env`'s
`[registry]`/`runtime.forbidden_flags` protection — claude-sandbox has no
analogue to either (see the carry-over table in `sandbox-config-file.md`).
The hazard here is identity, not a key namespace: a name an operator
trusts because it's committed and reviewed silently resolving to a
different, unreviewed path is the same silent-wrong-mount failure the `@`
sigil exists to eliminate for the bare-name/directory collision case.
Letting `config.local.sh` shadow a committed name would reopen that hazard
one layer up, invisibly — the sigil disambiguates *which* interpretation
`start.sh` uses, but does nothing about a committed interpretation being
quietly redirected.

**Mechanism** — snapshot the committed names before `config.local.sh` is
sourced, and revert with a warning if it changed one:

```bash
[ -f "${SANDBOX_DIR}/config.sh" ] && source "${SANDBOX_DIR}/config.sh"

declare -A COMMITTED_PROJECT_PATH=()
declare -A COMMITTED_PROJECT_PROFILE=()
for name in "${!PROJECT_PATH[@]}"; do
    COMMITTED_PROJECT_PATH[$name]="${PROJECT_PATH[$name]}"
    COMMITTED_PROJECT_PROFILE[$name]="${PROJECT_PROFILE[$name]:-}"
done

[ -f "${SANDBOX_DIR}/config.local.sh" ] && source "${SANDBOX_DIR}/config.local.sh"

for name in "${!COMMITTED_PROJECT_PATH[@]}"; do
    if [[ "${PROJECT_PATH[$name]:-}" != "${COMMITTED_PROJECT_PATH[$name]}" ]] \
    || [[ "${PROJECT_PROFILE[$name]:-}" != "${COMMITTED_PROJECT_PROFILE[$name]}" ]]; then
        echo "Warning: config.local.sh redefines committed project '$name';" \
             "ignoring the local value (config.sh wins)." >&2
        PROJECT_PATH[$name]="${COMMITTED_PROJECT_PATH[$name]}"
        PROJECT_PROFILE[$name]="${COMMITTED_PROJECT_PROFILE[$name]}"
    fi
done
```

This slots into `start.sh`'s existing layer-sourcing lines (60 and 63) —
no new sourcing step, just the snapshot/restore bracketing it. It runs
once per invocation, over however many names `PROJECT_PATH` holds, so
cost is proportional to registry size, not a concern at the scale this
registry operates at.

Three deliberate choices in that mechanism:

1. **Warn-and-revert, not warn-and-allow.** `dev-env`'s `_strip_protected`
   strips rather than merges protected keys; the same shape is used here —
   the local value is discarded, not just flagged, so a stale or mistaken
   local override can't silently win. An operator who genuinely wants to
   repoint a committed name edits `config.sh`, a one-line, reviewed
   change.
2. **Keyed on name collision, not a fixed path list.** `dev-env` protects
   two fixed schema paths because they're the corporate-gated controls.
   claude-sandbox's registry has no such fixed set to protect — any
   committed name is equally trust-bearing — so the check is "does this
   name already exist in the committed snapshot," evaluated against
   whatever `config.sh` happens to contain, not a hardcoded list.
3. **Two-array sync validation is unchanged.** The existing `:-`-guarded
   read-site check (see Resolution and validation, above) already covers
   a name present in one array but not the other, regardless of which
   file supplied it — `config.local.sh` adding `PROJECT_PATH[foo]` without
   a matching `PROJECT_PROFILE[foo]` surfaces the same "has a path but no
   profile" error an inconsistent `config.sh` entry would. This case does
   not need cross-file handling beyond what already exists.

### What is deliberately not included

- **No strict mode.** Ad-hoc paths remain fully supported. See the
  auditability scope discussion above.
- **No override of a committed name from `config.local.sh`.** Addition is
  supported (see Layering, above); redefinition is actively reverted, not
  merely discouraged in prose — the distinction this revision introduced.
- **No change to container naming.** `start.sh` line 233 names the
  container from `basename "$PROJECT_DIR"`. Using the registry name
  instead would be a marginal readability gain in `podman ps` output, but
  it changes an output format the runtime-posture tests inspect. Out of
  scope.
- **No `build.sh` change.** `build.sh` contains no reference to projects
  and gains none — it builds images, which are project-independent.
- **No `Makefile` or `helpers.py`-equivalent CLI.** Rejected in
  `sandbox-config-file.md` lines 277–280 for reasons unaffected by this
  change.

### Case classification (docs-as-code-workflow.md)

This is **Case C** — a structural change introducing a new abstraction
(the registry) spanning `config.sh`, `start.sh`, and the committed
example template.

It does **not** trigger **Case E**. That case's trigger is a specific file
list — `base/Dockerfile`, `base/entrypoint.sh`, `squid/squid.conf`, or the
`permissions` block in `settings.json` (workflow doc §6, "Container
security control") — and this change touches none of them.

That said, the trigger being a file list rather than a substance test
deserves an explicit note here, because this change *does* touch how the
`/workspace` mount path is resolved, and `sandbox-config-file.md` lines
288–298 set the precedent of arguing this boundary rather than assuming
it. Three reasons no STRIDE section is required:

- The change adds a **resolution step in front of** the existing path
  validation, not a replacement for it. Every mount still passes through
  the same `realpath` and directory check.
- The set of reachable directories is **not widened**. Any path the
  registry can resolve to was already reachable by typing it directly;
  the registry is an alias mechanism over an existing capability.
- The container's security posture — `--cap-drop=ALL`,
  `--security-opt=no-new-privileges`, `--userns=keep-id`, resource limits,
  log driver — is untouched.

The one substantive risk in the area (ambiguous resolution mounting an
unintended directory) is what the sigil design eliminates by construction,
and is the reason a bare-name interface was rejected rather than
mitigated. This reasoning is unaffected by allowing `config.local.sh` to
add registry entries (see Layering, above): an added entry is still just
an alias for a path that was already reachable by typing it directly, and
the warn-and-revert guard keeps a *committed* name's resolution from being
altered by an uncommitted file — the specific case that would have
reopened this risk. If a future change introduces a strict mode, or lets
the registry resolve to paths not otherwise reachable, that change should
be re-evaluated against Case E at that time.

## Consequences

**Easier:**

- `./start.sh @mylib` replaces `./start.sh ~/projects/mylib crypto` — the
  primary, everyday motivation.
- The project→profile pairing becomes a reviewable line in a
  version-controlled file rather than an unwritten convention. `git log`
  on `config.sh` answers "when did mylib move to the systems profile, and
  why" where nothing answered it before.
- A mis-typed profile for a registered project becomes impossible in the
  common path — the profile arrives from the registry, not from memory.
- Onboarding a second machine reduces to exporting `PROJECT_BASE` and
  cloning; the registry itself travels with the repository.
- Registered projects become enumerable: `${!PROJECT_PATH[*]}` gives the
  error path a useful listing, and future tooling a source of truth.

**Harder / trade-offs:**

- **The registry adds a concept with exactly one consumer.** The v1
  `config.sh` change was justified by *removing* duplication between
  `build.sh` and `start.sh`; this change has no such structural
  justification — `build.sh` never reads it. It is purely additive
  surface area, justified by convenience alone. That is a weaker
  warrant than v1's, and it should be held to it: if the registry is not
  actually used day to day, it should be removed rather than maintained.
- **Two arrays can drift.** Mitigated by the explicit sync check at the
  read site and by a bats assertion, but it remains a structure that a
  nested format (TOML) would not have.
- **`config.sh` now contains paths, not just build metadata.** It grows a
  second kind of content, and the `${PROJECT_BASE}` indirection is a small
  amount of ceremony a reader must understand to see why the file is
  still machine-portable.
- **The audit property is soft by design in one way, and enforced in
  another.** It is bypassable by typing a path instead of a registry name
  — accepted, see the auditability scope discussion above. Unreviewed
  *additions* via `config.local.sh` are now an explicit, supported part of
  the design rather than an unblocked side effect (see Layering, above);
  what stays enforced is that they cannot silently redefine a name the
  committed registry already vouches for. For any name that lives only in
  `config.local.sh`, the claim remains "the repository records intent, not
  what ran" — true of any gitignored file, and unchanged by this revision.
- **One more thing to keep current.** A project that moves or is archived
  leaves a stale registry entry that fails only at session start. The
  failure is loud and safe (the directory check rejects it), but the
  registry is not self-maintaining.
- **A directory literally named `@something` is no longer addressable by
  bare relative path.** Accepted; absolute and `./`-prefixed paths are
  unaffected.

## Alternatives considered

- **Bare name with a disambiguation heuristic** (`./start.sh mylib`,
  registry consulted when the argument has no `/` and no matching
  directory). **Rejected** — this is the central design hazard. From the
  repository root, `./start.sh crypto` would silently resolve to the
  `crypto/` Dockerfile directory and shadow a registry entry of the same
  name, bind-mounting the wrong directory at `/workspace`. A
  silent-wrong-answer branch on the sandbox's trust boundary is not an
  acceptable cost for saving one character.
- **`--project mylib` / `-p mylib` flag.** Rejected: reopens the
  no-flag-parsing decision confirmed with the operator twice
  (`sandbox-config-file.md` lines 186–187, and the same doc's rejection of
  CLI flags for layer 4), and requires introducing argument parsing to a
  script that has never had it. The sigil achieves the same
  disambiguation with no interface-model change.
- **Registry entirely in `config.local.sh` (gitignored), nothing in
  `config.sh`.** Rejected. It is the cleanest layering argument in
  isolation — project paths genuinely are machine-specific — but it
  abandons the auditability motive completely, leaving only typing
  convenience, which does not justify the design work. `${PROJECT_BASE}`
  resolves the portability objection that motivated this option, which is
  why the adopted design keeps a committed core instead of reaching for
  this.
- **Registry in `config.sh`, additively extendable from `config.local.sh`,
  with no protection against override.** This is the shape originally
  considered and declined for v1 ("available later if a real need
  appears"). Revisited and adopted, with one change from what v1 sketched:
  override of a committed name is reverted-and-warned rather than left to
  merge silently (see Layering, above). Without that guard, "which profile
  does project X use" for a *committed* name would stop being answerable
  from the repository alone the moment a local file could quietly redirect
  it — the exact property the plain additive version was originally
  declined for. Restricting the guard to name collisions, rather than
  reinstating the full rejection, keeps that property for every name
  `config.sh` actually registers while still allowing the addition
  `dev-env`'s precedent showed is the real-world need.
- **Strict mode (reject unregistered paths).** Rejected: would convert
  the registry from documentation into enforcement, but at the cost of
  breaking ad-hoc use, which is a primary workflow for a single-user
  local tool. The threat model
  (`docs/claude_code_security_plan.md`, Scope) has no external reviewer
  whose assurance would justify that trade.
- **Single array with a delimiter** (`[mylib]="crypto:${PROJECT_BASE}/mylib"`).
  Rejected: requires parsing, and breaks on any path containing the
  delimiter. Two keyed arrays plus an explicit sync check is simpler to
  read and to validate.
- **TOML + a parser, matching `dev-env` directly.** Rejected for the
  reasons already settled in `sandbox-config-file.md` lines 349–359 —
  introducing Python or `yq` as a host prerequisite for a pure-Bash
  project. Nothing about a project registry changes that calculus; if
  anything the two-array shape is the last piece of config simple enough
  not to need one.

## Implementation plan

Each step is a single-file atomic commit except where noted. Issue number
to be substituted once the tracking issue is open.

1. **`config.sh`** — add the `PROJECT_BASE` default, `PROJECT_PATH`, and
   `PROJECT_PROFILE` arrays with a header comment explaining the
   `${PROJECT_BASE}` indirection and the `@name` addressing. Seed with a
   commented-out example block only — no real project entries, so the
   commit introduces the mechanism without asserting any operator's
   layout. No behavior change yet.
   `feat(config): add project registry arrays to config.sh (#N)`

2. **`start.sh`** — add the `@name` resolution block between argument
   capture and `realpath`, per the shape above. Update the usage header
   comment (lines 1–17) with the new grammar and an `@name` example.
   Regression gate: `bats tests/test_runtime_posture.bats tests/test_global_layer.bats`
   must pass unchanged, since no existing invocation form is altered.
   `feat(start): resolve @name project references from the registry (#N)`

3. **`start.sh`** — bracket the existing `config.sh`/`config.local.sh`
   sourcing (today's lines 60 and 63) with the committed-name snapshot and
   the warn-and-revert diff, per "Layering: `config.local.sh` may add, not
   override" above. Separate commit from step 2: same file, but a distinct
   concern (layering enforcement vs. argument resolution) at a different
   point in the script.
   `feat(start): protect committed project names from local override (#N)`

4. **`tests/test_config.bats`** — extend the existing config-layering
   suite with registry cases: (a) `@name` resolves to the registered path
   and profile; (b) an explicit second argument overrides the registry
   profile; (c) an unknown `@name` exits non-zero with the "unknown
   project" message and does not start a container; (d) a name present in
   `PROJECT_PATH` but absent from `PROJECT_PROFILE` is reported rather
   than aborting on `bad array subscript` — the `set -u` regression the
   `:-` guards exist for; (e) a bare argument matching a registry name is
   still treated as a path, confirming the sigil boundary holds; (f) a
   name added only in `config.local.sh` resolves correctly; (g)
   `config.local.sh` attempting to redefine a name already in `config.sh`
   is reverted to the committed value, with a warning on stderr and no
   change to the command's exit code.
   `test(config): add project registry resolution tests (#N)`

5. **`config.local.sh.example`** — add an example `[projects]`-style block
   (commented out) showing a machine-local addition, plus a note that
   redefining a name already present in `config.sh` is silently reverted
   with a warning rather than honored — parallel to the existing note at
   lines 25–27 explaining why `PROFILES` is not locally overridable.
   `docs(config): document project registry additions in config.local.sh (#N)`

6. **Documentation** — `ARCHITECTURE.md` (directory-layout description of
   `config.sh`, and a Cheat Sheet entry for `@name`), `docs/user_guide.md`
   (the everyday invocation form and the add-only `config.local.sh`
   extension), and `BUILDING.md` if `PROJECT_BASE` warrants a mention in
   setup. Tightly coupled — one commit.
   `docs: document the named project registry (closes #N)`

No ADR is proposed. The binding architectural decisions this change rests
on — sourced Bash over a parsed format, positional-only interface,
`config.sh`/`config.local.sh` layering — were all made in
`sandbox-config-file.md`; this document applies them rather than deciding
anything new of that weight. `docs/adr/` remains empty, as it is today.
