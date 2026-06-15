---
name: design
description: >
  Invoke at the beginning of any significant change — new feature, major
  refactor, architectural decision, or multi-file modification. Also invoke
  explicitly to initialize the docs-as-code workflow for a new project.
  Classifies the change, selects the appropriate workflow, and guides
  artifact production before any code is written.
---

<!-- template-version: docs-as-code-workflow-template 1.0.0 -->

# Design-First Workflow (Docs-as-Code)

Follow these steps in order. Do not write or modify implementation code
until the user explicitly approves the design document (Cases C and D).

## Step 1 — Read project workflow context

Look for `docs/designs/docs-as-code-workflow.md` in the project root.

**Found**
Read it. Its conventions take precedence over the defaults in this skill.
Continue to Step 2.

**Not found — explicit setup request**
User says "initialize docs-as-code", "set up the workflow", "new project
setup", or similar:
1. Read `~/.claude/templates/docs-as-code-workflow-template.md`.
2. Resolve all placeholders and authoring instructions:
   a. Replace `<org>/<repo>` in the frontmatter Scope field.
   b. Replace the §1.1 Current state comment block with one paragraph
      describing the project's existing documentation state honestly (what
      is missing, inconsistent, or undisciplined). Do not leave the
      comment in place.
   c. Review the §1 Scope exclusions list. Add or remove items to reflect
      what this workflow document actually covers for this project.
   d. Add project-specific tools to the §2.2 Tools table (e.g., Docker,
      CMake, vcpkg, Nix). Remove the instructional comment after adding
      entries, or remove the comment alone if no additions are needed.
   e. Add project-specific document types to the §2.2 Document types
      table if the project produces artifacts not covered by the defaults
      (e.g., benchmark reports, threat model documents). Remove the
      instructional comment afterward.
   f. Add project-specific directories to the §2.2 Repository layout
      block if additional directories were added to the document types
      table. Remove the instructional comment afterward.
   g. Case E: determine whether the project has a domain-specific
      workflow requirement (e.g., security-critical changes requiring
      threat model docs, schema migrations requiring rollback procedures).
      If yes, define Case E fully — trigger, required artifacts, minimum
      content. If no, remove the Case E section in §3, the Case E trigger
      in §4, and the Case E row in §5 entirely.
   h. Add project-specific definitions to §6 if new document types or
      terms were introduced. Remove the instructional comment afterward.
   i. Verify that no `<!-- ... -->` comment blocks remain in the output.
      Every comment in the template is an authoring instruction; none
      belong in the committed document.
3. Set `Status: Accepted` in the frontmatter. The decision to adopt this
   workflow is made at setup time; the document records a decision already
   taken, not a proposal under review.
4. Save the result to `docs/designs/docs-as-code-workflow.md`.
5. Propose as a first commit: `docs: add docs-as-code workflow`

Then continue to Step 2.

**Not found — heuristic**
No `docs/` directory exists in the project root, and the requested
change appears non-trivial (not an isolated fix, style change, test
addition, or chore):
> "No docs-as-code workflow document found and no `docs/` directory
> exists. Would you like me to initialize one from the template before
> we continue?"

- Yes → follow the explicit setup path above, then continue to Step 2.
- No → continue to Step 2 using built-in defaults.

**Not found — neither**
Continue to Step 2 using built-in defaults.

---

## Step 2 — Classify the change

Apply the following decision tree. Stop at the first match.

```
0. Is a project-specific Case E defined in
   docs/designs/docs-as-code-workflow.md, and does this change
   satisfy its trigger?
   YES → Case E. Follow the procedure defined in the project workflow
         document.

1. Does this change cross module boundaries, introduce a new abstraction,
   or constrain future design choices?
   YES → Case D if the decision is hard to reverse or binds the project
         long-term. Case C otherwise.

2. Does this change have a motivation that a commit message alone cannot
   fully express?
   YES → Case B, or Case C if the scope spans multiple files or modules.

3. Is the change self-contained, easily reversible, and self-explanatory?
   YES → Case A.
```

