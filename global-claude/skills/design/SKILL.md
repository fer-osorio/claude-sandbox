---
name: design
description: >
  Invoke at the beginning of any significant change — new feature, major
  refactor, architectural decision, or multi-file modification. Guides
  Claude through the docs-as-code workflow: read existing design context,
  produce a design document, and wait for approval before touching code.
---

# Design-First Workflow (Docs-as-Code)

Follow these steps in order. Do not write or modify implementation code
until the user explicitly approves the design document.

## Step 1 — Read existing context

Before proposing anything:
1. Look for a `docs/designs/` directory in the project root.
2. Read `docs/designs/docs-as-code-workflow` if it exists — it may
   contain project-specific conventions that override this skill.
3. Search for any existing SDD related to the requested change.

## Step 2 — SDD guard

Branch based on what Step 1 found:

**SDD exists — Status: `Accepted`**
Present the document to the user and confirm:
> "An accepted SDD already exists for this. Should I proceed with
> implementation, or would you like to revise the document first?"
- If proceed → jump to **Step 5**
- If revise → update the document's Status to `Draft`, then go to
  **Step 4**

**SDD exists — Status: `Draft`**
Present the document to the user and say:
> "A draft SDD exists for this. Please review it and let me know if
> it needs changes before we proceed."
Go to **Step 4**.

**SDD exists — Status: `Superseded`**
Inform the user that the SDD is marked as superseded. Ask whether to
create a new one or update the existing document. Then go to **Step 3**.

**No SDD found**
Continue to **Step 3**.

## Step 3 — Understand the change

Ask the user any clarifying questions needed to scope the design
correctly. Prefer one focused question over a long list.

## Step 4 — Produce or update the design document

If creating: new file at `docs/designs/<kebab-case-title>.md`.
If updating: edit the existing file in place.

Use the following structure:

```markdown
# <Title>

## Status
Draft | Accepted | Superseded

## Context
What situation or problem motivates this change?

## Decision
What is the proposed solution? Be specific about interfaces,
data structures, and module boundaries.

## Consequences
What becomes easier or harder as a result of this decision?
List trade-offs honestly.

## Alternatives considered
What other approaches were evaluated and why were they rejected?

## Implementation plan
Ordered list of concrete steps. Each step should be small enough
to map to a single commit or a small PR.
```

## Step 5 — Wait for approval

Present the design document and **stop**. Do not proceed to
implementation until the user explicitly approves the document
(e.g. "looks good", "approved", "proceed").

## Step 6 — Implement

Follow the implementation plan from the approved document step by step.
Reference the design document in commit messages where relevant.
