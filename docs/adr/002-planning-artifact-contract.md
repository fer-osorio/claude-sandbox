# ADR 002 — Planning-phase artifact contract

## Status

Accepted

## Context

[ADR 001](001-agentic-sdlc-scope.md) commits to L1: Planning runs headless,
triggered by an event rather than by a person typing. A multi-step skill
workflow needs step N's output to become step N+1's input, and there are
only two ways to arrange that — implicitly, through conversation history, or
explicitly, through written files.

The implicit route works in an interactive session and fails silently
outside one. Under `claude -p` there is no conversation for a later step to
read; in a long session, early context is dropped and the failure surfaces
as a quality problem rather than as the plumbing problem it is.

A second concern points the same way. Content that lives in more than one
place must be kept in sync, costs tokens on every read, and forces a reader
to triangulate between sources. That is one root cause with two symptoms:
context bloat for the agent, and comprehension overhead for a developer
trying to understand just enough at 2am to make a fix. Both are solved by
the same rule — one authoritative home per piece of information, everything
else references it.

Deciding this before the first skill is written is not tidiness. Every
sub-skill's output section and every sub-skill's input instructions have to
agree on paths and formats; defining that contract after two skills exist
means retrofitting a shared interface.

## Decision

**1. Handoff is file-based, under `docs/planning/`.** Each sub-skill reads
its inputs from paths and writes its output to a path. The orchestrator
coordinates by path, never by conversation history.

**2. Exactly one skill owns each path.** Any skill may read any path; a
skill may write only the paths it owns. Initial allocation:

| Path | Owner | Contains |
|---|---|---|
| `docs/planning/README.md` | every sub-skill updates its own row | Index: artifact, status, one-sentence description |
| `docs/planning/scope.md` | `project-planning` (opening step) | Problem statement, constraints, explicit non-goals |
| `docs/planning/prior-art.md` | `swe-prior-art-research` | Prior art, build-vs-adopt recommendation |
| `docs/planning/feasibility.md` | `project-feasibility` | Technical / operational / financial feasibility, risk inventory |
| `docs/planning/charter.md` | `project-planning` (closing step) | Charter and go/no-go decision material |

**3. Every artifact carries frontmatter** with `status` (`Draft`,
`Approved`, or `Superseded by <path>`), `date`, and `phase`. A reader must
be able to tell a live artifact from a stale one without reading its body.

**4. Every artifact is readable at two levels** — a TL;DR of at most three
sentences at the top, full content below. A human scans five TL;DRs in under
a minute; an agent reads the TL;DR to decide whether to retrieve the rest.

**5. Templates carry hard section ceilings**, as template files rather than
as advice in a SKILL.md. What does not fit in the template does not belong
in that artifact; it belongs in a document with its own home.

**6. No re-derivation.** If something was established in a prior step, the
current step cites `path §section`, reads it, and builds on it — it never
restates it. `See docs/planning/scope.md §2` is a citation. "See the
planning documents" is not.

**7. These rules are enforced by a test, not by a reviewer.**
`tests/test_planning_artifacts.bats`, tagged `hostonly`, written when the
first `docs/planning/` artifact lands. It asserts: every artifact has a row
in the index; every artifact has a valid `status`; no artifact exceeds its
template's ceilings; no skill declares an output path another skill owns.
Rules 1–6 are prose, and prose is rung 2 of the enforcement ladder — a rule
nothing can fail is a rule that stops holding the first time it is
inconvenient. Naming the test here is what stops that from being the default
outcome.

## Consequences

The handoff survives headless operation, which is what L1 requires. Every
step's output is diffable, auditable, and resumable: if prior-art research
finds something disqualifying, the run stops and the partial output is still
readable without re-running anything. The index gives a 2am reader a single
entry point instead of five files to triangulate.

Against that: this is more files than a conversation-history design, and the
ownership table in decision 2 is a maintenance surface that goes stale
quietly when a skill is added or renamed — which is exactly why decision 7
has a machine check it rather than trusting review. The ceilings in decision
5 will sometimes be wrong and will need revisiting; a ceiling that is
routinely worked around is worse than none, because it teaches everyone the
contract is advisory.

This assumes `docs/planning/` is committed. Artifacts for abandoned projects
therefore stay in the tree, distinguished only by their `status` field. That
is deliberate: a recorded no-go, with the reasoning that produced it, is the
most reusable output the Planning phase has.

## Alternatives considered

**Chose:** explicit file-based handoff.
**Rejected:** implicit handoff via conversation history.
**Why the rejected option is attractive:** zero setup, no path contract to
design or get wrong, and the model naturally sees everything a prior step
produced without being told where to look.
**What breaks if you try it anyway:** under `claude -p` there is no
conversation to read from, so L1 cannot work at all; in long interactive
sessions early context is silently dropped, and the resulting failure looks
like the model reasoning poorly rather than like a missing input.

**Chose:** hard ceilings in template files.
**Rejected:** "keep output concise" instructions in each SKILL.md.
**Why the rejected option is attractive:** one line per skill, no template
files to write or maintain, and it reads as the obvious lightweight option.
**What breaks if you try it anyway:** a conciseness instruction constrains
one skill's output and does nothing to stop a later skill re-summarizing
material an earlier one already wrote. Duplication has to be made
structurally difficult, not discouraged.

**Chose:** an index file every sub-skill updates.
**Rejected:** rely on the directory listing and a naming convention.
**Why the rejected option is attractive:** nothing to keep in sync, and no
risk of the index itself going stale.
**What breaks if you try it anyway:** a filename tells you what an artifact
is called, not what it contains or whether it is current. The reader who
needed one file still opens five, which is the problem the index exists to
solve.

## References

- [ADR 001](001-agentic-sdlc-scope.md) — commits to L1, which is what forces an explicit handoff
- [`docs-as-code-workflow.md`](../designs/docs-as-code-workflow.md) — document types and locations
- [`engineering-principles-by-lifecycle-phase.md`](../engineering-principles-by-lifecycle-phase.md) — the enforcement ladder, and why prose is rung 2
