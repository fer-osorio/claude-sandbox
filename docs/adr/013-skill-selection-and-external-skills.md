# ADR 013 — Skill selection and a pinned layer for external skills

## Status

Accepted

## Context

#136 asks for a way to inject skills this project did not write. Some
organizations require their own skills as a condition of working with them,
and a project with several contributors cannot insist that one person wrote
every instruction. #135, skill selection, was folded into #136 because
selection is the mechanism an external source is selected through
([comment](https://github.com/fer-osorio/claude-sandbox/issues/136#issuecomment-6474132904)).
No organization requires this today. The decision is made now so that a
requirement, when it arrives, meets terms that were set beforehand.

**What exists.** `start.sh` bind-mounts all of `global-claude/` read-only at
`/run/claude-global`. `base/entrypoint.sh` copies it into `~/.claude/`, then
copies the profile overlay over it with `cp -r`, so a later file silently
replaces an earlier one of the same name. D-2 keeps what the agent is told
knowable after the fact: every skill the layer names is committed under
`global-claude/skills/`.

**What #128 changed.** Only the skill descriptions and `CLAUDE.md` load in
every session
([`0128-global-layer-load-class-bounds.md`](../designs/0128-global-layer-load-class-bounds.md)).
On its own, selection saves at most the 5797 bytes of the description
listing. Its value is the attack surface it removes and the mechanism it
gives an external source.

**What raises the stakes.** Design
[`0129-encrypted-credential-store.md`](../designs/0129-encrypted-credential-store.md)
§Sensitivity tiering policy requires that "every Inject-tier value must be
assumed readable by the agent". Instructions written by a third party
therefore run beside values the agent can read.

**The baseline.** A skill that an organization mandates runs somewhere. The
comparison is against that skill running on the plain host, not against a
sandbox that never accepts one.

**Reachability.** The repository is public, and the sandbox is at times
pointed at itself. In that case the agent can write to `config.local.sh`,
which is gitignored.

## Decision

**1. Selection.** `GLOBAL_SKILLS` is a space-separated list of names, so
that every layer of design
[`0028-sandbox-config-file.md`](../designs/0028-sandbox-config-file.md),
the environment included, can set it.
- Unset means every committed skill. This is the default, so nothing
  migrates.
- Set, it names exactly the base skills injected. An empty value means none.
- A name that is not a directory under `global-claude/skills/` aborts the
  launch. This includes a name that exists only in an overlay. The overlay
  is selected by choosing a profile, and selection does not filter it.
- The selection is made per session, not per profile.

**2. Staging.** For each launch, `start.sh` creates a directory with
`mktemp -d`, mode 0700, and mounts it read-only at `/run/claude-global` in
place of `global-claude/`.
- It copies every top-level entry of `global-claude/` except `skills/`.
- It copies the selected skills, then the external skills.
- `cleanup` removes the directory on every exit path, and the EXIT trap is
  installed before staging begins.
- `base/entrypoint.sh` and the mount target do not change, so this is not
  Case E.

**3. External skills: a local directory and a manifest in
`config.local.sh`.** `EXTERNAL_SKILLS_DIR` names a host directory of skill
directories. `EXTERNAL_SKILLS`, an associative array, maps each name to a
content hash and an informational source, such as a URL and a revision.
- `start.sh` never fetches anything.
- The manifest is never committed, so this public repository names no
  organization's skills.

**4. What aborts the launch.** Each of the following:
- a directory present in `EXTERNAL_SKILLS_DIR` but absent from the
  manifest, or the reverse;
- a hash mismatch, computed on the staged copy rather than the source, so
  the bytes checked are the bytes mounted;
- any entry that is not a regular file or a directory, such as a symlink,
  which could otherwise pull a host file into the container;
- a name that collides with any committed base skill or any overlay skill,
  selected or not;
- frontmatter in an external `SKILL.md` with a key other than `name` or
  `description`. This shuts out keys that would change permissions or run
  code, such as `allowed-tools` or `hooks`, without listing the vendor's
  keys one by one.

The hash is SHA-256 over the sorted list of relative paths and the SHA-256
of each file's content. The manifest's comment documents the command that
computes it.

**5. External skills contribute `skills/<name>/` only.** They never supply
`CLAUDE.md`, `settings.json`, hooks or templates. The permissions and
instructions that hold every session together stay this project's.

**6. D-2 is unchanged.** External skills never enter `global-claude/`. A base
skill that names one still fails D-2, so the committed layer stays
self-contained. D-15 measures the committed tree, as before. At launch,
`start.sh` warns if any external description exceeds 1536 bytes, or if the
injected descriptions together exceed 6000.

**7. The banner names what was injected.**
- `Skills:` gives the selected base skills, or `all (N)`.
- `External:` gives each external skill with its source and the first 12
  hex digits of its hash.

Both lines appear before the container starts.

**8. External skills and injected credentials may share a session.** The
residual risk is stated in Consequences. 0129's tiering is what bounds it.

**9. Order.** Decisions 1, 2 and 7 for base skills ship first, in their own
PR. Decisions 3 to 6, and the `External:` line, are built when an actual
requirement arrives, against this ADR. If that requirement does not fit
these terms, a qualifying ADR comes first.

## Consequences

**What is traded.** For external content, *this was read and approved*
becomes *this is the content the operator pinned*. The hash proves that the
content is unchanged since it was pinned, not that the organization shipped
it. Provenance is recorded, not proved. Proving it would take the
organization's signatures, which are out of scope. A pin is only as good as
the review behind it.

**Repudiation is weaker for external skills.** The manifest is untracked, so
git history cannot reconstruct what an external skill said. What remains is
the launch banner and the hash. That is the price of keeping organization
names out of a public repository.

**Third-party instructions run beside readable credentials (decision 8).**
An external skill can tell the agent to use or print any Inject-tier value
in the session. Exfiltration goes only where the squid allowlist allows,
but that includes GitHub. 0129's operative test, "would I be comfortable if
this value were printed into a session transcript?", now covers instructions
the operator did not write. Both the `Creds:` and the `External:` lines show
on the banner, so the combination is never silent.

**A session pointed at this repository can edit the manifest.** Because
`config.local.sh` is untracked, the edit shows up in no diff. The next
launch's banner is the only signal. This is the same exposure the agent
already has to `start.sh` and `config.sh` in that setting, but less visible.

**The description budget is outside the repository's control.** External
descriptions count against the vendor's listing budget, which D-15 cannot
see. Decision 6 warns at launch rather than aborting, because the cost is
that some descriptions are truncated, not that a boundary is crossed.

**Selection pays for its saving.** Every launch now copies the layer, about
100 KB, which is negligible. It also gains a temporary directory to clean
up. An unknown name fails loudly, which is the failure #135 named.

**Tests must exercise `start.sh` itself.** A stub engine records the mount
arguments and lists the staged directory. That is the observation #173
lacks, and it covers the `readonly` flag on the global mount at the same
time.

## Alternatives considered

**Chose:** keep D-2 and add a second source with its own invariant.
**Rejected:** exempt external skills from D-2.
**Why the rejected option is attractive:** it is one line, and no new
mechanism is needed.
**What breaks if you try it anyway:** what the agent was told stops being
knowable, and nothing takes its place. D-2's whole value goes.

**Chose:** merge the external skills into the staged `/run/claude-global`.
**Rejected:** a separate `/run/claude-external` mount, as #136 first
proposed.
**Why the rejected option is attractive:** the container itself would keep
the layer's provenance, and the separation would be visible in `mount`.
**What breaks if you try it anyway:** it changes `base/entrypoint.sh`, which
is Case E, and buys nothing. The entrypoint merges everything into
`~/.claude/` anyway, so the separation ends at copy time. The host banner
carries the provenance.

**Chose:** staging on the host (#135's option a).
**Rejected:** pass the selection to the entrypoint and filter while copying.
**Why the rejected option is attractive:** it is the smallest diff, and no
temporary directory is needed.
**What breaks if you try it anyway:** unselected skills still enter the
container at `/run/claude-global`, so selection removes no attack surface.
It is also Case E.

**Chose:** an untracked manifest.
**Rejected:** a committed manifest, as #136 proposed.
**Why the rejected option is attractive:** every pin is reviewed in a PR and
recoverable from history. That is the strongest Repudiation control
available.
**What breaks if you try it anyway:** the public repository names each
organization's skills and sources. A private fork that wants a committed
manifest can source one from `config.local.sh`.

**Chose:** a local directory.
**Rejected:** fetch from a git repository at a pinned commit.
**Why the rejected option is attractive:** it is automated, and the commit
is a provenance the organization itself publishes.
**What breaks if you try it anyway:** the launcher gains network egress that
squid's allowlist does not govern, and a failed fetch becomes a launch
failure mode. The operator can check out that commit into the directory and
record it as the source.

**Chose:** an allowlist of frontmatter keys.
**Rejected:** accept any frontmatter, or list the dangerous keys.
**Why the rejected option is attractive:** an organization's skill may use
`allowed-tools` legitimately, and refusing it turns away a skill the
operator was told to run.
**What breaks if you try it anyway:** a skill could widen tool permissions
or attach hooks that `settings.json` does not show. A denylist goes stale
the first time the vendor adds a key. Relaxing the allowlist key by key is
a qualifying ADR.

**Chose:** allow credentials and external skills together (operator's
decision, 2026-10-28).
**Rejected:** make them mutually exclusive.
**Why the rejected option is attractive:** third-party instructions never
run beside a value the agent can read. It is the simplest control, and it
can be relaxed later.
**What breaks if you try it anyway:** an organization that mandates skills
and also needs a token cannot use the sandbox at all. The work moves to the
plain host, which is the baseline this ADR is measured against, and that
outcome is worse.

## References

- #136; #135, folded in; #173, the untested `start.sh` flags; #179, the
  description budget
- [`0003-global-layer-injection.md`](../designs/0003-global-layer-injection.md)
  §4.3, §4.4, §5: the mechanism and its threat model
- [`0028-sandbox-config-file.md`](../designs/0028-sandbox-config-file.md):
  the layered overrides
- [`0129-encrypted-credential-store.md`](../designs/0129-encrypted-credential-store.md)
  §Sensitivity tiering policy
- [`0128-global-layer-load-class-bounds.md`](../designs/0128-global-layer-load-class-bounds.md):
  D-15 and the load classes
