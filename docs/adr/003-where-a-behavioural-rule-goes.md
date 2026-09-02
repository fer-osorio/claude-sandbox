# ADR 003 — Where a behavioural rule goes

## Status

Accepted

## Context

Issue #42 asks whether engineering principles belong in the injected
`global-claude/CLAUDE.md` or in a skill invoked when relevant, and explicitly
declines to answer: "that is an argument worth making explicitly rather than
assuming, because the same reasoning would justify putting anything there."
The question gates #42 and #43 — nothing can be written into `CLAUDE.md` until
it is settled — and it recurs for every rule proposed afterwards.

Two facts, both established after #42 was written, change the framing.

**The informal channel does not exist.** The session container runs `--rm`
(`start.sh:301`) and mounts nothing under `~/.claude`; G-4 and G-5
(`tests/test_global_layer.bats:71-99`) assert that isolation deliberately.
Anything an agent records to memory is destroyed at session exit. `CLAUDE.md`
and skills are not merely the better channels — they are the only ones that
survive a session boundary.

**Two of #42's five candidate principles are already carried.** An audit
against the tree at `80618e7`:

| Candidate (§ of `docs/engineering-principles-by-lifecycle-phase.md`) | Existing carrier |
|---|---|
| Name anti-goals; silence reads as "not yet" (§Design) | `docs/planning/templates/scope.md:36-40`, verbatim; also `templates/charter.md:20`, `docs/adr/001-agentic-sdlc-scope.md:29` |
| Record rejections, including why the rejected option was attractive (§Design) | `global-claude/skills/design/SKILL.md:246-256`; `docs/designs/docs-as-code-workflow.md:244-254` |
| Spend length only on what the diff cannot carry (§Part I.4) | none |
| Grep for readers, not definitions (§Part I.3) | none |
| A gate never observed failing is not known to be a gate (§Part I.1) | none |

Writing the first two into `CLAUDE.md` would duplicate text that already sits
closer to the moment of authorship than `CLAUDE.md` does — which is the defect
ADR 002 decision 6 names, appearing in the file that decision governs.

So the binary in #42 is incomplete. There is a third placement, and it is the
one already working.

## Decision

**1. Three placements, ranked by precision. Use the most specific that fits.**

| Rung | Placement | Loads | Use when |
|---|---|---|---|
| 1 | Artifact template or format spec | When the artifact is authored | An artifact format already exists that the rule constrains |
| 2 | Skill | Description always; body on invocation | The applicable moment has a nameable trigger, and the rule needs a procedure rather than a sentence |
| 3 | `CLAUDE.md` | Every session, always | The moment cannot be named as a discrete trigger |

**2. A rule earns rung 3 only by failing rungs 1 and 2.** Always-on placement
is not granted on the strength of the rule; it is what remains when the rule
cannot be attached to an artifact or a trigger. This is the admission criterion
#42 asked for, and it constrains additions whether or not a line ceiling
exists.

**3. Rung 2 is paid for in the description, not the body.** A skill's
`description` is in context every session; only the body is deferred. Both
rungs therefore cost roughly one always-on line — rung 2 buys a full procedure
for that line, rung 3 buys one sentence. Prefer rung 2 whenever the rule needs
more than a sentence, and write the trigger into the description sharply enough
to fire, because an unfired skill is the failure mode that makes rung 2 worse
than rung 3.

**4. No restatement.** If a principle already has a carrier, cite `path
§section` and stop. ADR 002 decision 6 applies to `CLAUDE.md` itself.

**5. Applied to #42's five candidates:**

| Principle | Placement | Work |
|---|---|---|
| Spend length only on what the diff cannot carry | Rung 3 | Already scheduled — this is #43's output-cost rule |
| Grep for readers, not definitions | Rung 2 | New skill; own issue |
| A gate never observed failing is not known to be a gate | Rung 2 | Same skill; own issue |
| Name anti-goals | Rung 1, carried | Cite `templates/scope.md`; write nothing |
| Record rejections and their appeal | Rung 1, carried | Cite `design/SKILL.md`; write nothing |

The two rung-2 principles plausibly share one skill — both say *check the
mechanism, do not trust its presence*, one for a gate and one for a definition.
Whether they do is a design question for that issue, not this one.

## Consequences

#42 shrinks to almost nothing in `CLAUDE.md`: one line, which #43 already
supplies. That matters for ordering: a size ceiling has to be set against content that
already exists, or the change that introduces the ceiling breaches it. The
ceiling can now be set against a file that is not about to absorb four more
rules.

`CLAUDE.md` gains a falsifiable admission test. "Does this fail rungs 1 and 2?"
is answerable by inspection — is there a template, is there a trigger — where
"is this important enough" is not. The recurrence #42 predicts is not
prevented, but arguing for an addition now requires showing no artifact and no
trigger exists, which is a claim that can be checked and refused.

Against that: **the ladder's weakest rung is the one it prefers.** A rung-1
rule fires only if the template is used; a rung-2 rule fires only if the
trigger is recognised. Both fail silently, and neither failure is observable —
which is the enforcement-ladder defect (§Part I.1) reproduced inside the
mechanism meant to place it. Decision 3 mitigates rung 2 by loading the trigger
always; rung 1 has no equivalent mitigation and relies on the template being
reached for at all.

There is direct evidence for that risk. On 2026-09-02 an analysis deliverable
was produced as a styled HTML page rather than Markdown, in a docs-as-code
repository, with no skill invoked and no moment at which a trigger would have
fired. That is the density principle failing with no carrier at any rung — the
observation that produced #43's format rule, and the reason that particular
principle is placed at rung 3 rather than deferred to a skill.

This decision assumes skill descriptions are loaded into context every session
while bodies are not. Decision 3's economics depend on it entirely. If that
changes, rung 2 collapses into rung 1's failure mode and the ladder needs
revisiting.

## Alternatives considered

**Chose:** the three-rung ladder.
**Rejected:** the binary `CLAUDE.md`-versus-skill as #42 posed it.
**Why the rejected option is attractive:** it is the question actually asked,
it needs no new vocabulary, and two options resolve faster than three.
**What breaks if you try it anyway:** two of the five candidates have no
correct home under it, so they get written into `CLAUDE.md` as duplicates of
`templates/scope.md` and `design/SKILL.md` — inflating the file #42 exists to
protect, and breaching ADR 002 decision 6 in the process.

**Chose:** admission by failing the lower rungs.
**Rejected:** an allowlist of topics permitted in `CLAUDE.md`.
**Why the rejected option is attractive:** a list is enumerable, greppable, and
would look like moving the rule off rung 2 of the enforcement ladder — the
direction #37 and #49 have both pushed.
**What breaks if you try it anyway:** the list has no principled bound, so
every proposed rule becomes an argument to extend it. The check would pass
while the file grows, which is worse than no check, because it certifies the
outcome it was built to prevent.

**Chose:** audit the five candidates for existing carriers before writing any.
**Rejected:** write all five into `CLAUDE.md`, prune later.
**Why the rejected option is attractive:** it is #42 as written, and judging
duplication is easier once the lines sit next to each other.
**What breaks if you try it anyway:** the ceiling gets set against the inflated
file, so the duplication becomes the permanent baseline, and the pruning pass
is never forced because nothing fails.

## References

- Issue #42 — distil the engineering principles into the injected `CLAUDE.md`
- Issue #43 — output-cost discipline, mechanism or rule
- ADR 002 §Decision 6 — no re-derivation; cite `path §section`
- `docs/engineering-principles-by-lifecycle-phase.md` §Part I.1, §Part I.3,
  §Part I.4, §Design
