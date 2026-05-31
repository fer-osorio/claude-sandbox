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

**Body** (optional)
- Separate from subject with a blank line
- Explain *what* and *why*, not *how*

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
