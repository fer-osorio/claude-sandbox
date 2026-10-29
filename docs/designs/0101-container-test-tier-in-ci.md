# A container test tier in CI

## Status

Accepted

## Corrections

Factual corrections only, dated. The text they correct is left as written.
Revisions to how a decision is carried out are marked in the decision
itself.

**2026-10-20: the denominators were one low.** Context says `hostonly` is
"48 of the suite's 80 tests". When this document was accepted, the suite was
81 tests and `hostonly` selected 49. The figure of 32 excluded was right. The
testing SDD and `ci.yml`'s `HOSTONLY_FLOOR` already used 49. Since C-21 (the
`build.sh all` exit status, found by this tier's first run), the figures are
82 and 50, with 32 still excluded. No decision is affected.

**2026-10-20: the cost claim named the wrong cause.** Consequences says "the
Squid suite's real network requests dominate". Three spike runs say
*failing* requests dominate: 316s with nothing failing, against 395–485s
with two or three failures, on 135–157s of builds. Cost per group was never
measured on the runner. The conclusion that builds are not the expensive
part stands. No decision is affected.

**2026-10-20: Consequences claims more than the tier gates.** It says "a PR
that widens the Squid allowlist, drops `--cap-drop=ALL` or breaks read-only
global-layer mounting fails a gate." The first holds. The other two do not
hold for `start.sh`, the place a session gets those flags. R-2, R-3 and
G-1 to G-3 pass their own flags to `engine_run`, so they show the engine
applies them, not that `start.sh` asks for them. Step 7 removed
`--cap-drop=ALL` from `start.sh`'s session container, and `readonly` from
its global-layer mount, and no test in either tier failed. The records are
in the headers of `tests/test_runtime_posture.bats` and
`tests/test_global_layer.bats`. No decision is affected, but the control is
ungated until a test reads `start.sh`'s own arguments.

**2026-10-20: #160 did not make the Squid suite answer the same way twice.**
Consequences makes that a hard dependency of the tier. #160 closed with a
retry that has now been observed on a runner and cannot help. Of the six
runs since it landed, five left at least one host unanswered (0 to 6 of
8). Each unanswered host shows the same shape: a first attempt of 36–40s,
then retries answered in 0 ms from Squid's negative DNS cache. The
resolver is aardvark-dns 1.4.0 under Podman 4.9.3 on Ubuntu 24.04.5. Since
`3331970` an unanswered host fails only the assertions that read it,
labelled as the harness rather than the policy. So the variance is
attributable, but it is not gone. **Whether the tier is a gate while this
holds is open.** The dependency the plan stated is unmet.

**2026-10-21: the cause was the harness, and it is fixed.** The entry above
attributed the variance to Squid's DNS. The cause was the harness, which
started a fresh curl container for every request. A container starting on
claude-net makes aardvark-dns 1.4.0 drop queries for several seconds. On the
runner, 10 of 20 lookups lost one or two tries with a container starting
alongside them, and 0 of 20 without (probe run 39638126824). Squid gives up
after three unanswered tries in 39.72s, which is the 36–40s first attempt. A
real session has one long-lived client, so the policy was never at fault.
Since `6922d17` the suite sends every request from one client. The next
three runs (39683131282, 39683138144, 39683143969) were green, with no
retries. The dependency in Consequences is met, though three runs is a small
sample and the nightly runs are the continuing check. #160's retry remains as
a backstop.

**2026-10-21: the ungated `start.sh` flags are tracked.** The third entry
above is now #173.

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
unknown image name: `start.sh` runs `"$ENGINE" info` and exits before the
image-name check, so without an engine its output is "not reachable" rather
than "unknown image". Reaching it means reordering `start.sh` to validate
arguments before probing the environment — defensible separately, not a
re-tagging.

**One assertion cannot be honest on a hosted runner, not three.** This was
measured rather than reasoned about — two spike runs on `ubuntu-latest`, recorded
on #101:

| Fact | Value |
|---|---|
| Podman | 4.9.3, rootless, `claude-net` creates cleanly |
| Mandatory access control | AppArmor enabled; **no SELinux** |
| cgroups | `cgroup2fs`, delegated controllers `cpu memory pids` |
| Build cost | 135–136s for all four images plus Squid |
| Suite cost | 395–485s for all 80 tests |

