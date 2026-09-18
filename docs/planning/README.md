# Planning bundles

One directory per Planning run, named `<NNNN>-<slug>` after its tracking
issue. Each carries its own index of artifacts. Exactly one row is
**Current**: the bundle every Planning skill reads and writes. Skills
resolve it here and never infer it from the directory listing
([ADR 008](../adr/008-per-bundle-planning-directories.md)).

## Bundles

| Bundle | Current | Issue | Question |
|---|---|---|---|
| [`0102-instruction-layer-silent-failures`](0102-instruction-layer-silent-failures/README.md) | **Current** | #102, #103, #104 | Fix three silent-failure gaps in the instruction layer? |

Opening a bundle adds a row, marks it Current, and unmarks the previous
one. Nothing else changes a row.

## Two choices ADR 002 left open

**Templates live in the global layer, artifacts live here.** ADR 002
decision 5 requires templates to be files rather than advice inside a
SKILL.md, but does not say where they go. They are at
`global-claude/templates/planning/`, reaching a session as
`~/.claude/templates/planning/<artifact>.md`, because the skills that
follow them are injected into every project while this directory is
per-project. See
[`0069-planning-skill-output-routing.md`](../designs/0069-planning-skill-output-routing.md)
§Decision 1 for why, and §Consequences for what that costs.

Artifact paths are unchanged — decision 2 specifies them and only the
authoring inputs moved.

**Ceilings are counted in words, not sentences or lines.** ADR 002
decision 4 asks for a TL;DR of at most three sentences. Splitting prose
into sentences is unreliable — abbreviations and decimals both break it —
and a check that misfires gets switched off, so the check counts something
mechanical instead.

It counted physical lines until the first real run, which was written as
unwrapped paragraphs. Every section passed; the same text wrapped at this
repository's 76 columns breached thirteen of twenty ceilings. Lines measure
how an author wrapped the prose, not how much of it there is. The ceilings
were converted at nine words per line — the measured density of this
repository's wrapped prose — which reproduces the line-based verdict on
nineteen of the twenty sections.

Each template declares its own ceilings as `ceiling-<section>-words:` keys
in its frontmatter, so the numbers live next to the sections they govern
rather than in the test. Three sentences remains the intent; the word
ceiling is the mechanical proxy for it.
