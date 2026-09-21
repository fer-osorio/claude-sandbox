# ADR 009 — One passphrase-wrapped age identity for the credential store

## Status

Accepted

This records the key-management decision behind issue #129. The storage and
injection mechanics are in `docs/designs/0129-encrypted-credential-store.md`
and are revisable; what is written here is not, because credentials already
encrypted against an identity cannot be un-encrypted by editing a document.

## Context

`start.sh` forwarded one credential, `GH_TOKEN`, from the launching shell:
unscoped, unencrypted at rest, and with nowhere to put a second.
`docs/planning/0129-encrypted-credential-store/scope.md` §Problem statement
holds the full statement, and
`docs/planning/0129-encrypted-credential-store/charter.md` §Decision records
the go.

Two things forced a decision rather than an implementation detail.

**Encrypting anything at rest means choosing what protects the key**, and that
choice is load-bearing in a way the surrounding code is not. Whatever guards
the key is functionally as sensitive as every credential in the store
combined.

**The choice is hard to reverse.** Changing the scheme later means decrypting
every file under the old one and re-encrypting under the new — possible, but
only while the old key still exists. An operator who has lost it has no
migration path, only revocation and reissue at each credential's issuer.

`docs/planning/0129-encrypted-credential-store/prior-art.md` §Build vs adopt
established that the primitives were settled and that the work was glue. It
did not decide the key model.

## Decision

**`age`, with exactly one X25519 identity for the whole store, wrapped at rest
with a passphrase typed at each launch of a credentialed project.**

Concretely:

- `creds.sh init` generates one identity. Its public half is stored in the
  clear as `recipient.pub`; its private half is scrypt-wrapped with the
  operator's passphrase as `identity.age`.
- Every project's credential file is encrypted to that one public key.
  Writing therefore needs no passphrase; reading does.
- `start.sh` unwraps the identity into a file descriptor and pipes it into the
  decryption of one file. The unwrapped identity is never a variable, never a
  file, and never an argument.
- There is no caching and no agent. The prompt is per launch.

`age` rather than GPG follows the prior-art finding; one identity rather than
one per project or per file is the part decided here.

## Consequences

**A passphrase prompt on every credentialed launch, with no way to avoid it.**
Caching would mean a daemon holding an unwrapped key — a new component and a
new thing to protect, which is the shape of the problem this was meant to
reduce. The friction is real and is left in place: it is also the pressure
that keeps the store small, which
`docs/designs/0129-encrypted-credential-store.md` §Sensitivity tiering policy
depends on.

**Non-interactive invocation becomes impossible for credentialed projects, by
construction.** CI cannot use this, and that is a named non-goal in
`docs/planning/0129-encrypted-credential-store/scope.md` §Non-goals rather
than an oversight. Anything that needs unattended credentials needs a
different mechanism.

**`identity.age` becomes a single point of failure for the whole store.**
Losing it or forgetting the passphrase makes every credential unrecoverable,
not merely leaked. The only mitigation available is a procedure a person
performs, which is why
`docs/designs/0129-encrypted-credential-store.md` §Key lifecycle was a
condition on the design rather than a follow-up.

**Adding a credential to a new project needs no passphrase**, because writing
needs only the public key. Adding a second one to the same project does,
because a project's credentials share a file.

**`age` becomes a host prerequisite** whose absence aborts a credentialed
launch rather than degrading to no credentials.

**Rotation stays possible but is manual and whole-store.** `creds.sh rotate`
re-encrypts every file to a new identity and keeps the old one as
`identity.age.prev`. There is no partial rotation and no per-project key.

## Alternatives considered

**An SSH key already in `ssh-agent` as the identity.**
**Chose:** a dedicated passphrase-wrapped identity.
**Rejected:** `age`'s native support for SSH keys as identities.
**Why the rejected option is attractive:** it creates no new secret at all. It
inherits whatever already guards the agent — including a hardware token — and
unlocks once per shell session rather than once per launch, which removes the
one consequence above that the operator will actually feel. On a host where
`ssh-agent` is already unlocked for `git push`, the store would open with no
prompt whatever.
**What breaks if you try it anyway:** nothing technical, which is why this is
the alternative most likely to be reinvented. What it costs is that the
store's security becomes a property of the SSH agent's configuration — agent
forwarding, `AddKeysToAgent`, lifetime settings — none of which this project
controls or can check, and all of which can change without anyone touching
this repository. It also couples credential access to a key whose real job is
authenticating elsewhere, so revoking or rotating that key for unrelated
reasons silently locks the store. The passphrase model keeps the store's
protection inside the store. If per-launch prompting proves too costly in
practice, this is the option to revisit, and it needs a new ADR.

**A passphrase per credential file, with no identity.**
**Chose:** one identity, one passphrase.
**Rejected:** `age --passphrase` directly on each project's file.
**Why the rejected option is attractive:** it is the simplest thing that
works. No identity file, no public key, no key material on disk at all, and
no single point of failure — losing one passphrase costs one project, not the
store.
**What breaks if you try it anyway:** it degenerates. Either the operator
reuses one passphrase across every file, which is a shared secret with extra
ceremony and strictly worse than an identity, or they keep a distinct
passphrase per project, which is a password manager the store was supposed to
replace. It also makes `creds.sh add` prompt every time, and rotation becomes
per-file.

**An OS keychain.**
**Chose:** a passphrase.
**Rejected:** Secret Service, or a bridge to Windows Credential Manager.
**Why the rejected option is attractive:** unlock is handled by the desktop
session, so there is no prompt and no passphrase to forget, and key material
is held by something more careful than a shell script.
**What breaks if you try it anyway:** WSL2 runs no Secret Service daemon by
default, and this project's `BUILDING.md` is WSL2-first. Bridging to Windows
Credential Manager adds a host-specific component to a launch path that is
currently plain Bash, and it would have to fail closed on hosts that lack it —
so the passphrase path would need to exist anyway as the fallback.

**Per-project identities.**
**Chose:** one identity for the store.
**Rejected:** one keypair per project.
**Why the rejected option is attractive:** it bounds the blast radius of a
compromised identity to one project, which is the same instinct that makes
per-project credential files worth having in the first place.
**What breaks if you try it anyway:** the operator now manages N passphrases
or one passphrase protecting N identities, which is the first alternative's
failure again with more files. The blast radius it bounds is also the wrong
one: the threat model here is the agent inside the container, which never sees
any identity, not an attacker on the host, against whom
`docs/planning/0129-encrypted-credential-store/scope.md` §Non-goals declines
to defend.

## References

- `docs/designs/0129-encrypted-credential-store.md` — storage, injection,
  key lifecycle, and the tiering policy.
- `docs/claude-code-security-plan.md` §Phase 4 and Change 26 — threat model
  and residual risk.
- `docs/planning/0129-encrypted-credential-store/prior-art.md` §Build vs adopt
  — why `age` rather than GPG, and why the store itself is not adopted
  wholesale.
