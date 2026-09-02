---
name: commit-hook-setup
description: >
  Install or verify the commit-msg hook in /workspace. Invoke when the
  entrypoint log shows "hook already present" and attribution-trailer
  enforcement is not yet in place or may be stale, or when asked to set up
  or inspect commit enforcement.
---

# Commit Hook Setup

## When to invoke
- Entrypoint startup log says "commit-msg hook already present" and you
  need to verify or update it
- First session on a new repository where an existing hook was found
- Operator asks to install, verify, or update the commit-msg hook

## Step 1 — Find the hooks directory, then inspect

Do not assume `.git/hooks`. `core.hooksPath` redirects hooks elsewhere, and in
a linked worktree or submodule `.git` is a file holding a pointer rather than a
directory. Inspecting the wrong path reports confidently on a file git never
runs.

```bash
HOOKS="$(cd /workspace && git rev-parse --git-path hooks)"
case "$HOOKS" in /*) ;; *) HOOKS="/workspace/$HOOKS" ;; esac
echo "hooks directory: $HOOKS"
cat "$HOOKS/commit-msg" 2>/dev/null || echo "(no hook present)"
```

Report the resolved path whenever it is not `/workspace/.git/hooks` — an
operator who redirected hooks needs to see which file was examined.

## Step 2 — Decide

**No hook present** → proceed to Step 3. Ask the operator to confirm before writing.

**Hook present** → do not judge it by reading it. A hook containing the words
you expect can still accept the messages it exists to reject: the first
version of this hook matched one literal trailer and let every other form of
tool attribution through, and a copy installed before that fix is
indistinguishable by eye. Run Step 2a and decide on what it does.

## Step 2a — Probe the installed hook

```bash
probe() {
    printf 'test: probe\n\n%s\n' "$2" > /tmp/hook-probe
    if bash "$HOOKS/commit-msg" /tmp/hook-probe > /dev/null 2>&1; then
        [ "$1" = accept ] && echo "ok:   accepted — $2" || echo "GAP: accepted — $2"
    else
        [ "$1" = reject ] && echo "ok:   rejected — $2" || echo "OVER-BROAD: rejected — $2"
    fi
}

probe reject 'Co-Authored-By: Someone <a@b.c>'
probe reject 'Generated with SomeTool'
probe accept 'Signed-off-by: Real Person <a@b.c>'
```

**Every line reports `ok:`** → compliant. Report and stop.

**Any line reports `GAP:`** → the installed hook is stale. It predates the
widening of the pattern and misses at least one shape of tool attribution.

**Any line reports `OVER-BROAD:`** → the installed hook rejects a legitimate
git trailer. That is the failure mode that gets a hook disabled, so treat it
as urgent as a gap.

For either, show the operator the hook's content and the probe output, then
ask them to choose:

  a) Replace with the standard hook (loses any custom logic in the existing one)
  b) Merge the standard hook's checks into the existing one
  c) Leave as-is — an enforcement gap; state which probes failed

Never overwrite silently.

## Step 3 — Install standard hook

```bash
cp ~/.claude/hooks/commit-msg "$HOOKS/commit-msg"
chmod +x "$HOOKS/commit-msg"
```

`$HOOKS` is the path resolved in Step 1. Re-resolve it if this step runs in a
new shell.

Verify by re-running Step 2a. `ls -la` and `cat` confirm the file arrived;
only the probes confirm it enforces anything.
