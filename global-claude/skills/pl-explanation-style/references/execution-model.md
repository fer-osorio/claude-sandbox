# Execution model framing

Loaded when the question is about what actually happens when code runs
— below the level of "the language lets you do this" and down to how a
CPU or VM carries it out. The grammar/type system says what's allowed;
this file says what it costs and how it's physically realized.

## The template

> At runtime, `<construct>` is realized as `<representation>` — held in
> `<register / stack slot / heap location>` per `<calling
> convention/ABI>` — and executed via `<dispatch mechanism>`. Concurrent
> access to it is governed by `<memory model guarantee>`.

## The concepts, and why each is distinct

**1. Representation & storage** — where a value actually lives:
a register, a stack frame slot, or the heap, and whether the language
gives you *value* semantics (copies) or *reference* semantics (aliases
to the same storage) for that construct. This is the direct runtime
counterpart of the grammar file's static types — a type says what shape
a value has; storage says where and how many copies of it exist.

**2. Calling convention / ABI** — how arguments and return values cross
a function-call boundary: which are passed in registers vs. pushed on
the stack, which registers the callee must preserve (callee-saved) vs.
is free to clobber (caller-saved), and how the return address and
previous frame pointer are recorded so the stack can unwind correctly.
This is the mechanical layer beneath "the function receives its
arguments" — different calling conventions (cdecl, System V AMD64,
a language's own VM-internal convention) make different tradeoffs here,
and generic/polymorphic calls often need this made explicit (e.g. why
monomorphization changes what convention applies per instantiation).

**3. Dispatch mechanism** — how the next instruction gets selected and
run. For compiled/native code this is hardware fetch-decode-execute
directly. For a VM'd or interpreted language it's a bytecode dispatch
loop — a switch over opcodes, threaded dispatch, or a JIT that
compiles hot paths to native code partway through execution. Naming
which one applies is what turns "the interpreter runs your code" into
an actual explanation of the performance or behavior in question.

**4. Memory model & concurrency semantics** — what a concurrent read is
guaranteed to observe about a concurrent write: sequential consistency,
a happens-before relation, or (for a data race) no guarantee at all,
which in some languages is explicitly classified as undefined behavior
rather than merely "unpredictable." This has no equivalent in the
grammar file's static world — it's specifically about what multiple
threads of execution can observe about shared storage, and it's the
concept that turns "this is a race condition" into a precise claim
about which guarantee is violated.

## Example

Instead of: "Recursion uses up memory with each call."

Prefer: "Each call pushes a new stack frame holding the callee's local
variables, its return address, and — per the calling convention — the
arguments that didn't fit in registers. Unwinding on return pops that
frame. Without tail-call optimization, a frame stays live for the
entire duration of the call it made, so recursion depth is bounded by
stack size, not by heap availability."

## Notes

- Pairs with `grammar.md` whenever the explanation needs both what a
  construct is typed as and how it's realized at runtime — most
  "why is this generic/polymorphic call slow" or "why does this type
  change memory layout" questions need both.
- If the subject is a specific interpreter or VM's *implementation*
  (its source files, its dispatch loop as a body of code, its build) —
  rather than the execution semantics it's realizing — that's
  `softwarecs-explanation-style`'s `local.md`: a VM is itself a program
  with a path and a pipeline, same as any local process. This file
  supplies the vocabulary for describing what that dispatch loop is
  doing, not for describing the program that contains it.
- Pairs with the "Technical Explanation Structure" skill for the overall
  shape of the explanation.