R-7 and R-8 assert SELinux mount relabeling, and on a host without SELinux they
**skip with a stated reason** rather than passing vacuously. The design that
preceded this measurement assumed they would pass while asserting nothing; they
already handle it honestly, so they need no special treatment.

R-6 is the real case. It asserts that a cgroups v2 memory limit is *enforced*
rather than merely accepted, and it fails on the runner in both runs — even
though `memory` is in the delegated controller set, which is the condition one
would expect to be sufficient. Changes 17 and 18 of
`docs/claude-code-security-plan.md` established that this behaviour is sensitive
to the host's cgroup layout; the measurement confirms delegation alone does not
make it assertable.

**Two findings outside this design's scope came out of the same measurement**,
and the tier depends on both: R-5 reports a failure rather than a skip on any
fully-built machine (#159), and the Squid suite returns a different set of
failures on each run through intermittent name resolution inside the proxy
container (#160). Critically, `TCP_DENIED/403` appeared only for the deliberately
blocked domain across both runs, so the shipped allowlist is correct and #160 is
a harness defect rather than a control defect.

So the decision is not "run the excluded tests or do not". It is: which
assertions can a runner make honestly, what happens to the rest, and where the
cost lands.

## Decision

**1. A second job, `container`, selecting container tests by tag.** It installs
Podman, creates the `claude-net` network, builds the images the selected tests
need, and runs `bats --filter-tags container,!hostfidelity tests/`.

*Revised 2026-10-20: built as a separate workflow,
`.github/workflows/container.yml`, not as a second job in `ci.yml`.* Actions
applies `paths:` to a whole workflow, so a filter on `ci.yml` would also gate
the host-only job, which has to run on every pull request. The two ways to
filter per job were a third-party filter action and a job-level `if:` over a
computed diff. The repository's only action is `actions/checkout` and it pins
bats by commit, which rules out the first. The second makes a skipped job
report green, which is the shape this design exists to remove. The intent of
the decision holds; only the mechanism differs.

**2. A new `hostfidelity` tag on R-6 alone**, meaning: this assertion depends on
the host's cgroup or mandatory-access-control layout and cannot be made
faithfully on a hosted runner. The tag is a claim about the environment, not
about speed, which is why it is not `slow`. R-6 remains operator-verified, and
the SDD says so rather than leaving a reader to infer it from a tag list.

R-7 and R-8 do not get the tag. They already skip with a reason naming the
missing precondition, which is the same information the tag would carry, carried
closer to the assertion. Tagging them as well would duplicate it and overstate
how much of the runtime group a runner cannot reach.

**3. Two guards, in opposite directions.** `ci.yml` already guards its selection
against shrinking (`HOSTONLY_FLOOR`). The container job gets the same floor, and
`hostfidelity` gets a **ceiling of one**. Without it, the cheapest way to make a
failing container test green is to tag it `hostfidelity`, and nothing would
notice. That is the #81 failure shape — a test escaping its gate by moving —
generalised to a tag instead of a file.

A ceiling of one will be wrong eventually, and that is the intent: the second
test that genuinely needs the tag should require a deliberate edit with a reason,
not arrive quietly.

**4. Cost is tied to risk by a path filter, with a nightly backstop.** The
`container` job runs on a pull request only when it touches `base/**`,
`squid/**`, `global-claude/**`, `start.sh`, `build.sh` or `tests/**`, and
unconditionally on a nightly schedule.

*Revised 2026-10-20: the filter also lists `config.sh` and
`.github/workflows/container.yml`.* `config.sh` is listed because both
scripts source it, and its `PROFILES` decides what `build.sh` builds. The
workflow file is listed because a change to the gate has to run the gate. A
`workflow_dispatch` trigger runs the tier on demand against any branch.
Measured, it accepts `--ref` for a branch that is not on `main` once the
workflow is registered. Opening the pull request registers it. Step 7 used
this. A documentation-only PR pays nothing; a
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

**Three runtime assertions still never run in CI**, for two different reasons
that should not be conflated. R-6 is excluded by tag, bounded by the ceiling in
decision 3. R-7 and R-8 are not excluded at all — they are selected, they run,
and they skip because the runner has no SELinux. The second case is honest but it
is not coverage, and a count of passing tests will not show the difference. A
skip count in the published summary is the cheap way to keep that visible, and it
is in the plan below.

**A path filter can be wrong.** Tying cost to the paths a PR touches assumes the
touched paths predict the risk. A change to a test helper under `tests/lib/`
that breaks a container assertion is caught; a change to something unlisted that
breaks one is caught only by the nightly run. The filter is a cost decision, and
it is why decision 4 has a backstop rather than standing alone.

**The cost is about nine minutes, and the builds are not the expensive part.**
135s of builds against 395–485s of tests. The assumption behind `ci.yml`'s
original refusal — that building four images is what would make this
intolerable — turns out to be wrong; the Squid suite's real network requests
dominate. That weakens the case for the path filter in decision 4, which is kept
anyway: nine minutes against the current job's ten seconds is still a change
every contributor pays on every push, and the filter costs one `paths:` block.

**The tier cannot be built until #160 is fixed.** A gate that reports a different
answer on each run is not a gate, and the Squid suite does. This is a hard
dependency, not a caveat, and it is the first step of the plan rather than a note
in it.

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

**Chose:** a `hostfidelity` tag on R-6, with a ceiling.
**Rejected:** run R-6 on the runner too and accept whatever it reports.
**Why the rejected option is attractive:** no new tag, no exclusion list to
justify, and the numbers look better — 32 excluded becomes 0. It is also the
option the measurement *nearly* supported, since `memory` is in the delegated
controller set.
**What breaks if you try it anyway:** R-6 fails on the runner in both spike runs,
so the tier would be permanently red and the standing fix would be to weaken the
assertion. A gate nobody can make green gets deleted, and the assertion that
goes with it is the one Changes 17 and 18 were written about.

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

1. ~~**Spike, nothing committed.**~~ Done, two runs on `ubuntu-latest`. Results
   are recorded on #101 and folded into Context above. It changed decisions 2 and
   3 and produced #159 and #160.
2. **Fix #160**, the Squid suite's per-run variance. Nothing downstream is worth
   building until that suite answers the same way twice — a dependency, not an
   ordering preference.
   *2026-10-20: #160 is closed, but the dependency is not met. See Corrections.*
   *2026-10-21: met by `6922d17`. See Corrections.*
3. **Fix #159**, so R-5 skips rather than fails on a fully-built machine. The
   tier builds every image, so without this the job is red for a correct
   environment.
   *Done, #168.*
4. **Tag `hostfidelity`** on R-6, with the reason stated at the test rather than
   only in this document. Add a `container` tag to the five container suites. No
   workflow change yet; `hostonly` selection is unaffected, so `HOSTONLY_FLOOR`
   stays at 49.
   *Done.*
5. **Add the `container` job** with the path filter, the selection floor, the
   `hostfidelity` ceiling of one, and `::notice::` publication of selected,
   passed, failed **and skipped** counts. The skip count is what keeps R-7 and
   R-8's non-coverage visible rather than hidden inside a pass total.
   *Done, as a separate workflow (decision 1).*
6. **Add the nightly schedule** invoking the same job without the path filter.
   *Done. It first fires once the tier is on `main`.*
7. **Negative-control the tier in CI.** Break one assertion per suite on a
   throwaway branch, confirm the job reports it, revert. Record the results in
   each test file's header, as `tests/test_planning_artifacts.bats` already does
   for the P-checks.
   *Done 2026-10-20, one probe per suite. Results are in each suite's header.
   It found the ungated `start.sh` flags in Corrections.*
8. **Revise the SDD.** `docs/designs/0011-claude-sandbox-testing-module-sdd.md`
   §4's tag axes gain `container` and `hostfidelity`; its header's "deliberate
   trade" paragraph is replaced by what each tier's green now means, including
   that only 135s of it is builds. Bump the version and add a Revision History
   row.
   *Done, v1.4.*
9. **Correct `ci.yml`'s header** to name both jobs and what each one's green does
   not cover.
   *Done.*
10. **Close #101** with the measured numbers, and open a follow-up for routing
    notification of a failed scheduled run, which this design deliberately leaves
    unsolved.
    *Done 2026-10-23. The three runs on `6922d17` took 7m58s–8m14s, 155–162s of
    it builds, and asserted 28 with 3 skipped. No follow-up was opened: the
    operator confirmed that GitHub's own failure email for a scheduled run
    reaches the people who act on it.*
11. **Delete the spike workflow and its branch.** Throwaway by construction; its
    results live in #101 and in this document.
    *After merge, with the `probe/101-*` branches used for step 7 and the
    Squid diagnosis.*
