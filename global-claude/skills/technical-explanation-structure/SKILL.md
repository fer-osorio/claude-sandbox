---
name: technical-explanation-structure
description: Structures "how does X work" explanations into historical context/problem, the process behind it, and the input/output contract with the user. For in-depth explanations, not quick facts.
---

## Overview

When explaining how something works — a system, a process, a tool, a
solution — don't describe the mechanism in isolation. Build the explanation
in three connected layers so the reader understands not just *what* happens,
but *why* it happens that way, and *what they can rely on* without needing
to track the internals.

## When to use this skill

Use this structure when:
- The user asks "how does X work," "why is X built this way," or "explain
  X to me" for a system, process, tool, or solution.
- The explanation is substantive enough to benefit from structure (more
  than a couple of sentences).

Don't use this structure for:
- Quick factual lookups ("what year was X released").
- Simple yes/no or definitional answers.
- When the user explicitly asks for a short answer, a specific format, or
  only one of the three parts below.

## The three-part structure

### 1. Historical context & problem statement — the "why"

State the problem that existed before the solution, and briefly how it came
to be recognized as a problem. This is what gives the rest of the
explanation a reason to exist rather than reading as an arbitrary design.

### 2. Process behind the solution — the "how," tied back to the "why"

Explain the actual mechanism, but keep drawing the connection back to
Part 1: each design choice in the process should visibly trace back to a
constraint or problem named above. Avoid describing the mechanism as a
free-standing sequence of steps disconnected from why those steps exist.

### 3. The interface contract — presentation vs. processing

Close by stating the boundary the user actually operates at: what they hand
in (A), what they get back (B), and make explicit that the internals from
Part 2 are exactly what they don't need to track to use the solution
correctly. Frame this as a contract: "You provide A, you receive B, and you
don't need to reason about how A becomes B to rely on the result." This is
the payoff — it tells the reader what they can safely forget.

## Notes

- Keep proportion sensible: for a simple topic, each part can be one or two
  sentences. Don't pad a simple mechanism into three bloated sections.
- When the topic is software/CS specifically, pair this structure with
  CS-native framing in Part 2 rather than plain-language description —
  but which companion skill supplies that framing depends on what's
  being explained, not just that it's "software":
  - Explaining a *program, tool, or service* — something with a process
    boundary, a pipeline, an I/O contract ("how does `gcc` work," "how
    does this API authenticate a request") — see "Software/CS
    Explanation Style."
  - Explaining a *language's own rules* — syntax validity, type
    checking, why code behaves a certain way at runtime ("why is this a
    type error," "why is this a race condition") — see "PL Explanation
    Style."
  - Some questions need both (e.g. "why did upgrading the compiler
    change this program's behavior" is a pipeline question and a
    language-semantics question at once) — pull in both skills and make
    the handoff between them explicit, the same way either skill does
    internally when a system spans more than one framing.
- If the user only wants the mechanism itself and not the framing, they'll
  typically say so directly ("just the process," "skip the background") —
  respect that and drop the other two parts rather than forcing the full
  structure.
