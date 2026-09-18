# ADR 008 — Per-bundle planning directories

## Status

Supersedes ADR 002

Only the flat layout named in ADR 002's decisions 1 and 2 is superseded:
the location, not the rules. Single ownership per path, frontmatter,
two-level reading, template ceilings, and the index all stand.

## Context

[ADR 002](002-planning-artifact-contract.md) fixes one path per artifact
directly under `docs/planning/`. A repository therefore holds exactly one
Planning run. The first run, covering #102–#104, filled every slot. The
next Planning-shaped task, a prior-art pass for #105, had nowhere to go
except over that run's Approved artifact.

A run is a bundle of scope, prior art, feasibility, and charter, and those
are decided together. They need to stay readable together after the next
run starts.

## Decision

**1. One directory per run.** Each run lives in
`docs/planning/<NNNN>-<slug>/`. `NNNN` is the tracking issue number, or the
PR number when no issue exists, as the naming convention in
`docs/designs/0105-file-naming-convention.md` defines. Artifact names inside
are fixed exactly as ADR 002 lists them, including a per-bundle `README.md`
index.

**2. The top-level index names the current bundle.** `docs/planning/README.md`
lists every bundle and marks exactly one as **Current**:

- `project-planning` creates the bundle directory and sets Current.
- Every other Planning skill, and `design` Step 1b, resolves paths through
  Current. None of them infers the current bundle from the listing.

**3. No Current, no guess.** If `docs/planning/` exists but its index names
no Current bundle, which includes a project still on the flat layout, a
skill stops and says so. It does not pick one.

**4. `docs/planning/` existing is still the opt-in signal.** Nothing about
opting in changes.

## Consequences

- Runs accumulate instead of overwriting one another. Earlier runs stay
  readable, and their status is untouched.
- Every Planning path gains one indirection: resolve Current, then the
  artifact. The skills, the templates' `artifact:` fields, and the P-checks
  all change together.
- Projects that ran Planning on the flat layout hit decision 3 once and
  migrate by hand. The failure is loud, which is the intent.
- A second "current" pointer, beside each artifact's `status`, is state
  that can go stale. It stays in the one file every skill already reads,
  and each P-check verifies that it names an existing bundle.

## Alternatives considered

**Chose:** Current recorded in the index. **Rejected:** newest bundle by
prefix. **Why the rejected option is attractive:** it needs no extra state
and cannot go stale. **What breaks if you try it anyway:** reopening an
older bundle silently resolves to the wrong one. It is also the "rely on the
directory listing" option that ADR 002 already rejected.

**Chose:** Current recorded in the index. **Rejected:** ask the operator on
every run. **Why the rejected option is attractive:** it is never wrong.
**What breaks if you try it anyway:** Planning runs headless under L1
([ADR 001](001-agentic-sdlc-scope.md)), where no one is there to answer.

**Chose:** per-bundle directories. **Rejected:** a suffix on each artifact
(`scope-0107.md`). **Why the rejected option is attractive:** it keeps one
flat directory and changes less. **What breaks if you try it anyway:** every
artifact name stops being fixed, so each template's `artifact:` becomes a
pattern. A bundle is also no longer one directory someone can read, archive,
or delete as a unit.