Secondary check: if this change goes wrong or needs revisiting in six
months, will you wish you had written down your reasoning? If yes, go up
one case.

---

## Step 3 — Route by case

### Case A — Small, self-contained change
*Applies to: `fix`, `style`, `test`, `chore`, `revert`*

No artifact needed beyond the commit message. The commit body must be
sufficient to explain the change to a reader with no other context.
**Stop here.**

---

### Case B — Motivated change with defined scope
*Applies to: contained `feat`, single-module `refactor`, `ci`, `build`*

1. Guide the user to open a GitHub Issue before writing any code.
   Issue title pattern: `<type>: <short description>`
2. Reference the issue number in every related commit:
   `<type>: <what changed> (#<issue-number>)`
3. The final commit closes the issue:
   `docs: update BUILDING.md or ARCHITECTURE.md (closes #<issue-number>)`

No design document required. **Stop here.**

---

### Case C — Structural change spanning multiple modules
*Applies to: large `refactor`, multi-module `feat`, significant
`ci`/`build` pipeline redesign*

1. Guide the user to open a GitHub Issue.
2. Continue to **Step 4**.
3. The design document becomes the first commit on the branch:
   `docs: design for <feature> (#<issue-number>)`

---

### Case D — Architectural decision
*Applies to: new dependency strategy, new language or runtime, fundamental
change to build or deploy model, any decision that will constrain the
project for a long time*

1. Guide the user to open a GitHub Issue.
2. Skip to **Step 6b**. An ADR *is* the design document for decisions of
   this weight.
3. If execution is non-trivial, propose an implementation plan in
   `docs/plans/<YYYY-MM>-<slug>-v1.md` alongside the ADR.

---

## Step 4 — SDD guard (Case C)

Search for an existing SDD related to the requested change.

**Status: `Accepted`**
Present the document and confirm:
> "An accepted SDD already exists for this. Should I proceed with
> implementation, or would you like to revise it first?"
- Proceed → jump to **Step 7**
- Revise → update Status to `Draft`, go to **Step 5**

**Status: `Draft`**
Present the document and say:
> "A draft SDD exists for this. Please review it and let me know if
> it needs changes before we proceed."
Go to **Step 5**.

**Status: `Superseded`**
Inform the user. Ask whether to create a new document or update the
existing one. Then go to **Step 5**.

**No SDD found**
Continue to **Step 5**.

---

## Step 5 — Understand the change

Ask the user any clarifying questions needed to scope the design
correctly. Prefer one focused question over a long list.

---

## Step 6a — Produce or update design document (Case C)

If creating: new file at `docs/designs/<kebab-case-title>.md`.
If updating: edit the existing file in place.

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
What becomes easier or harder as a result? List trade-offs honestly.

## Alternatives considered
What other approaches were evaluated and why were they rejected?

## Implementation plan
Ordered list of concrete steps. Each step should map to a single
commit or a small PR.
```

Continue to **Step 7**.

---

## Step 6b — Produce ADR (Case D)

New file at `docs/adr/00N-<slug>.md` (increment N from the last
existing ADR).

```markdown
# ADR 00N — <Short title of the decision>

## Status
Proposed | Accepted | Deprecated | Supersedes ADR 00N

## Context
What situation forced this decision? What constraints existed?
What was tried before?

## Decision
What was decided? State it plainly and directly.

## Consequences
What becomes easier, harder, or impossible as a result?
Include both positive and negative consequences.
```

ADRs are **never rewritten**. If a decision is reversed, write a new
ADR with `Status: Supersedes ADR 00N`.

Continue to **Step 7**.

---

## Step 7 — Wait for approval

Present the design document and **stop**. Do not proceed to
implementation until the user explicitly approves
(e.g. "looks good", "approved", "proceed").

---

## Step 8 — Implement

Follow the implementation plan from the approved document step by step.
Reference the design document in commit messages where relevant.
