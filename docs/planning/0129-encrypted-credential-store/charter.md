---
status: Approved
date: 2026-09-20
phase: planning
owner: project-planning
---

# Project charter

## TL;DR

Proposed: a host-side, age-encrypted, per-project credential store that
`start.sh` decrypts at launch and injects by name. The evidence points
toward proceeding — the primitives are settled and the insertion point is
four lines — with the key-lifecycle procedure attached as a condition.

## Recommendation

Proceed, with one named condition and one caveat.

The condition: the backup and recovery procedure for the identity ships
with the design document, not after it.
`docs/planning/0129-encrypted-credential-store/feasibility.md §Risk inventory`
rates a lost identity as unrecoverable rather than merely leaked, and it is
the one failure here with no mitigation available afterwards.

The caveat: adopt `age` and build only the glue, per
`docs/planning/0129-encrypted-credential-store/prior-art.md §Build vs adopt`.

What would overturn this: if the tiering policy concludes that nothing
beyond a repo-scoped token belongs in the store, then the store holds one
credential and the existing passthrough already does that.

## Evidence

- `start.sh:235` already injects name-only, and `PROJECT_DIR` resolves at
  `:146` before validation, so the mechanism generalizes without
  special-casing
  (`docs/planning/0129-encrypted-credential-store/feasibility.md §Technical`).
- Fail-closed precedent and a reusable test harness are both already in
  this repo (same section).
- `age` and SOPS are mature, and SOPS+age+direnv is near-identical prior
  art
  (`docs/planning/0129-encrypted-credential-store/prior-art.md §Findings`).
- Against: OWASP recommends file mounts over environment variables (same
  section). Inverted here because the adversary is inside the container —
  defensible, but it must be argued in writing or a reviewer will read it
  as an oversight.
- Against: this closes nothing the agent can read
  (`docs/planning/0129-encrypted-credential-store/scope.md §Non-goals`).
- Against: three of five AI-agent projects cited in the earlier informal
  pass fail an adoption check (`prior-art.md §Findings`); two maintained
  ones remain.
- `age` becomes a new host prerequisite, and a missing binary must abort
  rather than skip (`feasibility.md §Technical`).
- 34 of 63 tests never run in CI
  (`docs/planning/0129-encrypted-credential-store/feasibility.md §Operational`).

## Open questions

Blocking: none.

Tolerable, but decide early: whether the tiering policy leaves enough in
the store to justify the machinery.

Tolerable: the ClawGate and Knostic sources could not be reached from this
sandbox (`prior-art.md §Confidence`); neither bears on the scoped design,
only on the deferred follow-up. Timeline and budget are undecided
(`scope.md §Constraints`), and the effort estimate has no comparable in
this repo's history (`feasibility.md §Confidence by dimension`).

Unresolved elsewhere: #130 asks whether `settings.json` deny rules block
raw Bash writes. It does not block this work — it strengthens the case for
host-side decryption either way.

## Decision

Go

Increase the security while decreasing operator error probability.

2026-09-21

