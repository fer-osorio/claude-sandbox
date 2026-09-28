---
status: Approved
date: 2026-09-20
phase: planning
owner: project-feasibility
---

# Feasibility

## TL;DR

Buildable, and smaller than it looks: the insertion point is four lines in
`start.sh` and the test harness already exists. The binding constraints are
not technical — they are the key-lifecycle procedure a person must
rehearse, and a documentation cost larger than the code.

## Technical

The insertion point already exists and is small. `start.sh:235` builds
`ENV_ARGS` as a name-only `-e GH_TOKEN`, which is exactly the mechanism the
scope generalizes, and `PROJECT_DIR` is resolved at `start.sh:146` after
`@name` resolution — so path keying needs no special-casing for registered
projects. Fail-closed has precedent in the same file: a Squid proxy that
fails to start aborts the session (`start.sh:288`).

Test scaffolding exists too. `tests/test_config.bats` already copies
`start.sh` into a temp directory and runs it under `ENGINE=true`, a no-op
engine stand-in. All three cases in
`docs/planning/0129-encrypted-credential-store/scope.md §Definition of done`
fit that harness without new infrastructure.

One correction to the framing: `age` is a *host* dependency, since
`start.sh` runs on the host. The interpreter discipline governing
image-baked toolchains does not apply. It does add a row to BUILDING.md
§Prerequisites, and a missing `age` must abort rather than silently skip —
otherwise the failure is indistinguishable from "no credentials
configured".

Nothing in the container changes: `base/entrypoint.sh` and the images are
untouched.

## Operational

Single operator, already fluent in this codebase's shell idiom —
every layering, fail-closed and registry pattern this needs is one they
wrote. No new language or runtime.

The real operational cost is not the code, it is the key lifecycle: a
passphrase-protected identity with no backup is an unrecoverable store, and
backup/recovery is a procedure a person must actually perform and rehearse,
not a function to write.

Capacity is the live constraint — issue #101 records 34 of 63 tests never
running in CI, and #113 records that a session cannot verify a check it
wrote actually ran. This adds three tests to a suite whose CI coverage is
already a known gap.

## Financial

Assumption: the shell integration is a day's work —
`docs/planning/0129-encrypted-credential-store/prior-art.md §Build vs adopt`
puts it at roughly a hundred lines around `age`, and the insertion point is
four lines. The companion script (add/list/rotate/migrate) is larger than
the integration it serves, since every command is a separate `age`
invocation with its own argument handling. Documentation is the third cost:
a backup/recovery procedure, a tiering policy, an ADR for key management, a
design document, and a BUILDING.md row.

Opportunity cost is the honest counterweight. The benefit over today is
real but bounded — it removes plaintext from the operator's shell and makes
the store per-project. It does not reduce what the agent can read, which
`docs/planning/0129-encrypted-credential-store/scope.md §Non-goals` accepts
explicitly.

## Risk inventory

- Identity lost or passphrase forgotten → the whole store is unrecoverable,
  not merely leaked. *Mitigation:* backup/recovery gates the design
  document, not a follow-up.
- A missing `age` binary silently skips injection, indistinguishable from
  "no credentials for this project". *Mitigation:* absent binary aborts;
  only an absent credential file is silent.
- Moving or renaming a project directory orphans its credential file.
  *Mitigation:* documented fail-open behaviour plus a `migrate` command.
- The store becomes a dumping ground for credentials too broad to hand an
  agent. *Mitigation:* the tiering policy is written before the first
  credential is added.
- Decrypted values stay readable inside the container, exactly as
  `GH_TOKEN` is today. *Mitigation:* none — accepted in
  `docs/planning/0129-encrypted-credential-store/scope.md §Non-goals`;
  saying so plainly is the control.
- The three new tests join the 34 that never run in CI. *Mitigation:* out
  of scope here; #101 tracks it.
- A passphrase prompt on every credentialed launch discourages use.
  *Mitigation:* none needed if tiering keeps the store small.

## Confidence by dimension

- **Technical** — high, and checkable: every claim names a file and line in
  this repo, and the test harness already exists.
- **Operational** — moderate. The code judgment is solid; the claim that a
  backup procedure will be rehearsed rather than written and forgotten
  rests on intent alone.
- **Financial** — lowest. The day-and-a-bit estimate has no comparable in
  this repo's history, and documentation cost is the part most often
  underestimated.
- **Prior art** is present, but its own Confidence section names two
  sources it could not reach.
