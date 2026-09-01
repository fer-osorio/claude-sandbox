---
name: pl-explanation-style
description: When explaining a programming language's syntax, semantics, type system, or runtime execution model — not a specific program written in it — use formal grammar and VM/hardware execution vocabulary, not plain-language description. Covers grammar/semantics (CFGs, parsing, AST, typing judgments, inference rules, soundness) and execution model (registers, calling conventions, stack/heap, VM dispatch loops, memory model, concurrency), loaded by relevance rather than either/or. Trigger for why code is a syntax or type error, how type inference/checking works, why code behaves oddly at runtime (races, aliasing, undefined behavior), how an interpreter/VM executes instructions, what a memory model guarantees, or any "why does this language do X" question — even without the words "grammar," "semantics," or "type system." Distinct from softwarecs-explanation-style, which covers a program/tool/service as a system (pipeline, I/O), not a language's own rules.
---

## Overview

When a question is about what a programming language *permits, means, or
does at runtime* — not about a specific tool that happens to be written
in it — assume computer science literacy and describe it using the
formal vocabulary in the matching reference file(s) below, rather than
plain-language description ("that's just not allowed" / "it crashes
because of memory stuff").

## When to use this skill

Use this framing when explaining:
- Why a piece of code is or isn't valid syntax.
- Why code does or doesn't type-check, or how type inference reaches a
  particular type.
- What a language construct actually means (assignment, pass-by-value
  vs. pass-by-reference, closures, generics/monomorphization).
- Why code behaves a certain way at runtime — a data race, aliasing,
  undefined behavior, unexpected performance.
- How an interpreter, VM, or the underlying hardware actually executes
  a construct.

**Not this skill:** "how does `gcc`/`rustc`/`node` work as a program" is
a question about a *tool*, not the language it implements — that's
`softwarecs-explanation-style` (`references/local.md`, since a compiler
binary is a local pipeline). Some questions need both: "why did
upgrading the compiler change this program's behavior" is a pipeline
question (that skill) *and* a language-semantics question (this one) —
describe the compiler as a program in the former's vocabulary, the
specific rule that changed in this skill's, and make the handoff
explicit rather than picking one.

## Step 0: identify which concepts are load-bearing, then read the matching reference(s)

Unlike `softwarecs-explanation-style`'s local/networked split, the two
reference files below are not mutually exclusive branches selected by
classifying the system — they're two lenses that are each independently
relevant depending on what the question is actually asking. Load
whichever the question needs; don't force a single-file answer if the
question spans both.

- **`references/grammar.md`** — for questions about the validity,
  structure, or static meaning of code as written: syntax, parsing,
  ASTs, type systems, type inference, soundness. Read this when the
  question is "is this valid," "why won't this type-check," "what does
  this construct mean before it runs."
- **`references/execution-model.md`** — for questions about what
  happens when code actually runs: registers, calling conventions,
  stack/heap layout, a VM's dispatch loop, memory model, concurrency
  semantics. Read this when the question is "why does this
  crash/race/behave differently," "how is this executed," "what does
  the runtime guarantee."

Many substantive questions need both at once — e.g. "why does
monomorphizing this generic change its calling convention" is
inseparably a type-system question (`grammar.md`) and a
calling-convention question (`execution-model.md`). Read both and
connect them explicitly rather than picking one arbitrarily because it
seemed like the primary one.

## Notes

- Don't force this vocabulary onto explanations that aren't about a
  language's own rules — a question about a specific library's API
  design, or a non-CS topic, should use plain framing or
  `softwarecs-explanation-style` as appropriate, not this skill's
  grammar/execution vocabulary grafted on.
- If a compiler or interpreter's *implementation* is itself the
  subject — its pipeline, its binary, its file I/O — that's
  `softwarecs-explanation-style`; this skill still supplies the
  grammar/execution vocabulary for describing what that program's
  parser or codegen phase is implementing, so the two are meant to be
  read together for questions like "why does this parser reject valid
  syntax."
- Pairs with the "Technical Explanation Structure" skill the same way
  `softwarecs-explanation-style` does, for the overall shape of the
  explanation (why / how / contract) — this skill supplies vocabulary
  for the "how," not the structure around it.
- If the person's own framing suggests they aren't asking as an
  engineer, this skill shouldn't override that context — use judgment.

## Changelog

- **1.0** — Initial version: grammar/semantics and execution-model
  references, loaded by relevance rather than exclusive branch.
