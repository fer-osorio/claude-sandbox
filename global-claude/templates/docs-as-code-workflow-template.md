# Docs-as-Code Workflow
**Version:** 1.0.0
**Status:** Accepted
**Scope:** `<org>/<repo>`

---

## 1. Introduction

### Current state

<!-- Describe the documentation problem this project currently has.
     Common patterns:
     - Design documents are written but discarded after implementation.
     - Commit messages record what changed but not why.
     - Environment setup knowledge lives in people's heads, not in files.
     Replace this block with a one-paragraph honest description. -->

### Objective

Establish a lightweight workflow that keeps documentation and source code
in sync, version-controlled, and useful after the fact — without adding
tooling friction.

### Scope

This document covers:

- Which documents to create, and when.
- Where those documents live in the repository.
- How documents connect to commits, issues, and releases.
- How to select the right workflow for a given change.

It does not cover:

<!-- List explicit exclusions. Common ones: -->
- API reference generation.
- Public-facing documentation sites.
- Team-scale review processes.

<!-- Add or remove exclusions as appropriate for the project. -->

---

## 2. System Architecture

### 2.1 Top-level overview

The workflow has three layers. Each layer answers a different question.

```
┌─────────────────────────────────────────────────────┐
│  LAYER 3 — PERMANENT RECORD                         │
│  docs/adr/   docs/designs/   docs/plans/            │
│  "Why was it built this way?"                       │
├─────────────────────────────────────────────────────┤
│  LAYER 2 — IN-FLIGHT TRACKING                       │
│  Issues · Pull Requests                             │
│  "What is being changed and why?"                   │
├─────────────────────────────────────────────────────┤
│  LAYER 1 — CHANGE LOG                               │
│  Git commits (Angular convention)                   │
│  "What changed?"                                    │
└─────────────────────────────────────────────────────┘
```

Each layer is built on the one below it. A commit references an issue; an
issue references a document; a document is committed alongside the code.

### 2.2 Components

#### Tools

| Tool | Role |
|---|---|
| **Git** | Version control for both source code and documentation |
| **GitHub Issues** | Tracks motivation and design for in-flight changes |
| **GitHub CLI (`gh`)** | Terminal-native interface to Issues and Releases |
| **Markdown** | Plain-text format for all documents (rendered by GitHub) |

<!-- Add project-specific tools below if applicable. Examples:
| **vcpkg / Conan** | C/C++ dependency manifest |
| **Nix flakes** | Hermetic development environment |
| **Docker** | Runtime environment declaration |
-->

#### Document types

| Type | Location | Purpose | Lifespan |
|---|---|---|---|
| **Commit message** | Git history | Records what changed | Permanent |
| **GitHub Issue** | GitHub Issues tab | Records motivation while change is in flight | Closed on merge, permanent record |
| **Implementation plan** | `docs/plans/` | Ordered steps to execute a change | Permanent after execution |
| **Design document** | `docs/designs/` | Before/after structure, trade-offs, migration path | Permanent |
| **Architecture Decision Record (ADR)** | `docs/adr/` | Single architectural decision, context, and consequences | Permanent, never deleted |
| **`BUILDING.md`** | Repo root | How to build and run the project locally | Living document |
| **`ARCHITECTURE.md`** | Repo root | High-level system overview | Living document |

<!-- Add a row for project-specific document types if the project warrants
     them. Example for a security or performance-critical project:
| **Benchmark report** | `docs/benchmarks/` | Before/after measurements for perf changes | Permanent |
-->

#### Repository layout

```
repo-root/
  BUILDING.md
  ARCHITECTURE.md
  docs/
    adr/
      001-<decision-slug>.md
      002-<decision-slug>.md
    designs/
      <feature-slug>.md
    plans/
      <YYYY-MM>-<feature-slug>-v<N>.md
```

<!-- Add project-specific directories below if needed. Example:
    benchmarks/
      <YYYY-MM>-<feature-slug>.md
-->

### 2.3 How components relate

```
GitHub Issue (motivation)
    │
    ├── referenced by → Git commits ("feat: ... (#12)")
    │                       │
    │                       └── closes → Issue (on merge)
    │
    └── resolved by → docs/designs/ or docs/plans/
                          │
                          └── key decision extracted to → docs/adr/
```

An ADR is the terminal artifact — it outlives the issue and the plan and
remains the authoritative record of why the system is the way it is.

---

## 3. Workflow Description by Case

### Case A — Small, self-contained change

**Applies to:** `style`, `fix`, `test` (additions), `chore`, `revert`

No document required beyond the commit message. The commit message must be
sufficient to explain the change to a reader with no other context.

```
fix: <short description of what was fixed>

<What was the incorrect behavior? What caused it? What does the fix do?
One short paragraph is enough. No bullet points needed.>
```

**Artifacts produced:** commit message only.

---

### Case B — Motivated change with defined scope

**Applies to:** `feat` (contained), `refactor` (single module), `ci`, `build`

Open a GitHub Issue before writing any code. Reference it in every related
commit. Close it with the final commit.

```bash
# Open issue from terminal
gh issue create --title "<type>: <short description>"

# Commit referencing the issue
git commit -m "<type>: <what changed> (#<issue-number>)"

# Final commit closes the issue
git commit -m "docs: update BUILDING.md or ARCHITECTURE.md (closes #<issue-number>)"
```

**Artifacts produced:** GitHub Issue, commit messages.

