# Software Design Document
## claude-sandbox Testing Module
### bats-core Integration Test Harness (Docker Baseline, Pre-Podman-Migration)

| Field | Value |
|---|---|
| **Document Type** | Software Design Document (SDD) |
| **Status** | Accepted |
| **Version** | 1.1 |
| **Date** | 2026-09-02 |
| **Author** | Fernando |
| **Reviewers** | Security Team |
| **Supersedes** | — (no prior testing SDD exists for claude-sandbox) |
| **Relates to** | `docs/claude_code_security_plan.md`, `docs/squid_proxy_guide.md`, `docs/designs/global-layer-injection.md`, `docs/plans/2026-05-global-layer-injection-v1.md`, `ARCHITECTURE.md`, `docs/designs/sandbox-config-file.md`, `docs/adr/002-planning-artifact-contract.md` |

---

## Revision History

| Version | Date | Author | Description |
|---|---|---|---|
| 1.0 | 2026-07-09 | Fernando | Initial design: bats-core harness, five test groups, `$ENGINE` abstraction, naming/fixture conventions |
| 1.0 | 2026-07-13 | Fernando | Accepted; moved to `docs/designs/` per docs-as-code Case C convention; tracked under issue #11 |
| 1.1 | 2026-09-02 | Fernando | Reconciled with the suite as built: Groups 6–8 added, Group 3 extended to S-6, `hostonly` tag axis documented, §9 traceability extended. Covers the drift that accumulated through R-6…R-8, S-4…S-6 and three test files added without revision entries (issue #51) |

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [System Overview](#2-system-overview)
3. [System Architecture](#3-system-architecture)
4. [Component Design — Test Groups](#4-component-design--test-groups)
5. [Naming and Fixture Conventions](#5-naming-and-fixture-conventions)
6. [Test Execution Model](#6-test-execution-model)
7. [Security Design](#7-security-design)
8. [Error Handling and Test Failure Philosophy](#8-error-handling-and-test-failure-philosophy)
9. [Traceability to Existing Documentation](#9-traceability-to-existing-documentation)
10. [Constraints and Non-Goals](#10-constraints-and-non-goals)
11. [Future Considerations](#11-future-considerations)
12. [Implementation Plan](#12-implementation-plan)
13. [Glossary](#13-glossary)

---

## 1. Introduction

### 1.1 Purpose

This document specifies a `bats-core` integration test harness for `claude-sandbox`. It converts the prose Testing Strategy and Security Validation tables already present in `docs/claude_code_security_plan.md`, and the six manually-executed smoke tests in `docs/plans/2026-05-global-layer-injection-v1.md` Phase 6, into an executable, version-controlled suite. No such harness currently exists — every verification step in the source documents is a manual procedure.

This work is scoped as the first of three pre-merge tasks (testing → Podman migration → config evaluation), serving as the regression baseline for the migration that follows it.

### 1.2 Scope

Covers the design of a test suite for `claude-sandbox` only. The developer-container automation system (`config.toml` / `setup.sh` / `run.sh` / `helpers.py`) has its own equivalent effort, tracked separately, following the same conventions but not specified in this document.

This document does **not** cover:
- Implementation of the Podman migration itself
- The dispatcher/meta-CLI merge design
- CI/CD integration (explicitly out of scope per `docs/claude_code_security_plan.md` §"Scope")
- Container-in-container test execution (evaluated and rejected — see §3.4 and §10)

### 1.3 Intended Audience

| Audience | Purpose |
|---|---|
| Developer (Fernando) | Implementation reference |
| Security Team | Review of the test harness's own attack surface before it is trusted as a regression gate |
| Future maintainers | Understanding of why each test exists and what document it traces back to |

### 1.4 Relationship to Existing Documents

| Document | Relationship |
|---|---|
| `docs/claude_code_security_plan.md` | Source of the Testing Strategy and Security Validation tables this suite implements |
| `docs/squid_proxy_guide.md` | Source of the manual proxy isolation test procedure (Part 3, Step 5) that Test Group 3 automates |
| `docs/designs/global-layer-injection.md` | Source SDD for the global layer injection mechanism Test Group 4 validates |
| `docs/plans/2026-05-global-layer-injection-v1.md` | Source of the six Phase 6 smoke tests that Test Group 4 automates verbatim in intent |
| `ARCHITECTURE.md` | Governs how tools are added to images (Strategy A/B); this document assumes that dependency-management workflow is unchanged |

---

## 2. System Overview

### 2.1 Problem Statement

`claude-sandbox`'s security properties — non-root execution, capability dropping, network allowlisting, readonly global-layer mounts — are currently verified by manually running the commands documented in each guide's "smoke test" or "verification" section. This has two consequences:

1. **No regression detection.** A change to `base/Dockerfile`, `start.sh`, or `squid.conf` that silently weakens a control (as happened historically — see Squid guide Change 2, the inline-comment bug that dropped `--cap-drop=ALL`) is only caught if the operator happens to re-run the relevant manual check.
2. **No safety net for the upcoming engine migration.** Moving from Docker to Podman/WSL2 changes every `docker run` invocation in `start.sh` and every `docker build` invocation in `build.sh`. Without an automated behavioral baseline, "the migration preserved all security properties" is an assertion, not a verified fact.

### 2.2 System Goals

In priority order:

1. **Regression safety for the migration.** Every property the security plan claims must be independently, automatically verifiable before the engine changes.
2. **Engine independence.** Tests assert on outcomes ("network egress to a non-allowlisted domain is refused"), not on implementation details ("the `docker run` command contained `--cap-drop=ALL`"), so the same suite validates both Docker and Podman without rewriting test logic.
3. **Non-interference with real sessions.** Running the suite must never affect a developer's actual sandbox containers, images, or shared network.
4. **Negative-path parity.** Every positive assertion ("X is permitted") has a corresponding negative assertion ("Y is refused"). A suite that only proves the happy path would not have caught the Squid changelog regression.
5. **Traceability.** Every test case maps to a specific line item in an existing document, so coverage gaps against the documented threat model are visible by inspection.

### 2.3 Design Constraints

- **No container-in-container execution.** See §3.4.
- **Host-level execution only**, using the same engine binary (`docker` today, `podman` post-migration) the scripts themselves invoke.
- **No CI/CD dependency.** Per `docs/claude_code_security_plan.md`'s explicit scope exclusion, this suite runs locally, on demand.
- **No modification to `build.sh` / `start.sh` / Dockerfiles** as part of this effort. This is a testing module, not a refactor. Any defect the suite surfaces is documented as a finding, not silently fixed in passing.
- **No real credentials.** Detailed in §7.2.

### 2.4 Assumptions and Dependencies

| Assumption / Dependency | Justification |
|---|---|
| `bats-core` available in the WSL2/host environment | Shell-native, matches the all-bash tooling already used throughout the project; no new language runtime |
| Docker is the engine under test for v1.0 | Migration has not yet occurred; suite is written engine-agnostically per §3.4 to avoid rework |
| `claude-net` Docker network may already exist from real usage | Suite must not assume a clean-slate network; see §5.3 |
| Test execution happens on the same machine where `claude-sandbox` is normally used | No remote or CI execution target in scope |

---

## 3. System Architecture

### 3.1 High-Level Overview

```
tests/
├── test_build.bats                 ← Test Group 1
├── test_runtime_posture.bats       ← Test Group 2
├── test_squid_isolation.bats       ← Test Group 3
├── test_global_layer.bats          ← Test Group 4
├── test_toolchain_smoke.bats       ← Test Group 5
├── test_config.bats                ← Test Group 6
├── test_docs_integrity.bats        ← Test Group 7
├── test_planning_artifacts.bats    ← Test Group 8
├── lib/
│   ├── engine.bash                 ← $ENGINE abstraction, shared helpers
│   └── teardown.bash               ← trap-based cleanup helpers
└── fixtures/
    ├── scratch-project/            ← generic empty project dir
    ├── cpp-minimal/                ← minimal CMakeLists.txt
    └── research-minimal/           ← minimal .tex file
```

Each `.bats` file corresponds to one test group from §4 and runs independently — no file depends on state left behind by another.

### 3.2 Test Groups (Summary)

| Group | File | What it validates | Speed |
|---|---|---|---|
| 1 | `test_build.bats` | Build hierarchy, `HOST_UID` propagation | Fast |
| 2 | `test_runtime_posture.bats` | Non-root, cap-drop, no-new-privileges, image/name validation | Fast |
| 3 | `test_squid_isolation.bats` | Egress allowlist enforcement, access log | Slow |
| 4 | `test_global_layer.bats` | Layer injection, readonly mounts, session isolation | Fast |
| 5 | `test_toolchain_smoke.bats` | Per-profile toolchain availability | Slow |
| 6 | `test_config.bats` | Config-layer precedence, `@name` registry resolution | Fast, host-only |
| 7 | `test_docs_integrity.bats` | Link/skill/ADR/tag conformance, global layer size ceilings | Fast, host-only |
| 8 | `test_planning_artifacts.bats` | ADR 002 planning-artifact contract | Fast, host-only |

The fast/slow split feeds directly into the two-tier execution model in §6.1.

### 3.3 Directory Layout

Lives at `~/.claude-sandbox/tests/`, sibling to `base/`, `crypto/`, `systems/`, `research/`, `squid/`. Version-controlled in the same repository, same as every other component per the project's documentation-first convention.

### 3.4 Engine Abstraction

Every test invokes the container engine through a single indirection point rather than calling `docker` literally:

```bash
# lib/engine.bash
ENGINE="${ENGINE:-docker}"

engine_run()   { "${ENGINE}" run "$@"; }
engine_build() { "${ENGINE}" build "$@"; }
engine_ps()    { "${ENGINE}" ps "$@"; }
```

Test bodies call `engine_run`, `engine_build`, etc. Migrating the suite to validate Podman becomes `ENGINE=podman bats tests/`, not a rewrite. This is the single most consequential design decision in this document for the task that follows it — the alternative (docker literals scattered through ~15 test files) would mean re-deriving the suite rather than reusing it in the migration you're about to do.

**On container-in-container**, resolved in the prior discussion and restated here for the record: none of the eight test groups require the test runner itself to be containerized. Build/run/posture/toolchain checks are host-level subprocess calls to the engine binary — identical in kind to what `setup.sh`'s existing smoke tests already do. Squid isolation tests use **sibling** containers on a shared network (test runner on host, sandbox container and proxy container both as normal peers), not nested engines. True DinD/DooD is deferred — see §10.

---

## 4. Component Design — Test Groups

### 4.1 Group 1 — Build Hierarchy

| ID | Test | Assertion |
|---|---|---|
| B-1 | Dependency ordering | `./build.sh crypto` results in both `claude-base` and `claude-crypto` present; base predates crypto in build log ordering |
| B-2 | `HOST_UID` propagation | Build with `--build-arg HOST_UID=1234`; `engine_run claude-base id -u` returns `1234`, not the default `1000` — direct regression test for the documented ARG-non-inheritance failure mode |
| B-3 | Isolated build success | Each of `base/crypto/systems/research` Dockerfiles builds cleanly on its own, without relying on layer cache from a prior full build |
| B-4 | No `latest` tag reliance | Confirms images are referenced by explicit tag in `build.sh`, not implicit `latest` |

### 4.2 Group 2 — Runtime Security Posture

| ID | Test | Assertion |
|---|---|---|
| R-1 | Non-root execution | `whoami` inside any started image returns `claude-agent`, never `root` |
| R-2 | Capability drop present | `engine inspect` on a running test container shows `CapDrop: [ALL]` — regression test for Squid changelog Change 2 |
| R-3 | No-new-privileges present | `engine inspect` shows `no-new-privileges` security option active |
| R-4 | Unknown image rejected | `start.sh <project> nonexistent-image` fails before any container starts, with an actionable error |
| R-5 | Missing image rejected | `start.sh` against a valid image tag that hasn't been built fails with the documented `./build.sh <tag>` guidance, not a silent registry pull |
| R-6 | Memory limit actually enforced | `--memory=100m` container allocating 500MB is killed (`exit 137`) with `OOMKilled: true` — added post-migration after `podman-migration.md` §6.2-D/Change 17 found rootless Podman under WSL2 can accept `--memory` without enforcing it when cgroups v2 `memory` delegation is absent |
| R-7 | `/workspace` bind mount genuinely readable/writable under SELinux | A host-side file written before the container starts is readable inside it, and a file written inside the container lands on the host — added after `podman-migration.md` §6.2-T/Change 19 found a bind mount with correct POSIX bits still `EACCES` on an SELinux-enforcing host because Podman never relabeled it. Skips on non-SELinux-enforcing hosts, where the bug isn't observable |
| R-8 | `relabel=shared` (not `private`) works across concurrent sessions | Two containers concurrently mounting the same host path can both read it — distinguishes the Change 19 `shared` choice from `private`/`:Z`, which would pass a single-container check but break a second concurrent mount. Podman-only, skips on non-SELinux-enforcing hosts |

### 4.3 Group 3 — Squid Egress Enforcement

| ID | Test | Assertion |
|---|---|---|
| S-1 | Allowed domain succeeds | Request to an allowlisted domain from a sibling container routed through the test proxy returns `TCP_TUNNEL/200` in the access log |
| S-2 | Blocked domain refused | Request to a non-allowlisted domain returns `TCP_DENIED/403` or connection refusal — the higher-value direction; a misconfiguration that accidentally allows everything is otherwise silent |
| S-3 | Access log completeness | Every attempted connection in this group produces exactly one parseable log line (Repudiation control, directly testable) — `setup_file()` issues all requests once into a shared log, so the count covers S-1 through S-6, not only the first two |
| S-4 | `docs.anthropic.com` reachable | Reference-tier allowlist addition from issue #32 resolves and tunnels |
| S-5 | `code.claude.com` reachable | Reference-tier allowlist addition from issue #32 resolves and tunnels |
| S-6 | `mintcdn.com` reachable | The `dstdom_regex` CDN exception from issue #32, curled at the bare apex — Mintlify's CSP documentation lists plain `mintcdn.com` as required, so it is a directly-addressable host and not merely a wildcard zone |

Mirrors `docs/squid_proxy_guide.md` Part 3 Step 5 exactly, wrapped as assertions instead of manual `docker logs` inspection.

### 4.4 Group 4 — Global Layer Injection

G-1 through G-6 reproduce the six Phase 6 tests from `docs/plans/2026-05-global-layer-injection-v1.md`, restated as assertions rather than manual procedures. G-7 through G-9 were added later, for the entrypoint's commit-msg hook drift check (issue #54), and are the only tests in the suite that assert on entrypoint stdout — elsewhere those lines are filtered out as noise. G-10 was added last (issue #71) and is the only test that asserts on the layer as a whole rather than on a named file within it.

| ID | Test | Assertion |
|---|---|---|
| G-1 | Base layer applied | New `base`-image session: `~/.claude/CLAUDE.md` inside the container matches the host `global-claude/CLAUDE.md` source |
| G-2 | Overlay applied for domain images | `crypto`-image session: both `CLAUDE.md` and the crypto overlay skill file are present under `~/.claude/` |
| G-3 | Readonly mount enforcement | `touch` inside `/run/claude-global/` fails with a read-only filesystem error |
| G-4 | Working copy isolation from host | A file written to `~/.claude/memory/` inside a session does not appear in the host `global-claude/` source directory after the container exits |
| G-5 | Session-to-session isolation | A file written to `~/.claude/` in one running container is not visible from a second, concurrently running container |
| G-6 | Application-layer deny rule active | An attempted write to `/run/claude-global/` from inside a Claude Code session is blocked by `permissions.deny`, independent of the OS-level readonly mount (proves the two layers are independently effective, not just one carrying the other) |
| G-7 | Hook drift reported | A `/workspace` whose `.git/hooks/commit-msg` differs from the shipped copy produces the entrypoint's WARNING line, the container still starts, and the drifted hook is left unmodified — the check reports, it does not resolve |
| G-8 | Matching hook reported current | An identical installed hook produces the `OK` line and no warning. Pairs with G-7: a one-directional check cannot distinguish a working comparison from one that never fires |
| G-9 | Hook check follows `core.hooksPath` | A repository redirecting hooks to `.githooks/` has *that* hook examined and named in the warning, and nothing is written to the `.git/hooks/` directory git does not consult |
| G-10 | Whole layer arrives intact | For every file under `global-claude/`, a file with identical content exists at the corresponding path under `~/.claude/`, and the number compared matches the number the host holds. One-directional: files the entrypoint adds that the source lacks do not fail it |

### 4.5 Group 5 — Profile-Specific Toolchain Smoke Tests

| ID | Test | Assertion |
|---|---|---|
| T-1 | crypto | `softhsm2-util --show-slots` and `p11-kit list-modules` exit 0 |
| T-2 | systems | Minimal fixture `CMakeLists.txt` (from `fixtures/cpp-minimal/`) configures, builds, and links against the pre-built GTest without additional `find_package` configuration |
| T-3 | research | Minimal fixture `.tex` (from `fixtures/research-minimal/`) compiles successfully via `latexmk` |

### 4.6 Group 6 — Layered Config

Covers `config.sh`'s own correctness and the four-layer precedence chain from
`docs/designs/sandbox-config-file.md` (hardcoded default < `config.sh` <
`config.local.sh` < environment variable), not container runtime behaviour.
C-7 onward exercise `@name` registry resolution by running a copy of the real
`start.sh` with `ENGINE=true` — a no-op stand-in that satisfies every engine
check without contacting a daemon, so the resolution path is tested end to end
with no engine present. No test in this group reads or writes an operator's
real `config.local.sh`.

| ID | Test | Assertion |
|---|---|---|
| C-1 | Env var beats `config.sh` | A variable set in the environment overrides the value `config.sh` assigns to the same name |
| C-2 | `config.sh` beats the built-in default | With no env var set, `config.sh`'s value replaces the hardcoded layer-1 default |
| C-3 | `PROFILES` matches the tree | Every profile `config.sh` declares has a corresponding profile directory, and vice versa |
| C-4 | `PROFILE_BASE` references only declared profiles | No entry names a profile absent from `PROFILES` |
| C-5 | Unknown build target refused | `build.sh` with a target outside `PROFILES` exits non-zero without touching an engine — the refusal is a config-layer decision, so it must not depend on a daemon |
| C-6 | Both entry points source `config.sh` | `build.sh` and `start.sh` read the shared file rather than each carrying a re-copied literal list |
| C-7 | `@name` resolves | A registered name yields both its path and its registry profile |
| C-8 | Explicit profile wins | A second argument overrides the profile the registry supplies |
| C-9 | Unknown `@name` refused | Exits non-zero and never reaches the engine |
| C-10 | Path without profile is reported | A registry entry missing its profile produces a diagnostic, not a `set -u` crash |
| C-11 | Bare name is a path | A name matching a registry entry but written without `@` is still treated as a filesystem path |
| C-12 | `config.local.sh` name resolves | A name added only in the operator's uncommitted layer resolves correctly |
| C-13 | Committed names are not overridable | `config.local.sh` redefining a name that `config.sh` already declares is reverted and warned about, not silently honoured |

### 4.7 Group 7 — Documentation Integrity

Moves doc-discipline rules off rung 2 of the enforcement ladder. Every
assertion here exists because a real instance of the failure was already in
the tree, or because the failure is invisible until someone clones fresh.
The group reads tracked files and nothing else, which is what makes it
runnable on a CI runner with no container tooling — see §6.2.

| ID | Test | Assertion |
|---|---|---|
| D-1 | Relative links resolve | Every markdown link in a tracked `.md` points at a path that exists, relative to the linking file. Code fences and inline code spans are excluded, and anchor fragments are not checked |
| D-2 | Named skills are committed | Every backtick-quoted kebab-case token anywhere under `global-claude/` has a matching `skills/<name>/SKILL.md` — the broad form deliberately, since skills cite each other as "Pairs with \`name\`" rather than "\`name\` skill" |
| D-3 | ADRs conform | Every file in `docs/adr/` carries an `# ADR NNN — Title` heading and a `Status` of `Proposed`, `Accepted`, `Deprecated`, or `Supersedes ADR NNN` |
| D-4 | Skill directories have manifests | Every directory under `global-claude/skills/` contains a `SKILL.md` |
| D-5 | Every test is taggable | Every `@test` has a `# bats test_tags=` comment on the preceding non-blank line — the regression guard for the defect that left eight tests invisible to `--filter-tags`, including S-1 and R-1 |
| D-6 | `CLAUDE.md` within ceiling | At most 200 lines, the figure `docs/designs/global-layer-injection.md` §5.2 already treats as acceptable context cost |
| D-7 | Global layer within ceiling | At most 3000 lines across every file under `global-claude/`, counted in lines because byte measurements of the same directory differ by 2.4× depending on method |

### 4.8 Group 8 — Planning Artifact Contract

The enforcement `docs/adr/002-planning-artifact-contract.md` decision 7 names
by path. That ADR's rules 1–6 are prose; this group is what stops them from
holding only while convenient.

Coverage is partly latent by design. No planning artifact has been written
yet, so P-2 and P-4 have nothing to iterate over and pass trivially today;
they bind automatically the first time a skill writes to `docs/planning/`,
with no edit to the test file. P-1, P-3, P-5 and P-6 assert against the four
committed templates and carry weight now.

| ID | Test | Assertion |
|---|---|---|
| P-1 | Templates are self-describing | Every template declares its artifact path, its owning skill, and its section ceilings in frontmatter |
| P-2 | Artifacts carry a status | Every artifact's frontmatter `status` is one of the values ADR 002 decision 3 allows |
| P-3 | Artifacts are indexed | Every artifact path has a row in `docs/planning/README.md` |
| P-4 | Ceilings hold | No artifact section exceeds the line ceiling its template declares |
| P-5 | Ownership is unambiguous | No artifact path is claimed by more than one template — the check ADR 002 decision 2's table goes stale without |
| P-6 | Ceilings name real sections | Every declared `ceiling-<section>` key corresponds to a section the template actually contains |

---

## 5. Naming and Fixture Conventions

These conventions are binding for every test group above; a test that doesn't follow them is a defect in the test, not an acceptable variation.

| Concern | Convention | Rationale |
|---|---|---|
| Container names | `test-claude-<component>-<pid>` (e.g. `test-claude-base-4821`) | `$$`-suffix pattern already used by `start.sh` / Squid guide; `test-` prefix makes teardown scoping unambiguous in `docker ps` |
| Build-test images | Isolated `:test` tags (`claude-base:test`) | Never overwrites a tag a real session might be using concurrently |
| Build-test image lifecycle | **Removed after every run** — no caching across runs (Decision, 2026-07-09) | Prioritizes correctness over speed at this stage: a cached stale test image could mask a real Dockerfile regression, which directly undermines Goal 1 (regression safety for the migration). Caching is deferred to future work (§11) once the suite is trusted and speed becomes the binding constraint. |
| Runtime/behavior-test images | The real production tags (`claude-base`, `claude-crypto`, etc.), read-only usage — never mutated by a test | Testing `start.sh` against a synthetic image doesn't validate what a developer actually runs |
| Network | Reuse `claude-net` if present; create if absent; **never delete it in teardown** | Shared resource — deleting it under a concurrent real session is a self-inflicted DoS |
| Fixture projects | `tests/fixtures/<scenario>/`, committed to the repo | Synthetic, non-sensitive, reviewable in a diff |
| Fixture content | **Genuinely minimal** — an empty directory for generic scenarios, a trivial `CMakeLists.txt` for T-2, a trivial `.tex` for T-3 (Decision, 2026-07-09) | Fastest path to a working suite; validates the toolchain is *present and functional*, not that it handles realistic project complexity. Realistic fixtures deferred to future work (§11) once profile-specific edge cases become a concern. |
| Cleanup | `trap` per test, scoped strictly to the `test-` prefix | A blanket `docker ps -aq \| xargs rm` in teardown is the fastest way to remove a container the operator didn't intend to touch |

---

## 6. Test Execution Model

### 6.1 Fast Tier vs. Slow Tier

| Tier | Groups | Trigger |
|---|---|---|
| Fast | 1, 2, 4, 6, 7, 8 | Every change to `base/`, `start.sh`, `build.sh`, `global-claude/`, or `docs/` |
| Slow | 3, 5 | Before merge / before the Podman migration cutover |

Groups 6, 7 and 8 are additionally host-only: they need no engine and no image
at all, which is a stronger property than being fast. See §6.2.

Mirrors the Component Tests / Integration Tests split already present in `docs/claude_code_security_plan.md`'s own Testing Strategy section. Groups 3 and 5 are slow because they require either multi-container network setup (Squid) or full toolchain installation (LaTeX, CMake+GTest compilation) — not something you want gating every quick iteration.

### 6.2 bats Tagging

Fast/slow separation is implemented via bats' native `# bats test_tags=` annotation, so both tiers live in the same files per test group rather than a parallel directory split — avoids duplicating the fixture and helper wiring across two trees.

There are two independent axes, not one, and conflating them is what a reader
of this section would otherwise do:

| Tag | Means | Groups |
|---|---|---|
| `fast` | Completes in seconds | 1, 2, 4, 6, 7, 8 |
| `slow` | Builds images or starts containers | 3, 5 |
| `hostonly` | Needs no engine daemon and no image | 6, 7, 8 |

`fast` does not imply `hostonly`. Group 4 is fast and still requires a built
`claude-base`, because its `setup()` gates on one. **CI filters on `hostonly`,
not on `fast`** — so groups 1 through 5 do not run in CI at all, and the
`bats tests/` pre-merge gate is the only thing that exercises them. A test
added to a group whose file gates on an engine cannot be made CI-visible by
tagging it `hostonly`; it would be selected and then fail in `setup()`.

### 6.3 Local Execution

```bash
# Fast tier only (default local iteration loop)
bats --filter-tags fast tests/

# Full suite (pre-merge / pre-migration gate)
bats tests/

# Against Podman, once migrated
ENGINE=podman bats tests/
```

---

## 7. Security Design

The test harness is itself new infrastructure with host-level engine access. It gets its own — deliberately small — threat analysis, consistent with the project's standing principle that every component is reviewed proportional to its actual risk surface, not skipped because it's "just tests."

### 7.1 Threat Model for the Harness

The harness runs with the same privileges as any other script the operator invokes manually — no new privilege boundary is introduced (§3.4). The primary risk is not external compromise; it's the harness itself misbehaving against real, concurrent sandbox state (deleting a live container, tearing down the shared network, leaking a credential into a log).

### 7.2 Credential Handling in Tests

- **No test ever touches `ANTHROPIC_API_KEY`.** Nothing in this suite needs to authenticate to the real Anthropic API. If a future test appears to need it, that's a signal the test is validating the wrong thing.
- **`GH_TOKEN` injection tests use a throwaway dummy value only** (e.g. `test-token-do-not-use`), never a real token.
- Any test asserting token-handling behavior (e.g., "token is forwarded but never logged") captures stdout and asserts the dummy value's *absence* from it — a direct regression test for the "never logged" claim in the automation SDD's credential handling section.

### 7.3 Negative-Path Assertions as First-Class

Per Goal 4, every test group includes at least one refusal/rejection case (R-4, R-5, S-2, G-3, G-6, C-5, C-9, C-13, and the whole of Groups 7 and 8, which assert only on violations) rather than only proving the permitted path. This is the property that would have caught the Squid changelog's silent flag-drop regression had it existed at the time.

### 7.4 STRIDE Mapping — New Surfaces Introduced by the Harness

| Threat | Risk | Mitigation |
|---|---|---|
| **Tampering (T)** | A test's teardown accidentally removes a real, non-test container or the shared network | `test-` prefix scoping (§5) enforced in every trap; `claude-net` explicitly exempted from deletion |
| **Information Disclosure (I)** | A dummy credential or fixture leaks something sensitive via captured test output | No real credentials ever enter the suite (§7.2); fixtures are minimal, synthetic, and committed in the clear |
| **Repudiation (R)** | A test failure isn't traceable to what it validated | Every test ID (B-*, R-*, S-*, G-*, T-*, C-*, D-*, P-*) maps to a specific line in this document and, transitively, to a specific claim in the source SDDs (§9) |
| **Denial of Service (D)** | A stuck or crashed test leaves containers/images accumulating on the dev machine | `trap`-based cleanup (§5) on every test, not just on clean exit |
| **Elevation of Privilege (E)** | N/A — harness introduces no new privilege boundary (§7.1) | — |
| **Spoofing (S)** | N/A — no new identity or authentication surface | — |

### 7.5 Explicit Non-Goals of This Security Design

- The harness does not attempt to validate the Docker/Podman engine itself, the kernel, or host-level EDR/DLP visibility — those are out of scope per the parent security plan's own Non-Goals section.
- The harness does not run in CI and therefore has no CI-specific credential or supply-chain surface to analyze at this stage.

---

## 8. Error Handling and Test Failure Philosophy

Consistent with the fail-fast philosophy already established in `setup.sh` / `run.sh` (`set -euo pipefail`, no silent failures): a test that cannot complete its setup (fixture missing, engine unreachable, network absent and uncreatable) fails loudly and immediately, rather than being skipped silently. A skipped security test is indistinguishable from a passing one to anyone scanning results quickly — that ambiguity is unacceptable for this suite specifically, since its entire purpose is to be trusted as a migration gate.

| Failure category | Example | Response |
|---|---|---|
| Setup failure | Fixture directory missing | Test errors (not skips), names the missing path |
| Engine unreachable | Docker daemon not running | Whole suite fails fast with an actionable message before any individual test runs |
| Teardown failure | `engine rm` fails on a test container | Logged as a warning, does not mask the test's own pass/fail result, but is surfaced in suite summary output for manual cleanup |
| Assertion failure | Expected `TCP_DENIED/403`, got `TCP_TUNNEL/200` | Standard bats failure — the point of the suite |

---

## 9. Traceability to Existing Documentation

| Source document | Section | Test IDs |
|---|---|---|
| `docs/claude_code_security_plan.md` | §5, "Complete STRIDE Coverage Map" | R-1, R-2, R-3 |
| `docs/claude_code_security_plan.md` | Quick Reference Card, "What is protected" list | B-1 through T-3 (full suite) |
| `docs/squid_proxy_guide.md` | Part 3, Step 5 | S-1, S-2, S-3 |
| `docs/squid_proxy_guide.md` | Changelog, Change 2 | R-2, R-3 (direct regression coverage) |
| `docs/designs/global-layer-injection.md` | §5, STRIDE analysis of new surfaces | G-1 through G-6 |
| `docs/plans/2026-05-global-layer-injection-v1.md` | Phase 6, Tests 1–6 | G-1 through G-6 |
| `docs/claude_code_security_plan.md` | Changelog, Change 7 (UID matching) | B-2 |
| `docs/claude_code_security_plan.md` | Changelog, Change 17 (cgroups v2 delegation) | R-6 |
| `docs/designs/podman-migration.md` | §6.2, STRIDE analysis (Denial of Service) | R-6 |
| `docs/claude_code_security_plan.md` | Changelog, Change 19 (SELinux mount relabeling) | R-7, R-8 |
| `docs/designs/podman-migration.md` | §6.2, STRIDE analysis (Tampering, follow-up finding) | R-7, R-8 |
| `docs/designs/sandbox-config-file.md` | Layered precedence model and `@name` registry | C-1 through C-13 |
| `docs/adr/002-planning-artifact-contract.md` | Decision 7, "enforced by a test, not by a reviewer" | P-1 through P-6 |
| `docs/adr/003-where-a-behavioural-rule-goes.md` | Decision 4, no restatement; the placement ladder | D-2, D-6, D-7 |
| `docs/designs/global-layer-injection.md` | §5.2, Denial of Service — "Global layer size discipline" | D-6, D-7 |
| `docs/designs/docs-as-code-workflow.md` | §3 Case D, ADR format and Status values | D-3 |

This table is the single place to check for coverage gaps: any claim in the source documents without a corresponding test ID here is undocumented risk, not tested risk.

---

## 10. Constraints and Non-Goals

| Non-Goal | Rationale |
|---|---|
| Container-in-container test execution (DinD/DooD) | Evaluated in design discussion; not needed by any test group (§3.4). DinD would require privileges exceeding what's being validated; DooD hands the test container control over the entire host engine — both disproportionate to a single-user local workstation. Revisit only if CI integration is ever adopted. |
| CI/CD integration | Explicitly out of scope per the parent security plan |
| Modifying `build.sh` / `start.sh` / Dockerfiles as part of this effort | This is a testing module, not a refactor; defects found are documented, not silently patched |
| Testing the developer-container automation system | Tracked as a separate, parallel effort under the same conventions |
| Podman-specific test logic | The `$ENGINE` abstraction (§3.4) is designed precisely so this isn't needed |

---

## 11. Future Considerations

Deferred by explicit decision, not oversight:

- **Cached build-test images.** Once the suite is trusted and running time becomes the binding constraint, revisit removing images after every run (§5) in favor of a cache with explicit invalidation.
- **Richer fixtures.** Minimal fixtures (§5) validate toolchain presence, not realistic project complexity. A future pass could add fixtures mirroring actual CMake project structure or a multi-file LaTeX document to catch profile-specific edge cases the trivial case wouldn't.
- **CI integration**, if the project's scope ever expands to include it — would reopen the container-in-container question deferred in §10.
- **Podman-target hardening pass**, once the migration lands: revisit whether Podman's rootless model introduces test scenarios with no Docker equivalent (e.g., subuid/subgid range checks).

---

## 12. Implementation Plan

Each step maps to a single commit, consistent with project convention.

1. `lib/engine.bash` + `lib/teardown.bash` — the `$ENGINE` abstraction and shared trap helpers, with no tests yet (foundation commit).
2. `fixtures/scratch-project/`, `fixtures/cpp-minimal/`, `fixtures/research-minimal/` — minimal fixture content per §5.
3. `test_build.bats` (Group 1, B-1–B-4).
4. `test_runtime_posture.bats` (Group 2, R-1–R-5).
5. `test_global_layer.bats` (Group 4, G-1–G-6) — ordered before Group 3/5 since it's fast-tier and highest-value given the injection design's recency.
6. `test_squid_isolation.bats` (Group 3, S-1–S-3) — slow tier.
7. `test_toolchain_smoke.bats` (Group 5, T-1–T-3) — slow tier.
8. `BUILDING.md`/`ARCHITECTURE.md` update documenting `bats tests/` and `bats --filter-tags fast tests/` as standard commands.

---

## 13. Glossary

| Term | Definition |
|---|---|
| `bats-core` | Bash Automated Testing System; shell-native test framework used here for engine-invocation-level integration tests |
| `$ENGINE` | Shared indirection variable (`docker` or `podman`) through which all test-harness engine calls are routed |
| Fast tier | Test groups without multi-container networking or slow toolchain builds; run on every change |
| Slow tier | Test groups requiring Squid sibling containers or full toolchain compilation; run pre-merge |
| Sibling containers | Two or more containers on a shared network, each a peer — as opposed to nested (container-in-container) execution |
| Negative-path assertion | A test proving that a forbidden action is refused, as opposed to proving a permitted action succeeds |
| DinD / DooD | Docker-in-Docker / Docker-outside-of-Docker — two patterns for running container operations from within a containerized test runner; both evaluated and rejected for this suite (§10) |

---

*Status: Accepted. Approved 2026-07-13; implementation tracked in issue #11.*
