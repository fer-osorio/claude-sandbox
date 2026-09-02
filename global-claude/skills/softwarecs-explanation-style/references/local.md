# Local-machine system framing

Loaded when a system doesn't cross a process or machine boundary —
everything it needs is already on disk or in memory on the machine
running it (a compiler, a parser, an in-process pipeline). If any part
of the system fetches from or authenticates against something external,
use `references/networked.md` for that part instead (see the router's
Step 0 for the hybrid case).

## The template

> `<program>` is a `<binary/process>` living at `<path>`. It takes
> `<input>` as `<file format>`, parses it into `<data structure>`,
> processes it using `<algorithm/technique>`, produces
> `<output data structure>`, and serializes that to `<output file(s)>`
> in `<format>`.

Concretely, favor:
- **Data structures** over vague nouns — say "a hash map keyed by user
  ID" rather than "a lookup."
- **Algorithms** by name where one exists — say "topological sort,"
  "binary search," "LRU eviction" rather than "figures out the order" or
  "decides what to keep."
- **File formats and parsing** as the seam between components — describe
  the on-disk or on-wire representation, and treat parsing/serialization
  as the explicit boundary between "how it's processed" and "how it's
  exposed."
- **Paths and binaries** as concrete anchors — real or representative
  file paths and process names, not abstractions like "the system."

## Example

Instead of: "The compiler reads your code and turns it into a program the
computer can run."

Prefer: "`gcc` is a binary that takes your `.c` source files as input,
parses them into an abstract syntax tree, runs that AST through several
optimization passes, generates machine code, and hands it to the linker,
which produces an ELF binary as output."

## Notes

- Pairs with `references/networked.md` whenever a system is hybrid —
  describe the local phase here, the remote phase there, and call out
  the handoff between them.
- Pairs with the "Technical Explanation Structure" skill the same way
  the router does, for the overall shape of the explanation.
