# ADR 014 — The profile contract

## Status

Accepted

## Context

#194 lets several child profiles be built into one image, each member on the
previous one ([`0194-profile-composition.md`](../designs/0194-profile-composition.md)).
That works only if a child Dockerfile can be built on any parent, not just
on `claude-base`, and leaves the image in a state the next member can build
on. Before #194 nothing required either: `crypto` named `claude-base`
literally and set its own `CMD`.

The design records the rules as its Decision 1. They are recorded here as
well because they bind every future profile, including ones written long
after composition stops being the reason anyone reads that design.

## Decision

Every child profile's Dockerfile:

1. opens with `ARG PARENT_IMAGE=claude-base` and `FROM ${PARENT_IMAGE}`, its
   only `FROM`. `build.sh` passes the parent; the default serves a
   standalone build;
2. starts its root work with an explicit `USER root`, and ends as
   `USER claude-agent`: a member cannot assume which user its parent left
   active;
3. sets no `ENTRYPOINT` or `CMD`, which `claude-base` owns;
4. extends `${PATH}` in every `ENV PATH=`, rather than replacing it.

C-41 checks every declared child profile, and B-5's fixture profiles,
against these rules. B-5 builds two fixtures into one image and shows the
rules are enough: both members' files and `PATH` entries survive, the user is
`claude-agent`, and the base entrypoint runs.

## Consequences

- Any profile that passes C-41 can be a combination member with no further
  work.
- A profile cannot rely on its parent's last `USER`, and cannot change the
  session's start command. A profile that needs a different start command is
  outside this contract, and would need a superseding ADR.
- Writing a profile has four rules that did not exist before #194. They are
  checked by a hostonly test, so breaking one fails CI rather than a later
  combination build.

## Alternatives considered

**Chose:** rules over the Dockerfile text, checked statically.
**Rejected:** no rules, and a combination build that fails when a member
does not fit.
**Why the rejected option is attractive:** no constraint on profiles that
are never combined, and nothing to maintain.
**What breaks if you try it anyway:** the failure surfaces in a
combination's build or, worse, as a combination that builds and runs as root
or without the entrypoint. The author of the member is not the person who
finds it.

**Chose:** an explicit `USER root` / `USER claude-agent` pair in each
profile.
**Rejected:** relying on the parent's `USER`.
**Why the rejected option is attractive:** one line fewer per profile, and
true today, since every parent ends as `claude-agent`.
**What breaks if you try it anyway:** it holds only while every parent obeys
rule 2, so one non-conforming member makes the next one's root work fail, or
run as root without saying so.
