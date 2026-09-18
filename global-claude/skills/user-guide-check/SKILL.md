---
name: user-guide-check
description: >
  Judge whether the project mounted at /workspace warrants a user guide,
  after session-start-scan.sh's SessionStart hook reports none was found.
  The hook only checks presence; this skill does the judgment it cannot.
  Invoke when a "[session-start-scan] No user guide found" line appears in
  session context, or when explicitly asked whether this project needs a
  user guide.
---

# User Guide Check

## When to invoke

- A `[session-start-scan] No user guide found` line appears in session
  context, from the SessionStart hook.
- Explicitly asked whether the current project needs a user guide.

## Step 1 — Judge whether a guide is warranted

A missing guide is not itself a finding — most projects legitimately go
without one. Inspect the mounted project before proposing anything:

- Does it have enough surface area to need a task-oriented guide — a
  library, CLI, or service with more than a couple of entry points — or is
  it a scratch repo, a fork awaiting real content, or a project still being
  scaffolded?
- Does something already cover this ground under a name the hook did not
  check — a `README.md` with genuine day-to-day usage instructions, a
  `docs/` tree that already reads as a guide under a different title?
- Is the project mid-setup in a way that makes documenting it now premature
  — no working build yet, no stable structure?

If the answer leans "not yet" or "already covered," stop here. Do not
offer, and do not leave a note behind — a project without a guide because
it does not need one yet is not a defect.

## Step 2 — Offer, once

If a guide is genuinely warranted, offer in the shape this project's own
session-start advisories already use: state the finding, name the fix, do
not block.

> "No user guide found for this project. Given [one-line reason], a
> task-oriented user guide may be worth adding — want me to seed one from
> the template?"

Offer at most once per session. Take no for an answer: do not ask again
this session. Re-offering on a *future* session, if the finding still
holds, is not a violation of this rule — only re-asking within the same
session is.

## Step 3 — Seed, on yes

1. Read `~/.claude/templates/user-guide.md`.
2. Resolve its placeholders and authoring comments per its own
   instructions — the same mechanics the `design` skill's explicit
   docs-as-code setup path already performs for its own trigger.
3. Save it to the location the project's own docs-as-code workflow
   document names for a user guide, if it has one; otherwise place it as
   `user-guide.md` under a top-level `docs` directory, matching the
   convention this template itself follows.
4. Propose a commit seeding it, following this session's standing Git
   Workflow conventions (branch first, no commit on `main`).

## Relation to the `design` skill

`design` Step 1 already offers a user guide, during **explicit docs-as-code
setup** — a narrow trigger the operator consciously invokes. This skill is
the wider, ambient form: it fires from a passive session-start scan of
whatever is already mounted, on any session, not only one initializing the
workflow. The two do not compete — `design`'s offer covers a project
adopting the workflow for the first time, and this skill covers every
session after that where the question was never asked.
