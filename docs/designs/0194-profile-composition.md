# Profile composition

## Status
Accepted

## Context

A session runs exactly one profile image, `${IMAGE_PREFIX}-<profile>`, and
every child profile is built `FROM claude-base`. A project that needs two
toolchains has one route today: a hand-written Dockerfile that restates
both members and drifts from them.

The requirement (#194):

- Named combinations. Committed definitions in `config/config.sh`; per-machine
  additions in `config/config.local.sh`, which may add names but not redefine
  committed ones. This is the layering the project registry already follows
  (`docs/designs/0030-named-project-registry.md`, "Layering: config.local.sh
  may add, not override").
- An arbitrary combination at the command line is a nice-to-have, not a
  requirement.

Constraints found in the current tree:

- `crypto` is the only child profile. Nothing can be composed until a second
  one exists, so the mechanism is tested on fixture profiles (§Decision 6).
- `profiles/crypto/Dockerfile` hard-codes `FROM claude-base`, while `build.sh`
  tags the base `${IMAGE_PREFIX}-base`. With a non-default `IMAGE_PREFIX`,
  which `config.local.sh.example` offers, `crypto` builds on a stale or
  missing `claude-base`. Decision 1 fixes this as a side effect.
- Profile overlays (`global-<profile>/`) are mounted directly as
  `/run/claude-overlay`. No profile has one today.

## Decision

1. **Child profiles take their parent as a build argument.**
   - Every child Dockerfile opens with `ARG PARENT_IMAGE=claude-base` and
     `FROM ${PARENT_IMAGE}`. A standalone build is unchanged, so B-3 keeps
     its meaning.
   - `build.sh` passes `--build-arg PARENT_IMAGE=${IMAGE_PREFIX}-base` when
     it builds a profile on its own, and the previous member's image when it
     builds a combination (Decision 3).
   - The profile contract, which a combination relies on:
     - exactly one `FROM`, the one above;
     - root work starts with an explicit `USER root`, and the file ends as
       `USER claude-agent`: a member cannot assume which user its parent
       left active;
     - no `ENTRYPOINT` or `CMD`, since `claude-base` owns both (the redundant
       `CMD ["claude"]` in `crypto` goes);
     - every `ENV PATH=` extends `${PATH}` rather than replacing it.
   - A hostonly test checks every child Dockerfile against the contract, so
     the contract is enforced rather than documented.

2. **Combinations are a `COMBOS` map in the config layers.**

   ```bash
   # config/config.sh
   declare -A COMBOS=(
       # [crypto-rust]="crypto rust"
   )
   ```

   - The value is an ordered member list, and order is build order.
   - `lib/config.sh` declares `COMBOS` empty before layer 2, snapshots the
     committed map after it, and after layer 3 reverts any committed name
     that `config.local.sh` redefined, with a warning. This is the registry's
     rule and mechanism, applied to a second map.
   - `validate_combos` in `lib/config.sh`, called by `build.sh` and
     `start.sh`, aborts on the first invalid definition, naming it. A
     definition is valid when:
     - the name matches `^[a-z0-9][a-z0-9-]*$` and is neither a profile
       name nor a reserved target (`all`, `squid`);
     - it has at least two members, without repeats;
     - every member is a profile in `PROFILES`, is not `base`, and has
       `PROFILE_BASE` equal to `base`.
   - `creds.sh` and `check-auto-memory.sh` do not validate. A typo in a
     combination does not block credential management.

3. **A combination builds as a chain of member builds.**
   - `./build.sh <combo>` builds `base`, then the first member as its own
     profile image, then each later member on top of the previous result.
   - The last member is tagged `${IMAGE_PREFIX}-<combo>`. With three or more
     members, each intermediate result is tagged
     `${IMAGE_PREFIX}-<combo>:part-<n>`, so a later build can name it as a
     parent.
   - `./build.sh` with no target builds base, every profile, every
     combination in name order, then `squid`. The usage message lists
     combinations next to profiles.

4. **`start.sh` accepts a combination wherever it accepts a profile.**
   - As the second argument, or as a `PROJECT_PROFILE` value. The
     unknown-image error lists both sets.
   - Runtime flags, mounts and the proxy are unchanged: they do not depend on
     the profile.

5. **Overlays are not composed yet.**
   - `start.sh` refuses a combination when any member has a
     `global-<member>/` directory, and names the member. Picking one overlay,
     or none, would silently drop the others.
   - `start.sh` never reads `global-<combo>/`.
   - Merging member overlays is deferred until a profile has an overlay
     (§Alternatives considered).

6. **Tests.**
   - Hostonly (C-group):
     - the profile contract over every child Dockerfile (Decision 1);
     - a valid combination resolves in `build.sh` and `start.sh` with a stub
       engine;
     - every invalid case in Decision 2 aborts, naming the rule it breaks;
     - a `config.local.sh` redefinition is reverted and warned, and an
       addition is honoured;
     - `build.sh <combo>` issues the chained builds in member order, each
       with the expected `PARENT_IMAGE`;
     - a combination with a member overlay is refused.
   - Container tier:
     - two fixture profiles under `tests/fixtures/`, each writing a marker
       file and extending `PATH`, built as a combination in a scratch copy of
       the tree. The test asserts both markers, both `PATH` entries,
       `whoami` = `claude-agent`, and that the entrypoint ran.
     - each committed combination passes every member's smoke test. While
       none is committed, the test skips with a message rather than passing
       an empty loop.
   - `HOSTONLY_FLOOR` and `CONTAINER_FLOOR` rise by the number of tests
     added.

## Security impact

Not Case E: no file on the Case E list changes.

| Threat | Change |
|---|---|
| **Elevation of Privilege (E)** | A combination holds the union of its members' packages and group memberships (for example `softhsm`), nothing beyond. User, capabilities and runtime flags are unchanged. |
| **Tampering (T)** | A `config.local.sh` combination builds only reviewed Dockerfiles, but in an order no review or CI run has covered. Accepted: a member that breaks another shows up in that combination's smoke test, on the machine that defined it. |
| **Information Disclosure (I)** | No change. The allowlist is global, so a combination reaches exactly what each member already reaches. |
| **S, R, D** | No change. |

**Residual.** `PROFILES` and `PROFILE_BASE` are kept out of `config.local.sh`
by convention only (`config.local.sh.example`). A local profile could
therefore become a combination member. This predates composition and is not
widened by it.

## Consequences

- No combination exists until a second child profile does. The first real
  one depends on that profile, not on this design.
- Order matters. Files and `ENV` values set by a later member win.
  Per-member smoke tests on the combined image catch a member that breaks
  another.
- After the first member, layers are not shared. Each combination rebuilds
  every later member on a new parent, which costs build time and disk per
  combination.
- A rebuilt member does not rebuild the combinations that contain it.
  `./build.sh <combo>` or `./build.sh` does, as `./build.sh crypto` rebuilds
  base today.
- The profile contract constrains every future child profile. In return, any
  profile meeting it is composable without further work.
- A non-default `IMAGE_PREFIX` now builds children on the matching base.

## Alternatives considered

- **A hand-written Dockerfile per combination**, listed as an ordinary
  profile.
  - Attractive: no new mechanism, and the built file is the reviewed file.
  - Breaks: every combination restates its members and drifts from them,
    which is the problem #194 states.
- **One generated Dockerfile**, concatenated from per-profile fragments.
  - Attractive: a single build, and layers shared within it.
  - Breaks: the file that gets built is not a reviewed file. Profiles stop
    being standalone Dockerfiles, so B-3 loses its meaning.
- **Copy each member's toolchain into base with multi-stage `COPY --from`.**
  - Attractive: each member is built once and combinations are cheap.
  - Breaks: apt installs are spread across `/usr`, the dpkg database, and
    users and groups (`crypto` runs `usermod`). None of that copies reliably.
- **Arbitrary combinations at the command line**, built on demand.
  - Attractive: nothing to configure.
  - Breaks: images no configuration names, built from `start.sh`, outside
    `./build.sh` and CI. Deferred, not foreclosed: Decision 3 builds from an
    ordered member list, so an unnamed list is a thin layer over it.
- **Abort on a local redefinition, instead of revert and warn.**
  - Attractive: louder.
  - Breaks: the registry already reverts and warns (C-13). Two rules for one
    layering would leave operators guessing which applies.
- **Merge member overlays in order now.**
  - Attractive: complete from the start.
  - Breaks: nothing yet, but it is code with no current input, and its
    conflict rule would be designed without a real case. The refusal in
    Decision 5 keeps the gap visible until then.

## Implementation plan

Stacked branches, one pull request each.

1. `refactor/0194-parent-image`
   1. `docs: design for profile composition (#194)`
   2. `refactor(profiles): build child profiles from a PARENT_IMAGE argument (#194)`
      — `crypto` Dockerfile, `build.sh`, and the contract test.
2. `feat/0194-profile-composition`, on top of 1
   1. `feat(config): define and validate named combinations (#194)`
      — `config.sh`, `lib/config.sh`, `config.local.sh.example`, tests.
   2. `feat(build): build a combination as a chain of member builds (#194)`
      — `build.sh`, fixture profiles, tests.
   3. `feat(start): start a session on a combination (#194)`
      — `start.sh`, the overlay refusal, tests.
   4. `ci: raise the test floors for composition (#194)`
   5. `docs: document combinations, ADR for the profile contract (closes #194)`
      — `ARCHITECTURE.md`, `docs/user-guide.md`, and an ADR recording
      Decision 1, which binds every future profile.
