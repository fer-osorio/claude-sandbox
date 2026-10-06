# A container test tier in CI

## Status

Accepted

## Context

`.github/workflows/ci.yml` selects `--filter-tags hostonly`. That is 48 of the
suite's 80 tests. The other 32 never run in any automated gate, and they are
precisely the ones asserting container properties: egress policy
(`tests/test_squid_isolation.bats`), runtime flags
(`tests/test_runtime_posture.bats`), global-layer injection
(`tests/test_global_layer.bats`), image builds (`tests/test_build.bats`) and
per-profile toolchains (`tests/test_toolchain_smoke.bats`).

Issue #101 is the "separate decision" `ci.yml`'s own header defers. That
header's reasoning still holds: building four images on every push would be slow
and flaky enough to get ignored or disabled, and a documented narrow gate beats
an undocumented broad one. What has changed is the evidence about the
alternatives.

**The cheap option does not exist.** #101 proposed auditing the 21 `fast`-but-not
-`hostonly` tests on the theory that some are miscategorised and could join the
existing gate as-is. None are. Every one needs a container engine, a built
image, or both. The closest call is R-4, which asserts `start.sh` rejects an
unknown image name: `start.sh:156` runs `"$ENGINE" info` and exits before the
name check at `:168`, so without an engine its output is "not reachable" rather
than "unknown image". Reaching it means reordering `start.sh` to validate
arguments before probing the environment — defensible separately, not a
re-tagging.

**Three assertions cannot be honest on a hosted runner.** R-7 and R-8 assert
SELinux mount relabeling (`relabel=shared` versus private); GitHub's Ubuntu
runners use AppArmor and have no SELinux. R-6 asserts that a cgroups v2 memory
limit is *enforced* rather than merely accepted, and Changes 17 and 18 of
`docs/claude-code-security-plan.md` established that this is sensitive to the
host's cgroup layout — rootless Podman on a runner is where a vacuous pass is
most likely. A green gate over those three would assert less than it appears to,
which is worse than no gate.

So the decision is not "run the excluded tests or do not". It is: which
assertions can a runner make honestly, what happens to the rest, and where the
cost lands.

## Decision

**1. A second job, `container`, selecting container tests by tag.** It installs
Podman, creates the `claude-net` network, builds the images the selected tests
need, and runs `bats --filter-tags container,!hostfidelity tests/`.

**2. A new `hostfidelity` tag on R-6, R-7 and R-8**, meaning: this assertion
depends on the host's cgroup or mandatory-access-control layout and cannot be
made faithfully on a hosted runner. The tag is a claim about the environment,
not about speed, which is why it is not `slow`. These three remain
operator-verified, and the SDD says so rather than leaving a reader to infer it
from a tag list.

**3. Two floors, not one.** `ci.yml` already guards its selection against
shrinking (`HOSTONLY_FLOOR`). The container job gets the same guard, and
`hostfidelity` gets its own **ceiling**: if more than three tests carry that
tag, the job fails. Without it, the cheapest way to make a failing container
test green is to tag it `hostfidelity`, and nothing would notice. That is the
#81 failure shape — a test escaping its gate by moving — generalised to a tag
instead of a file.

**4. Cost is tied to risk by a path filter, with a nightly backstop.** The
`container` job runs on a pull request only when it touches `base/**`,
`squid/**`, `global-claude/**`, `start.sh`, `build.sh` or `tests/**`, and
unconditionally on a nightly schedule. A documentation-only PR pays nothing; a
PR touching a control pays; a change that breaks a control from somewhere
unexpected is caught within a day rather than never.

**5. Both tiers publish through the annotation channel.** #113 established that
run logs are unreachable from inside a session while
`check-runs/<id>/annotations` is readable. The container job emits its selected
count and pass/fail counts as `::notice::` the same way, so a session can
confirm which tier ran and what it observed.

**6. Every newly gated assertion is observed failing on the runner once.**
A test that has only ever passed in CI is not known to be running in CI — the
`mechanism-verification` principle, applied to the tier rather than to a single
check. This is a step in the plan below, not a sentiment.

## Consequences

The controls guarding the sandbox stop depending on somebody remembering. A PR
that widens the Squid allowlist, drops `--cap-drop=ALL` or breaks read-only
global-layer mounting fails a gate, and the gate says which tier observed it.

What this costs and what it still does not buy:

**The three strongest runtime assertions stay manual.** R-6, R-7 and R-8 are
excluded by design, and the exclusion is now explicit and bounded rather than
implicit in a tag nobody selects. That is an improvement in honesty, not in
coverage, and the ceiling in decision 3 is what stops it decaying into a
dumping ground.

