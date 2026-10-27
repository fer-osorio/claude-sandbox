---
status: Approved
date: 2026-10-24
phase: planning
owner: swe-prior-art-research
---

# Prior art

## TL;DR

No published source supports one line count across a directory tree. The
vendor documents limits per load class instead: what loads every session,
what loads when a skill is invoked, and what loads only when read. Only
the first is the cost
`docs/planning/0128-global-layer-line-ceiling/scope.md §Problem statement`
names. D-7's 3000 mixes all three.

## Findings

**Vendor limits are per file and per load class.** Claude Code's
[memory docs](https://code.claude.com/docs/en/memory) say to "target under
200 lines per CLAUDE.md file. Longer files consume more context and reduce
adherence". That is D-6's existing figure. The
[skills docs](https://code.claude.com/docs/en/skills) say three things:
- only descriptions load at session start;
- a body loads on invocation, and the guidance is "Keep `SKILL.md` under
  500 lines";
- the description listing has a budget of 1% of the context window, and
  descriptions are dropped when it overflows. The only sign is a
  warning in the debug log. Each entry is capped
  at 1,536 characters.

**Research measures instructions and tokens, not lines.**
[IFScale](https://arxiv.org/abs/2507.11538) (Distyl AI, July 2025, preprint)
found Claude 4-era models at 82–95% adherence at 100 instructions and
68–82% at 250. Its authors say keyword-inclusion tasks may not generalise.
[Context Rot](https://trychroma.com/research/context-rot) (Chroma, 2025)
and [Lost in the Middle](https://arxiv.org/abs/2307.03172) (Liu et al.,
TACL 2023) show quality falling with length and with position.

**The context-file studies disagree.**
[Gloaguen et al.](https://arxiv.org/abs/2602.11988) found that
`AGENTS.md`-style files rarely raise task success and add over 20% to
inference cost, though their instructions are followed.
[McMillan](https://arxiv.org/abs/2605.10039) (single author, May 2026) found
no effect of file size on adherence (BF₁₀ 0.05–0.10).

**Measured on 2026-10-24, the every-session share is small.** Of D-7's
2816 lines:
- **CLAUDE.md:** 96 lines.
- **Skill descriptions:** 12 of them, 6731 characters in total, the
  longest 1083.
- **Hook output:** two lines, printed only when a project has no user guide.

The rest load on demand. That is 1555 lines of skill bodies, 723 lines of
templates and the hook scripts.

## Build vs adopt

Adopt the vendor's units. Nothing needs inventing.
- **D-6** (200 lines) is already justified by the memory docs.
- **Descriptions** should be bounded against the listing budget. At about
  four characters per token, an assumed conversion, the 6731 characters
  are about 84% of a 200k-token window's budget. On a 1M window they are
  about 17%. Other installed skills share that budget.
- **A skill body** has the documented 500-line guidance.

D-7's 3000 has no external basis. Its own stated purpose, a bound on
unnoticed growth, is a policy choice the literature neither supports nor
contradicts.

## Confidence

The vendor figures are documented but unexplained. No source gives
evidence for 200 or 500.
- **IFScale** is one preprint on simple instructions.
- **McMillan's null** is from a single author.
- **The 84% figure** rests on an assumed characters-per-token ratio.
- **Not consulted:** Anthropic's context-engineering post. The egress proxy
  refused `www.anthropic.com`.
