---
template-tier: scaffold
seeded-by: design user-guide-check
unowned-because: the project chooses where its guide lives and what it
  covers, and edits it directly from then on, so there is no fixed path
  and no single writer.
---

<!-- Template for a project's user guide. Copy it to the location chosen
     in the document-type table, then delete this comment and every other
     comment block below. A user guide is task-oriented: what someone does
     with this project day to day. Build and test commands belong in
     BUILDING.md, internals in ARCHITECTURE.md; link to them rather than
     restating them, or the three drift apart.

     Sections marked optional are deleted outright when they do not apply.
     Do not keep a heading with "none" under it — an empty section reads as
     an oversight, and the table of contents stops meaning anything. -->

# User Guide

<!-- One or two sentences: what this project is, for a reader who will use
     it rather than modify it. Then the two pointers out. -->

<What this project does, in a sentence.> For build and test commands see
BUILDING.md; for internals see ARCHITECTURE.md.

## Everyday operations

<!-- The two or three things a user actually does most, with a runnable
     command for each. Not an exhaustive command reference — the commands
     someone needs on their first day and keeps needing. -->

```
<command someone runs most often>
```

<What it does, and what to expect back.>

## Configuration and modes

<!-- Optional. Delete if the project has one mode and no configuration.
     A table beats prose when the reader is choosing between options. -->

| <Mode or profile> | Use for | Notes |
|---|---|---|
| <name> | <when to pick it> | <what it adds or changes> |

## Credentials and access

<!-- Optional. Delete outright if the project needs no credentials.
     If it does, state what crosses which boundary and what does not —
     the common failure is a reader assuming a credential is available
     somewhere it was never passed. -->

<Which credentials are needed, where they are set, and what happens
without them.>

## Extending it

<!-- How someone adds to this project, and the boundary between a change
     that persists and one that disappears. Name the thing that is easy to
     get wrong. -->

<How to add to this project, and what not to do.>

## Troubleshooting

<!-- Symptom, cause, fix — in that order, phrased as the reader will
     encounter it. Write the symptom as the literal text they will see,
     so searching for it lands here. -->

- **<Literal error text or observed symptom>** — <what causes it, and the
  fix.>

## Where to go next

<!-- Pointers out, each with a reason to follow it. A bare list of links
     without reasons is a table of contents, which the repository already
     has. -->

- <Document or path> — <what question it answers.>
