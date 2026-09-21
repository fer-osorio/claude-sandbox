---
status: Approved
date: 2026-09-20
phase: planning
owner: project-planning
---

# Scope

## TL;DR

Replace the shell-sourced `GH_TOKEN` passthrough in `start.sh` with a
host-side store that is age-encrypted and kept per project, whose values
reach the container by name only. Worth doing if it takes plaintext
credentials out of the operator's shell without widening what the agent
container can already see.

## Problem statement

`start.sh` forwards one credential, `GH_TOKEN`, from whatever the launching
shell holds. That single source has three consequences: the credential is
not scoped per project, it is not encrypted at rest on the host, and a
project needing a second credential has nowhere to put it. Solved means
each project has its own encrypted set of `KEY=value` credentials, which
`start.sh` decrypts at launch and forwards by name only, leaving the
container's exposure exactly as it is today.

## Constraints

- `age`, with one X25519 identity protected by a passphrase typed at each
  launch of a credentialed project.
- Credential files keyed by a hash of the resolved `PROJECT_DIR`.
- Decryption is host-side only. No plaintext touches disk; values reach the
  container as `-e KEY`.
- A decrypt failure aborts the launch; a missing file is skipped silently.
- `credentials/` is never git-tracked.
- Timeline and budget: not yet decided.

## Non-goals

- Proxy substitution through the Squid layer — named follow-up.
- An SSH private key injected as a payload for the agent to use — named
  follow-up.
- An SSH key as the store's identity — dropped, since the passphrase was
  chosen instead.
- Running without an operator present, including CI. The passphrase prompt
  makes this interactive-only by construction.
- Defending against a compromised host.
- Closing the in-container plaintext exposure (`echo $KEY`, `podman
  inspect`). Knowingly accepted as residual risk, not solved.

## Definition of done

- Bats coverage for three cases: credential present and injected,
  credential absent and launch proceeds, decrypt failure aborts.
- A companion script supports add, list, rotate and migrate.
- A backup and recovery procedure for the identity is documented.
- A sensitivity-tiering policy is written: safe to inject / needs proxy
  substitution / never inject.
