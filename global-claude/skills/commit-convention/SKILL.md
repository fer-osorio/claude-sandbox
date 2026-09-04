---
name: commit-convention
description: >
  Apply when writing any git commit message. Formats commit messages
  following the commit convention: type, optional scope, subject,
  optional body, and optional footer. Triggers on any commit, amend, or
  rebase operation.
---

# Commit Convention

## Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer(s)]
```

## Types

| Type       | When to use                                              |
|------------|----------------------------------------------------------|
| `feat`     | A new feature                                            |
| `fix`      | A bug fix                                                |
| `docs`     | Documentation changes only                               |
| `style`    | Formatting, whitespace — no logic change                 |
| `refactor` | Code change that is neither a fix nor a feature          |
| `perf`     | Performance improvement                                   |
| `test`     | Adding or correcting tests                               |
| `build`    | Build system or dependency changes                        |
| `ci`       | CI configuration changes                                  |
| `chore`    | Maintenance tasks not touching src or tests              |
| `revert`   | Reverts a previous commit                                |

## Rules

**Subject**
- Imperative, present tense: "add" not "added", "fix" not "fixed"
- No capital first letter
- No period at the end
- 72 characters max

**Scope** (optional)
- Noun describing the affected module in parentheses: `feat(auth): ...`

**Body** (optional, and often the right choice is none)
- Separate from subject with a blank line
- Explain *what* and *why*, not *how*
- Only the *why* that is missing elsewhere. Test each sentence against
  the diff and against any document this commit adds: if it is already
  there, cut it. A commit whose diff is explanatory prose — docs, a
  design section, a long header comment — usually needs no body at all.
- Length tracks how much of the *why* lives outside the change, not how
  large the change is. A one-line fix with a non-obvious cause earns more
  body than a large, self-describing documentation commit.

**Footer** (optional)
- Breaking changes: `BREAKING CHANGE: <description>`
- Issue references: `Closes #123`

## Examples

```
feat(aes): add CTR mode support

fix(file-handlers): handle empty file edge case

docs(readme): update build instructions

refactor(cipher): extract padding logic into separate method

feat(hsm): integrate PKCS#11 key derivation

BREAKING CHANGE: KeyHandle no longer accepts raw byte arrays
```

Body earned — the cause is nowhere in the diff:

```
fix(entrypoint): resolve the hooks directory instead of assuming it

With core.hooksPath set, the old path installed a hook git never runs
and reported success.
```

Body not earned — the diff already says it:

```
docs(seeding): record why the feature is parked

(the added section is titled "Why this is parked" and says why)
```