**A path filter can be wrong.** Tying cost to the paths a PR touches assumes the
touched paths predict the risk. A change to a test helper under `tests/lib/`
that breaks a container assertion is caught; a change to something unlisted that
breaks one is caught only by the nightly run. The filter is a cost decision, and
it is why decision 4 has a backstop rather than standing alone.

**Wall-clock is unmeasured.** Four images plus a Squid build on a hosted runner
has no measured cost in this repository. The plan below measures it before the
trigger is chosen, because "slow enough to get disabled" is the specific failure
`ci.yml`'s header warns about and an estimate would not settle it.

**Podman on a hosted runner is itself an assumption.** Rootless Podman from
Ubuntu's archive, `claude-net` creation, and `--userns=keep-id` all have to work
there. The spike settles that before anything is committed.

**A nightly failure has no owner.** A red scheduled run notifies nobody by
default, which makes it a log rather than a gate. Routing that notification is
out of scope here and is named in the plan as a follow-up rather than assumed
away.

## Alternatives considered

**Chose:** path-filtered PR job plus a nightly backstop.
**Rejected:** build and run the container tier on every push and PR.
**Why the rejected option is attractive:** one tier, no filter to maintain, no
window in which a broken control sits on `main` undetected, and the simplest
thing to explain.
**What breaks if you try it anyway:** it is exactly the cost `ci.yml`'s header
refused, on the reasoning that a slow flaky gate gets disabled — at which point
coverage goes to zero rather than to partial. The filter exists to keep the
common PR fast so nobody has a motive to turn it off.

**Chose:** a `hostfidelity` tag with a ceiling.
**Rejected:** run R-6, R-7 and R-8 on the runner and accept whatever they report.
**Why the rejected option is attractive:** no new tag, no exclusion list to
justify, and the numbers look better — 32 excluded becomes 0.
**What breaks if you try it anyway:** R-7 and R-8 assert SELinux behaviour on a
host that has none, so they would pass without testing anything, and R-6's
enforcement check is the one Changes 17 and 18 showed to be host-sensitive. The
result is a green gate over the three assertions that most need a real one,
which is the failure `mechanism-verification` names.

**Chose:** CI tiers.
**Rejected:** a pre-push hook running the container suite locally.
**Why the rejected option is attractive:** no CI cost at all, and the operator
already runs these by hand, so it formalises existing practice.
**What breaks if you try it anyway:** a hook is bypassable with `--no-verify`
and invisible when bypassed, so it is rung 1 wearing rung 3's clothes. It also
cannot run inside a sandbox session, which has no container engine, so the agent
that writes a control change still could not verify it.

**Chose:** a scheduled backstop.
**Rejected:** merge-queue-only execution.
**Why the rejected option is attractive:** it gates merges exactly once per
merge, which is the cheapest place to put a slow job that must not be skipped.
**What breaks if you try it anyway:** it requires enabling a merge queue on a
single-maintainer repository, and a failure then surfaces after review rather
than during it. Worth revisiting if the repository gains contributors.

## Implementation plan

1. **Spike, nothing committed.** On a throwaway branch, a workflow that installs
   Podman on `ubuntu-latest`, creates `claude-net`, builds all four images plus
   Squid, and runs the full suite. Record on #101: total wall-clock, per-image
   build time, and what R-6, R-7 and R-8 actually do there. This gates step 3's
   trigger choice and may invalidate decision 4.
2. **Tag `hostfidelity`** on R-6, R-7 and R-8, with the reason stated at each
   test rather than only in this document. Add a `container` tag to the five
   container suites. No workflow change yet; `hostonly` selection is unaffected,
   so `HOSTONLY_FLOOR` stays at 49.
3. **Add the `container` job** with the path filter, the selection floor, the
   `hostfidelity` ceiling, and `::notice::` publication. Trigger values come
   from step 1.
4. **Add the nightly schedule** invoking the same job without the path filter.
5. **Negative-control the tier in CI.** Break one assertion per suite on a
   throwaway branch, confirm the job reports it, revert. Record the results in
   each test file's header, as `tests/test_planning_artifacts.bats` already does
   for the P-checks.
6. **Revise the SDD.** `docs/designs/0011-claude-sandbox-testing-module-sdd.md`
   §4's tag axes gain `container` and `hostfidelity`; its header's "deliberate
   trade" paragraph is replaced by what each tier's green now means. Bump the
   version and add a Revision History row.
7. **Correct `ci.yml`'s header** to name both jobs and what each one's green
   does not cover.
8. **Close #101** with the measured numbers, and open a follow-up for routing
   notification of a failed scheduled run, which this design deliberately leaves
   unsolved.
