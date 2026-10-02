# ADR 010 — What makes a citation valid

## Status

Accepted

## Context

[ADR 002](002-planning-artifact-contract.md) decision 6 requires a citation of
the form `path §section` and distinguishes it from a gesture: `See
docs/planning/scope.md §2` is a citation, "See the planning documents" is not.
It settles that a citation must be specific. It does not settle how the path is
spelled, and its worked example names a file that cannot exist any more —
[ADR 008](008-per-bundle-planning-directories.md) moved every artifact into
`docs/planning/<NNNN>-<slug>/`, which is why D-11 in
`tests/test_docs_integrity.bats` carries `_D11_FLAT_PLANNING_FILES` to exempt
ADR 002 from resolving its own example.

The two committed bundles answered the open half by hand, and not the same way
twice. Across their eight artifacts there are 56 intra-bundle citations: 18
write the full repository-relative path, 38 name a sibling bare
(`feasibility.md §Technical`). Both bundles use both forms, and both switch
form mid-document —
`docs/planning/0102-instruction-layer-silent-failures/charter.md` writes full
paths at lines 18 and 25 and bare siblings in its other eighteen citations;
`docs/planning/0129-encrypted-credential-store/charter.md` alternates as late
as lines 55 and 57. `global-claude/templates/planning/prior-art.md` prescribes
`<bundle>/scope.md §Problem statement`, so the bare form is the majority and
the undocumented one.

Neither form is broken. The bare form is a path relative to the citing
document, and the sibling it names is in the same directory. What is missing is
a rule saying so, and the absence has a cost in two places:

- **#96** cannot write the charter evidence check without one. A strict reading
  of the template fails 38 citations in three committed, approved artifacts, and
  the wrong resolution is editing an approved artifact to satisfy a test
  written after it.
- **#111** reports four coverage classes D-9 and D-11 cannot see, and a fifth
  found while re-landing #81: a citation whose path resolves but whose section
  has moved out of the named document. Four §9 rows in
  `docs/designs/0011-claude-sandbox-testing-module-sdd.md` are in that state
  after the changelog splits in #132 and #139. No check anywhere reads the
  `§Section` half of a citation, and D-11 cannot see a bare sibling at all,
  because it matches only tokens beginning `docs/`.

Both gaps are the same missing definition: what a citation has to satisfy, as
opposed to what it has to look like.

## Decision

**1. A citation is valid when it resolves, not when it matches a spelling.**
For `path §Section`, `path` is resolved against the citing document's own
directory first, then against the repository root; the first that exists wins.
`§Section` must match a heading in the resolved document. A citation that
satisfies both is correct in either form, and neither form is preferred.

**2. The section half is load-bearing.** A path that resolves while its cited
section lives elsewhere is a failed citation, not a stylistic one. That is the
class #111 found, and it is the half the existing checks drop.

**3. Decision 1 governs documents inside this repository only.** Under
`global-claude/`, [ADR 005](005-citing-across-the-repo-boundary.md) decision 1
continues to govern, unchanged: there the question is direction across the
repository boundary, which resolution in this tree cannot answer.

**4. ADR 002 decision 6 is qualified, not reversed.** Its requirement that a
citation be specific stands. Its worked example is a flat-layout path, and is
read as illustrating the form rather than prescribing the path.

## Consequences

Every citation in both committed bundles stays valid, so nothing approved is
edited to satisfy a rule written after it. #96's P-10 check becomes resolution
plus anchor rather than a spelling match, which is also the widening D-11 needs
for #111's fifth class — one helper, two call sites.

A rule about resolution is checkable; a rule about spelling is the kind that
holds until it is inconvenient, which is the reasoning behind ADR 002
decision 7. Against that:

**Two spellings stay in the tree.** A reader of `feasibility.md §Technical`
must know which bundle they are in. Inside a bundle that is free; quoted
elsewhere it is not, and nothing stops the bare form being copied out of its
directory into a document where it resolves to nothing — caught, but only once
a check runs.

**Relative-first can shadow.** If a document's directory and the repository
root both hold the named path, the relative one wins and the root one becomes
unreachable from that document. Deterministic, but surprising; no instance
exists today.

**Anchor checking adds a maintenance surface.** Renaming a heading now breaks
every document citing it, which is the point, but it makes a heading rename a
multi-file change rather than a local one.

## Alternatives considered

**Chose:** validity by resolution.
**Rejected:** mandate the full repository-relative form everywhere, as the
template prescribes.
**Why the rejected option is attractive:** one spelling, no resolution order to
define, no shadowing, and a citation stays correct when it is quoted out of its
directory.
**What breaks if you try it anyway:** 38 citations in three committed, approved
artifacts fail on the check's first run, and the only fixes are editing
approved artifacts or allowlisting them — an allowlist with 38 entries is the
rule being switched off.

**Chose:** validity by resolution.
**Rejected:** mandate the bare sibling form within a bundle and the full form
across one.
**Why the rejected option is attractive:** it follows the majority usage, is
shorter to write, and the shadowing case cannot arise.
**What breaks if you try it anyway:** it fails the other 18 citations instead,
including every one in
`docs/planning/0129-encrypted-credential-store/feasibility.md`, and it has to
define "across a bundle" before it can be checked.

**Chose:** qualify ADR 002 decision 6 in a new ADR.
**Rejected:** fold the rule into #96's check and let the test be the record.
**Why the rejected option is attractive:** the rule and its enforcement land
together, in one place, with no second document to keep in sync.
**What breaks if you try it anyway:** the decision becomes discoverable only by
reading a bats helper, and the next person to meet the two spellings
re-litigates it. ADR 005 decision 3 is the precedent for the other order — the
ADR carries the rule, the check carries the failure message.

## References

- [ADR 002](002-planning-artifact-contract.md) — decision 6, qualified here;
  decision 7, enforcement by test rather than by reviewer
- [ADR 005](005-citing-across-the-repo-boundary.md) — decision 1, which governs
  under `global-claude/`
- [ADR 008](008-per-bundle-planning-directories.md) — the move that stranded
  decision 6's example
- Issue #111 — the coverage classes, including the section-moved class
- Issue #96 — the charter evidence check this unblocks
- Issue #144 — the chain
