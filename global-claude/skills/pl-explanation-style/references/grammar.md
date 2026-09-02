# Grammar & semantics framing

Loaded when the question is about the validity, structure, or static
meaning of code as written — before it ever runs. Covers syntax through
type systems as one continuum: both are formal systems of rules that
decide, independent of any implementation, what's permitted and what it
means.

## The template

> A construct is syntactically valid if it can be derived from
> `<grammar rule>`. Where types apply, it's well-typed if
> `<typing judgment>` holds under `<context/environment>` — derived via
> `<inference rule(s)>`. Its static meaning is `<what the type/shape
> guarantees, independent of execution>`.

Not every explanation needs the full chain — a syntax question may stop
at the grammar rule; a type-inference question usually needs the
judgment and the rule that derives it.

## The concepts, and why each is distinct

**1. Grammar (syntax)** — the context-free grammar (CFG) rules,
typically read or written in BNF/EBNF, that define which token
sequences are well-formed. A grammar has terminals and nonterminals,
production rules, and can be ambiguous (more than one valid derivation
for the same input) — which is why parsing *strategy* matters: LL,
LR/LALR, PEG, and recursive descent resolve ambiguity differently and
accept different (sometimes overlapping, sometimes distinct) grammar
classes. "This doesn't parse" is a grammar-rule violation, not a vague
"syntax error."

**2. Parse tree vs. AST** — a parse tree records every grammar rule
applied, including rules that exist only to express precedence or
disambiguate (e.g. an `Expr → Term → Factor` chain for arithmetic). The
AST discards that scaffolding and keeps only the structure that matters
semantically. Conflating the two hides why a language's parser and its
type checker operate on different-shaped trees.

**3. Static (typing) semantics** — the typing judgment, conventionally
written `Γ ⊢ e : τ` ("under context Γ, expression e has type τ"), is
derived via inference rules the same way a parse is derived via grammar
rules — same formal move, different rule set. Type *inference*
(e.g. Hindley-Milner via unification) is the algorithm that reconstructs
missing type annotations by solving those judgments rather than
requiring them written out. Distinguish this from parsing explicitly:
a program can parse successfully and still fail typing — two separate
checks, two separate failure modes, exactly as AuthN and AuthZ are
separate failure modes in the networked framing.

**4. Soundness & decidability** — soundness is the guarantee that a
well-typed program can't reach a stuck state at runtime (informally,
"well-typed programs don't get stuck," Milner's slogan) — it's what
makes the static check worth trusting instead of just running the code
to find out. Decidability is whether the type-checking algorithm is
even guaranteed to terminate with an answer — relevant when explaining
why some type systems need annotations the language "shouldn't" require
in principle (full inference for the feature is undecidable, so the
language falls back to requiring a hint).

**5. Dynamic semantics as a definition, not a story** — operational
semantics (small-step or big-step reduction rules) defines what a
construct *means* as a formal rewrite process, independent of any
particular interpreter's implementation. This is worth distinguishing
from `execution-model.md`'s vocabulary: operational semantics is "what
transformation this expression is defined to undergo," while the
execution model is "what a specific machine or VM actually does to
carry that transformation out." The former is one definition; the
latter can vary by implementation while still honoring it.

## Example

Instead of: "You can't add a string and a number because that's not
allowed."

Prefer: "The `+` operator's typing rule requires both operands to unify
to the same type variable. `string` and `number` don't unify under this
language's rules, so unification fails during type inference — the
expression is rejected before it's ever evaluated. This is a static
error, not a runtime one: the program never reaches a state where `+`
would have to decide what to do with mismatched operands."

## Notes

- Pairs with `execution-model.md` whenever the "how" also needs runtime
  behavior — e.g. explaining monomorphization needs both this file's
  type-system vocabulary and the execution file's calling-convention
  vocabulary.
- If the subject is a specific parser or type checker's *implementation*
  (a binary that reads source and emits an AST) rather than the
  grammar/type rules themselves, that's `softwarecs-explanation-style`'s
  `local.md` — a parser generator is a program with a path, an input
  format, and an output data structure, same as any local pipeline.
- Pairs with the "Technical Explanation Structure" skill for the overall
  shape of the explanation.