---

### Case C — Structural change spanning multiple modules

**Applies to:** large `refactor`, multi-module `feat`, significant pipeline
redesign (`ci`, `build`)

Open a GitHub Issue. Write a design document in `docs/designs/` as the
first commit. The design captures current structure, target structure,
motivation, and migration path. Commit the code in small steps. Extract
any binding decision into an ADR as the final step.

```bash
gh issue create --title "<type>: <short description>"

# First commit: the design
cp draft.md docs/designs/<feature-slug>.md
git add docs/designs/<feature-slug>.md
git commit -m "docs: design for <feature> (#<issue-number>)"

# Code commits (one logical step per commit)
git commit -m "<type>: <step one> (#<issue-number>)"
git commit -m "<type>: <step two> (#<issue-number>)"

# Final commit: close issue, add ADR if warranted
git commit -m "docs: ADR 00N — <decision> (closes #<issue-number>)"
```

Design document minimum structure:

```markdown
## Current structure
<What exists today and why it is insufficient.>

## Target structure
<What the component will look like after the change.>

## Motivation
<The specific problem being solved.>

## Migration path
1. <Step one>
2. <Step two>
```

**Artifacts produced:** GitHub Issue, `docs/designs/<slug>.md`,
optionally `docs/adr/00N-<slug>.md`.

---

### Case D — Architectural decision

**Applies to:** new dependency management strategy, new language or runtime
introduced, fundamental change to build or deploy model, any decision that
will constrain the project for a long time

Open a GitHub Issue. Write an ADR directly — the ADR *is* the design
document for decisions of this weight. An implementation plan goes in
`docs/plans/` if the execution is non-trivial.

ADR format:

```markdown
# ADR 00N — <Short title of the decision>

## Status
<!-- One of: Proposed | Accepted | Deprecated | Supersedes ADR 00N -->
Accepted

## Context
<!-- What situation or problem forced this decision?
     What constraints existed? What was tried before? -->

## Decision
<!-- What was decided? State it plainly and directly. -->

## Consequences
<!-- What becomes easier, harder, or impossible as a result?
     Include both positive and negative consequences.
     Include any implicit assumptions the decision relies on. -->
```

ADRs are **never rewritten**. If a decision is reversed, a new ADR is
written with status `Supersedes ADR 00N`.

**Artifacts produced:** GitHub Issue, `docs/adr/00N-<slug>.md`,
optionally `docs/plans/<date>-<slug>-v<N>.md`.

---

### Case E — Project-specific extended case

<!-- This case is a placeholder for a workflow that is specific to the
     nature of the project. Examples:

     - Performance changes in a security-critical tool (require benchmark
       documents and constant-time analysis).
     - Schema migrations in a database-backed service (require a migration
       plan and rollback procedure).
     - Public API changes in a library (require a deprecation notice and
       changelog entry).

     Define the case by answering:
     - What type of change triggers it?
     - What additional artifacts are required?
     - What is the minimum content of those artifacts?

     If the project has no domain-specific extended case, remove this
     section entirely. -->

**Applies to:** <!-- define trigger -->

<!-- Describe the required artifacts and their minimum content. -->

**Artifacts produced:** <!-- list artifacts -->

---

## 4. Workflow Selection Criteria

Ask the following questions in order. Stop at the first match.

```
1. Does this change cross module boundaries, introduce a new abstraction,
   or constrain future design choices?
   YES → Case D (ADR) or Case C (design doc), depending on scope.

2. <Insert project-specific trigger for Case E, if defined.>
   YES → Case E.

3. Does this change have a motivation that a commit message cannot
   fully express?
   YES → Case B (Issue) or Case C (Issue + design doc).

4. Is the change self-contained, easily reversible, and self-explanatory?
   YES → Case A (commit message only).
```

As a secondary check — if the change goes wrong or needs to be revisited
in six months, will you wish you had written down your reasoning? If yes,
write a document.

---

## 5. Quick Reference

| Change type | Case | Minimum artifacts |
|---|---|---|
| Style, formatting | A | Commit message |
| Bug fix (isolated) | A | Commit message |
| Test addition | A | Commit message |
| Chore, revert | A | Commit message |
| Contained feature | B | Issue + commit messages |
| Single-module refactor | B | Issue + commit messages |
| CI/build change | B or C | Issue; + design doc if pipeline changes significantly |
| Multi-module refactor | C | Issue + design doc + optional ADR |
| Large feature | C | Issue + design doc + optional ADR |
| Architectural decision | D | Issue + ADR + optional plan |
| <!-- Case E trigger --> | E | <!-- Case E artifacts --> |

<!-- Remove the Case E row if Case E is not defined for this project. -->

---

## 6. Definitions

**ADR (Architecture Decision Record):** A short document capturing a single
architectural decision, its context, and its consequences. Never deleted;
superseded by a new ADR when reversed.

**Design document:** A document describing the current and target structure
of a component, the motivation for changing it, and the migration path.
Written before implementation begins.

**Docs as Code:** The practice of treating documentation with the same
discipline as source code — version-controlled, reviewed, and updated
alongside the code it describes.

**Implementation plan:** An ordered sequence of phases for executing a
change, each with a verification gate and rollback strategy.

**Infrastructure as Code (IaC):** The practice of declaring build
environments, pipelines, and runtime configuration as version-controlled
text files rather than manual procedures.

<!-- Add project-specific terms below as needed. -->
