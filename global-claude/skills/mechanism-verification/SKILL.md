---
name: mechanism-verification
description: >
  Invoke before asserting that a check, gate, hook, CI step, or documented
  control actually enforces anything, and before concluding that code or
  config is unused. Presence is not function: a gate never observed failing
  is not known to be a gate, and a definition with no readers is not
  load-bearing. Trigger on adding or changing anything whose job is to
  prevent a class of change - a hook, a CI gate, a lint or schema rule, a
  regression test, a size or coverage threshold; on any claim that something
  is enforced, covered, or checked; and before deleting anything believed
  unused. Resolve by what the thing is for, not by whether it is a test: an
  ordinary unit test describing behaviour does not need this, a test whose
  purpose is to stop a regression recurring does. It applies precisely when
  the mechanism looks obviously correct, because that is where nobody
  checks.
---

# Mechanism Verification

Two questions, one method. *Does this gate actually stop anything?* and *is
this definition actually used?* Both are answered by evidence, never by
reading the thing and finding it plausible.

The cost of skipping this is not a broken gate — it is a gate everyone
believes in. See `docs/engineering-principles-by-lifecycle-phase.md`
§Part I.1 for the enforcement ladder and §Part I.3 for load-bearing vs
vestigial.

## When to invoke

- Adding or reviewing a test, hook, CI job, lint rule, or schema check
- Writing or reading a claim that something "is enforced" or "is covered"
- Before deleting code, config, or documentation believed unused
- When a control is named in a design document but you cannot say what
  would fail if it were removed

## Step 1 — State the failure it should catch

Write the concrete input that the mechanism is supposed to reject. If you
cannot name one, stop: there is nothing to verify, and the mechanism is
decoration regardless of how it reads.

## Step 2 — Produce that failure and watch it fail

Break it on purpose. Feed the bad input, breach the threshold, delete the
required field, revert the fix the regression test covers.

A mechanism that has never been observed rejecting anything is unverified,
however carefully it was written. Restore the tree afterwards and confirm
it passes again — one-directional evidence is half the check.

## Step 3 — Verify the probe before believing the result

A probe that silently does nothing reports the same "no failure" as a
mechanism working correctly. Before concluding a gate is fine, confirm the
probe did what you intended:

- Did the file actually change? Check the line count, not the command's
  exit status.
- Did the command run at all? A typo'd flag, a shell metacharacter, a path
  that does not exist — all of these produce quiet no-ops.
- Does the assertion string match the source exactly? An expectation with a
  typo passes nothing and fails nothing.

This step exists because it is the failure that looks most like success.

## Step 4 — For "is this still used?", grep for readers

Never grep for the definition — it will always match itself. Search for
whoever consumes it: callers, importers, includes, config keys read at
runtime, links pointing at the document.

Stronger still: remove it locally and see what breaks. A thing nothing
reads is vestigial no matter how load-bearing it looks.

## Notes

- Pairs with `commit-hook-setup`, which is this method applied to one
  artifact — it probes an installed hook with known-bad and known-good
  messages rather than reading it for the expected words.
- A negative result is worth recording. "Observed failing at N+1" in a
  commit body or a test comment is what stops the next person re-verifying,
  and what makes a later regression legible.
- This does not apply to prose rules. A convention nobody can fail is rung
  2 by construction; the honest move is to say so, not to invent a probe
  for it. See `docs/adr/003-where-a-behavioural-rule-goes.md`.

## Changelog

- **0.2 (draft)** — Tested the trigger against five inline cases (2 trigger,
  1 boundary, 2 edge). The boundary case — "write a unit test for the
  parser's error handling" — fired, and should not have: "adding or
  reviewing a test" catches every ordinary unit test, and a skill that fires
  on everything gets ignored, which is the same outcome as one that never
  fires. Replaced the keyword with an intent tie-breaker: does the thing
  exist to *prevent* a class of change, or to *describe* behaviour. Only the
  former needs this.
- **0.1 (draft)** — Initial version. Trigger drafted from six recorded
  instances in this repository: unfilterable bats tags, a STRIDE control
  named without a mechanism, a setup skill certifying a hook by reading it,
  a padding probe that silently appended nothing, a skill description that
  never loaded, and a pull-request body whose bare issue numbers closed
  nothing. Step 3 comes from the fourth of those.
