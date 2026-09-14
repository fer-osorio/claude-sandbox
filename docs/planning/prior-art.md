---
status: Approved
date: 2026-09-11
phase: planning
owner: swe-prior-art-research
---

# Prior art

## TL;DR

Adequate prior art exists for each sub-problem individually — rootless-cgroups delegation is a known, partly-unresolved Podman/WSL2 issue class; assumption/RAID logs are established requirements-engineering practice; AGENTS.md-style shared instruction-file conventions are a real, if young (2026), practice. Nothing found addresses the specific combination in `docs/planning/scope.md §Problem statement` — a docs-as-code-governed, injected AI-agent instruction layer citing itself across repo boundaries — so #103 and #104 are novel combinations of known components, not novel problems from scratch. #102's WSL2 cgroups gap traces to a currently-unresolved upstream regression, which raises rather than lowers its priority.

## Findings

**#102 — environment assumptions.** Rootless Podman + WSL2 cgroups v2 delegation is a documented failure class across multiple independent reports (`containers/podman#17202`, `#12983`; `microsoft/WSL#13053`). Root cause: the systemd user session doesn't fully initialize under WSL2, so Podman silently falls back to the `cgroupfs` manager, which does not enforce delegated controllers — this matches this project's own R-6 finding closely. `microsoft/WSL#13053` reports this specifically as a *regression* in WSL 2.5.x (the reporter confirmed 2.4.13 worked), meaning the platform bug resurfaced after being previously fine — a stronger argument for #102's "state it explicitly, don't assume it stays fixed" framing than a one-time known issue would be. `rootlesscontaine.rs`, a community-maintained cross-project reference (high adoption signal, widely cited across the rootless-container ecosystem), documents cgroups v2 delegation as a consequential prerequisite generically, confirming this is a rootless-container class of gap, not a WSL2 quirk. No prior art was found for #102's "does the instruction layer's judgment rules hold under the driving model" row — see Confidence.

**#103 — inference ledger and Planning-entry test.** `arXiv:1210.7101` ("Influence of Context on Decision Making during Requirements Elicitation") establishes that stated requirements rest on stakeholders' implicit, unstated assumptions, and recommends explicitly documenting the contextual assumptions behind what was stated — direct precedent for decision 1's ledger. Industry practice independently converges on the same shape: RAID logs (Risks, Assumptions, Issues, Dependencies) are an established, widely-taught artifact for recording assumptions as falsifiable statements with an owner and a review trigger — though typical RAID practice tracks assumptions rather than gating approval on an empty ledger, which is a stronger mechanism than the precedent. No prior art was found for decision 2 (a Planning-vs-Design boundary keyed on "is the open question whether the work should exist") in any docs-as-code or SDLC-governance framework surveyed; this project's own Case A–E classification already appears to be an unusual, project-specific mechanism, and no comparable analogue for gating *phase entry* (rather than *artifact rigor*) turned up.

**#104 — cross-repo citation portability.** AGENTS.md is a confirmed, adopted (2026) cross-tool convention: a shared instruction file most coding agents read, with tool-specific files (CLAUDE.md included) kept as thin mirrors. Documented practice for monorepos scopes each AGENTS.md to its own subtree — the agent reads the *closest* file, so each one only needs to describe what's under it — which sidesteps #104's failure mode by scoping rather than by fixing citation form. No source addresses #104's specific failure mode directly: a shared file citing a same-repo-relative path that silently resolves to a *different, wrong* file when reused elsewhere, as opposed to simply failing to resolve. Worth flagging the monorepo scoping pattern as a genuine alternative to #104's proposed fix, not just supporting evidence for it. No source addresses the ADR-numbering restart-per-repo collision specifically; it reads as a narrow, self-inflicted instance of general namespace-collision problems rather than a documented pattern.

## Build vs adopt

- **#102**: adopt. State prerequisites using the existing minimal-vs-ideal/degraded-mode framing already common in reliability-engineering practice; cite the WSL 2.5.x regression explicitly rather than as a one-time fixed issue.
- **#103 decision 1 (ledger)**: adopt, with a deliberate strengthening. RAID-log methodology is the precedent; the "empty before `status: Approved`" gate goes beyond typical RAID practice and should be flagged as an intentional design choice when this reaches Design, not an unexamined default.
- **#103 decision 2 (entry test)**: build. No comparable prior art found; closer to plausibly-novel than known-class-novel-combination once decision 1 is set aside.
- **#104**: adopt the principle (keep shared files scope-limited; don't cite what the reader won't have), build the mechanism. No surveyed tool already enforces citation portability *within* a shared instruction file's own prose — the AGENTS.md ecosystem solves this by scoping files, not by a citation-form rule, which #104's design pass should weigh as an alternative.

## Confidence

- WSL2/cgroups (#102): solid — three independent GitHub issues plus a maintained cross-project reference doc. The 2.4.13-vs-2.5.x regression boundary rests on a single reporter's account — treat as anecdotal on the exact version.
- Requirements-elicitation precedent (#103 decision 1): solid on the general principle (multiple convergent sources: one paper, plus independent industry RAID-log practice), single-paper depth on the specific "document context alongside requirements" recommendation.
- #103 decision 2 and #104's core failure mode: thin. No direct precedent surfaced for either — treated here as a genuine absence (per this skill's step 6), not an under-searched gap, given how specific the injected-instruction-layer setup is.
- Retrieval was scoped to Squid's allowlisted domains (`github.com`, `arxiv.org`); several relevant-looking results (`rootlesscontaine.rs`, `morphllm.com`, `medium.com`) were visible via WebSearch summaries only, not independently fetched and read.
