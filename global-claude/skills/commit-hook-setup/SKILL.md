---
name: commit-hook-setup
description: >
  Install or verify the commit-msg hook in /workspace. Invoke when the
  entrypoint log shows "hook already present" and Co-Authored-By
  enforcement is not yet in place, or when asked to set up or inspect
  commit enforcement.
---

# Commit Hook Setup

## When to invoke
- Entrypoint startup log says "commit-msg hook already present" and you
  need to verify or update it
- First session on a new repository where an existing hook was found
- Operator asks to install, verify, or update the commit-msg hook

## Step 1 — Inspect

```bash
cat /workspace/.git/hooks/commit-msg 2>/dev/null || echo "(no hook present)"
```

## Step 2 — Decide

**No hook present** → proceed to Step 3. Ask the operator to confirm before writing.

**Hook present and contains `Co-Authored-By` check** → compliant. Report and stop.

**Hook present but does not contain the check** → show the existing content to the
operator. Ask them to choose:
  a) Replace with the standard hook (loses existing logic)
  b) Append the Co-Authored-By check to the existing hook
  c) Leave as-is (enforcement gap — note it explicitly)

Never overwrite silently.

## Step 3 — Install standard hook

```bash
cp ~/.claude/hooks/commit-msg /workspace/.git/hooks/commit-msg
chmod +x /workspace/.git/hooks/commit-msg
```

Verify:
```bash
ls -la /workspace/.git/hooks/commit-msg
cat /workspace/.git/hooks/commit-msg
```
