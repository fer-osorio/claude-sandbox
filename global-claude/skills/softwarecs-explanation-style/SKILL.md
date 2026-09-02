---
name: softwarecs-explanation-style
description: When explaining software, code, or technical systems, use CS-native framing — binaries/paths, data structures, algorithms, file formats, parsing — instead of plain-language description. Covers both local-machine systems (compilers, parsers, local pipelines, on-disk formats) and networked/distributed systems (API calls, client-server auth, remote fetches). Always check whether the system being explained crosses a process or machine boundary — fetches from, or authenticates against, anything outside local disk/memory — and load the matching reference file, even partially for hybrid systems.
---

## Overview

When the explanation is about software specifically — a program, a
service, a library, a file format, a pipeline — assume computer science
literacy rather than explaining down to a lay audience. Describe the
system the way an engineer would describe it to another engineer, using
the vocabulary in the matching reference file below.

## When to use this skill

Use this framing when explaining:
- How a program, tool, or service works internally.
- How data moves through a pipeline or system.
- How a file format, protocol, or on-disk structure is organized.
- How a client and server, or two services, communicate.

Pairs naturally with the "Technical Explanation Structure" skill — that
skill supplies the shape (why / how / contract), this skill supplies the
vocabulary for the "how" section when the topic is software.

## Step 0: classify the system, then load the matching reference

This skill's only job is routing. Before writing anything, decide
whether the system crosses a boundary, then read the corresponding file
— the vocabulary lives there, not here:

- **Purely local** — everything the system needs is already on disk or
  in memory on the machine running it (a compiler, a parser, an
  in-process pipeline). Read `references/local.md`.
- **Purely networked** — the system's whole job is to talk to something
  else over a wire (an API client, a webhook handler). Read
  `references/networked.md`.
- **Hybrid** — a local process that, at some point, fetches from or
  authenticates against something external (a CLI tool that calls out
  to a remote API; a build step that pulls a dependency; a local git
  binary pushing over HTTPS with a credential helper). This is common —
  don't assume "explaining a local tool" rules out the network. Read
  **both** files: describe the local phase with `references/local.md`,
  the remote phase with `references/networked.md`, and make the
  **handoff between them** explicit — that boundary crossing is usually
  the most important part of the explanation, not an afterthought.

If unsure which bucket a system falls in, check: does it ever resolve
an address, open a socket, or present a credential to something it
doesn't share a filesystem with? If yes, it's hybrid or networked, not
purely local.

## Notes

- Don't force this vocabulary onto explanations that aren't about
  software/CS systems — a question about, say, tax law or a business
  process should use the general structure skill's framing without CS
  jargon grafted on.
- If the person's own framing suggests they aren't asking as an engineer
  (e.g., a stakeholder-level question), this skill shouldn't override
  that context — use judgment.
- Don't load `references/networked.md` for systems that are purely
  local — it adds vocabulary (transport, auth, failure semantics) that's
  irrelevant noise for a compiler or a local parser, and vice versa.
- Don't route questions about a *language's own rules* here — "why is
  this a syntax error," "why won't this type-check," "why is this a
  data race possible" are about the language, not about a system with a
  process boundary, even though they're clearly CS/software topics. Use
  the "PL Explanation Style" skill instead. The boundary case: "how does
  `gcc` work" is this skill (`local.md` — it's a binary at a path with a
  pipeline); "what does the C grammar or type system allow" is PL
  Explanation Style — same binary, two different questions about it.

## Changelog

- **1.3** — Added a Notes bullet distinguishing this skill (systems,
  tools, pipelines with a process boundary) from the new "PL
  Explanation Style" skill (a language's own syntax/type/execution
  rules), with the `gcc`-as-program-vs-`gcc`-as-C-implementation
  boundary case as the disambiguator.
- **1.2** — SKILL.md reduced to pure routing logic. Local framing moved
  out of the body into `references/local.md`, mirroring `networked.md`.
- **1.1** — Split into router + `references/networked.md`. Added Step 0
  boundary classification and the hybrid case. Local framing content
  unchanged from 1.0.
- **1.0** — Initial version: local-machine framing only.
