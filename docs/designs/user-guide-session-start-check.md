# User Guide Session-Start Check

## Status
Draft

## Context

Issue #47 proposed two session-start prompts: offer to create a user guide
if none exists, and the same for `config.local.sh`. They separate on
inspection, and only one is worth building.

**`config.local.sh` — declined.** `config.local.sh.example` is already
committed and `BUILDING.md` documents it, so discovery is covered. The
four-layer design in `docs/designs/sandbox-config-file.md` makes the file
optional by construction — the hardcoded defaults work without it. A prompt
on every session start for an optional file is noise, and noise gets tuned
out, alongside `base/entrypoint.sh`'s existing genuine advisory warnings
(broken interpreter reference, stale toolchain path). This document is the
record of that decision; no code or separate design doc follows from it.

**User guide — the real subject of this document.** `claude-sandbox` already
has `docs/user_guide.md`, so a check against *this* repository would never
fire. The useful version inspects whatever project is mounted at
`/workspace` — unknown conventions, unknown existing docs, unknown whether a
guide is warranted at all. "Does this project warrant a guide, and what
should it contain" is a judgment call. Every existing session-start check
(`base/entrypoint.sh`'s interpreter/toolchain/addon warnings,
`global-claude/hooks/commit-msg`) is a deterministic pattern or existence
check; none of them judge. A skill is needed for the judgment half.

This is distinct from the seeding path that already exists: `design` skill
Step 1 already offers a user guide, but only during **explicit docs-as-code
setup** — a narrow trigger the user consciously invokes
(`eb9dfdf`, #46). #47 is the wider, ambient form: inspecting whatever is
mounted, unprompted, at the start of a session that may have nothing to do
with docs-as-code setup at all.

## Decision

Hybrid: a deterministic `SessionStart` hook surfaces a candidate signal; a
skill applies the judgment the hook cannot.

**1. Hook** — `global-claude/hooks/session-start-scan.sh`, wired through a
new `global-claude/settings.json` under `hooks.SessionStart`, matched on
`session_start_reason == "startup"` only. Claude Code's `SessionStart` hook
distinguishes `startup` from `resume`/`clear`/`compact`/`fork`; matching
only `startup` means a long-running session is asked once, not re-prompted
on every resume or compaction.

`global-claude`'s existing copy-on-start mechanism
(`base/entrypoint.sh`: `GLOBAL_SRC` → `~/.claude`) delivers both the script
and this new `settings.json` the same way it already delivers
`global-claude/hooks/commit-msg` to `~/.claude/hooks/commit-msg`.
`~/.claude/settings.json` is the **user-level** settings scope, so Claude
Code applies it to whichever project is mounted — not only `claude-sandbox`
itself, which is the point.

The script does one thing: check whether a user-guide-shaped file exists
under the mounted project (exact candidate path list — `docs/user_guide.md`,
`docs/USER_GUIDE.md`, `USER_GUIDE.md`, `GUIDE.md`, or similar — to be fixed
at implementation) and report the finding as plain stdout, which Claude Code
reads as session context. It is read-only against the mounted project and
executes nothing found there. It does not decide whether a guide is
*warranted* — only whether one is *present*.

**2. Skill** — new `global-claude/skills/user-guide-check/SKILL.md`,
triggered by the hook's finding (its description names the finding as a
trigger condition, the same proactive-trigger pattern other skills already
use). On trigger it does the judgment: inspect the mounted project's
structure and existing docs and decide whether it warrants a guide at all
(a scratch repo or a repo mid-scaffold does not; an undocumented library or
CLI does). If yes, offer once, in the shape the issue itself specifies and
`base/entrypoint.sh`'s advisories already model: state the finding, name the
fix, do not block, do not prompt again this session. Take no for an answer.

On yes, the skill seeds `global-claude/templates/user-guide.md` directly —
read it, resolve its placeholders and authoring comments, save it, propose a
commit — the same mechanics `design` Step 1 already performs for its own
trigger, not reimplemented differently.

## Consequences

- First Claude-Code-native `SessionStart` hook in this repository, distinct
  from the existing git-native `commit-msg` hook that already lives beside
  it in `global-claude/hooks/`. Worth naming plainly in that directory or
  its README (if one exists) so a reader does not conflate the two kinds of
  "hook."
