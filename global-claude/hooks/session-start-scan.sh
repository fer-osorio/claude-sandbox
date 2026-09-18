#!/usr/bin/env bash
# session-start-scan.sh — installed by claude-sandbox global layer
#
# Runs on SessionStart, matcher "startup" only (~/.claude/settings.json), so
# a resumed or compacted session is not re-scanned.
#
# Read-only existence check: does the mounted project have a user guide
# under one of a few conventional names? This script does not decide
# whether a guide is *warranted* — only whether one is *present*. That
# judgment belongs to the user-guide-check skill, which this script's
# finding is meant to trigger. Deliberately silent when a guide is found:
# its stdout becomes session context on every session, and "OK, nothing to
# report" repeated every session is exactly the noise problem #47 already
# ruled out for the config.local.sh half of this check.
#
# Never executes or evaluates anything found under the mounted project —
# this runs unconditionally, unprompted, against content this script has
# no reason to trust.

set -u

PROJECT_DIR="/workspace"

CANDIDATES=(
    "docs/user_guide.md"
    "docs/USER_GUIDE.md"
    "USER_GUIDE.md"
    "GUIDE.md"
)

for rel in "${CANDIDATES[@]}"; do
    if [ -f "$PROJECT_DIR/$rel" ]; then
        exit 0
    fi
done

echo "[session-start-scan] No user guide found under $PROJECT_DIR (checked: ${CANDIDATES[*]})."
echo "[session-start-scan] Not necessarily a defect. If this project's structure, audience, and existing docs suggest a task-oriented user guide is warranted, apply the user-guide-check skill's judgment before offering to seed one from ~/.claude/templates/user-guide.md. Offer at most once this session; take no for an answer."
exit 0
