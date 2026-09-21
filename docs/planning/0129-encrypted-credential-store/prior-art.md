---
status: Approved
date: 2026-09-20
phase: planning
owner: swe-prior-art-research
---

# Prior art

## TL;DR

Every layer of this design has established prior art: age and SOPS for the
store, SOPS+age+direnv for per-project env injection. The AI-agent-specific
precedent is real but narrower than the earlier pass reported — two
maintained projects, three that do not survive an adoption check. Adopt the
primitives, build the integration.

## Findings

**The store layer is settled.** [`age`](https://github.com/FiloSottile/age)
(23.6k stars, active) and [SOPS](https://github.com/getsops/sops) (23.2k,
active) are both mature; `pass` has been the canonical "one encrypted file
per secret, shell-scriptable" answer for over a decade.
[`passage`](https://github.com/FiloSottile/passage), age's author's fork of
`pass`, confirms the design direction the scope takes — but its last commit
is August 2024 (1.2k stars), so it is a settled argument, not a maintained
dependency. Nothing here needs inventing.

**The per-project injection pattern is near-identical prior art.** SOPS +
age + `direnv` is the dominant form of "enter a project, get its secrets as
env vars, decrypted from something at rest," documented across independent
write-ups and a long-running direnv issue thread. The scoped design differs
in two ways: it triggers on a container launch rather than a shell `cd`,
and it declines to track ciphertext in git at all. The second is a real
divergence — SOPS's dotenv mode exists precisely so encrypted values can
live in a tracked repo with readable key names, and this project rejects
that because filenames alone disclose which projects hold which credentials
(`docs/planning/0129-encrypted-credential-store/scope.md §Constraints`).

**Container guidance points the other way, and the inversion needs
arguing.** OWASP's Docker Security and Secrets Management cheat sheets
recommend read-only file mounts over environment variables, because env
vars surface in `docker inspect`, `/proc/self/environ` and process
listings. Taken at face value that contradicts this design. It does not
survive the threat-model swap: OWASP assumes a human attacker with daemon
access, while here the adversary is the process inside the container, for
which a mounted file is strictly worse — directly readable by the agent's
own Bash tool. Defensible, but it must be argued in writing or a later
reviewer will read it as an oversight.

**AI-agent-specific prior art is thinner than reported.** Two projects are
real:

- [Infisical `agent-vault`](https://github.com/Infisical/agent-vault) (2.2k
  stars, commits today) — an HTTP credential proxy that swaps placeholder
  credentials for real ones in outbound requests, deployed on a separate
  machine from the agent. The closest thing to a maintained implementation
  of the proxy-substitution follow-up this scope defers.
- [VirtusLab `sandcat`](https://github.com/VirtusLab/sandcat) (193 stars,
  active) — architecturally the nearest analog to this project:
  devcontainer, all traffic through a transparent mitmproxy, env vars hold
  `SANDCAT_PLACEHOLDER_*` values substituted only for allowlisted hosts,
  everything else 403.

Three others cited in the prior conversation do not hold up. "Clawgate"
names at least three unrelated projects; the one matching the description
has 17 stars and no commits since February 2026. "envseal-vault" resolves
to five unrelated `envseal` repositories, none above four stars.
`sops-mcp` exists with zero stars. None is evidence of an established
pattern.

## Build vs adopt

Adopt the primitives, build the glue. `age` is the right encryption tool;
the scope's choice of it over GPG is well supported, and `passage`'s
existence settles that argument even though the tool itself is stale.

Do not adopt a store wholesale. `pass`/`passage` assume a human browsing a
password tree, and SOPS assumes tracked, team-shared, frequently-diffed
config — neither matches one flat `KEY=value` file per project, untracked,
read by a launcher. The integration is perhaps a hundred lines of shell
around `age`, which is smaller than bending either tool to fit.

Do not build toward proxy substitution now. `agent-vault` and `sandcat` are
maintained implementations of that architecture; if the follow-up is ever
taken up, the question is whether to adopt one rather than write a third.

## Confidence

Two sources could not be checked: `clawgate.io` and the Knostic report on
agents leaking `.env` files are both off this sandbox's egress allowlist,
so ClawGate is judged only from GitHub search results. Star counts are a
crude adoption proxy. The OWASP and direnv findings rest on primary
sources; the "thinner than reported" verdict rests on repository metadata,
which is verifiable and cheap to recheck.