- `global-claude/settings.json` is new — the global layer has not shipped a
  settings.json before. Confirm at implementation that D-6/D-7's line
  ceilings and any other check scoped to the global layer's file set do not
  silently assume "global layer = markdown files."
- `seeded-by: design` on `global-claude/templates/user-guide.md` becomes
  incomplete once `user-guide-check` can also seed it. P-7
  (`_p7_missing_owner_skills`, `tests/test_planning_artifacts.bats:319-334`)
  reads `seeded-by` as a single scalar naming exactly one skill — it cannot
  name two. Not resolved in this document; the recommended follow-up is
  widening `seeded-by` to a space-separated list and updating P-7's parser,
  as its own issue, before this skill's first seed action ships. Left
  undone, this reproduces on day one the exact staleness gap the 2026-09-18
  handoff already named (P-7 checks the named skill is committed, not that
  it still seeds anything) — same shape as #78 and #113.
- New unprompted action at the start of every session on every mounted
  project, not only `claude-sandbox`. Correct per the issue's intent, but is
  new surface: a wrong judgment call (offering when it shouldn't, or not
  offering when it should) is now something any project mounted into this
  sandbox can hit.
- Not a Case E trigger: the hook adds a `hooks` key to a new settings.json,
  not the `permissions` block, and touches none of `base/Dockerfile`,
  `base/entrypoint.sh`, or `squid/squid.conf`. Checked explicitly because a
  script that runs automatically and unprompted against mounted-project
  content reads as security-adjacent; the mitigation is architectural
  (read-only existence check, never executes or evaluates anything found
  under `/workspace`), not a Case E artifact.

## Alternatives considered

**CLAUDE.md instruction only, no hook.** A global CLAUDE.md section
instructing the assistant to self-check near session start, mirroring the
existing "Design Workflow" section — no `settings.json` or hook changes.
**Chose the hook instead. Rejected option's appeal:** simplest possible
change, no new schema, no new hook category to document. **Why it breaks:**
it relies on the model reliably reading and acting on a standing instruction
every session, with no deterministic trigger. The entrypoint precedent this
issue explicitly asks to copy — state the finding, name the fix — exists
*because* instruction-following alone was judged insufficient for the
interpreter and toolchain checks it models; both could equally have been
"just tell the model to check," and were not. A hook guarantees the check
runs; an instruction only asks.

**Pure hook, no skill — heuristic judgment folded into the shell script.**
E.g. "more than N files and no `docs/` directory." **Rejected option's
appeal:** one artifact instead of two, no hook/skill handoff to design.
**Why it breaks:** the issue's own finding is that "does this project
warrant a guide" is a judgment, not a pattern match. A heuristic dressed as
determinism produces confident wrong answers — false positive on a
deliberate scratch repo, false negative on an undocumented library with few
files — with no way to reconsider, which is strictly worse than the noise
problem that sank the `config.local.sh` half.

**Widen `design` Step 1's existing offer instead of adding a new skill.**
**Rejected option's appeal:** reuses an already-shipped, already-tested
seeding path with zero new files. **Why it breaks:** `design`'s offer is
nested inside the explicit docs-as-code setup path, consciously invoked by
the user. Retrofitting it to also fire ambiently at session start conflates
two different trigger conditions — explicit setup versus ambient inspection
— inside one skill. The issue names this exact seam directly ("#47 should
say plainly how it relates to Step 1 rather than duplicating it"); a
separate skill keeps the relation an explicit citation instead of an
entangled trigger.

## Implementation plan

1. `feat(hooks): add session-start-scan.sh, detect missing user guide (#47)`
   — the hook script alone, unit-testable without `settings.json` wiring.
2. `feat(config): wire session-start-scan into global-claude/settings.json (#47)`
   — the `hooks.SessionStart` entry, matcher `startup`.
3. `feat(skills): add user-guide-check skill (#47)` — the judgment and the
   offer-and-seed logic.
4. `docs: resolve the user-guide.md seeded-by gap between design and user-guide-check (#47)`
   — either the P-7/`seeded-by` widening if scoped in, or an explicit
   "Known gaps" note mirroring the handoff note's #78/#113 pattern —
   whichever is decided before this step ships.
5. `docs: record config.local.sh session-start prompt declined (closes #47)`
   — closing commit; references this document's Consequences section as
   the record.
