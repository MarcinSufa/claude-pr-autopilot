#!/usr/bin/env bash
# pr-autopilot — user-only approval write for /pr-autopilot:approve-spec.
#
# Usage (run by the USER in their own terminal, inside the assignment worktree):
#   bash <plugin>/skills/approve-spec/scripts/approve-claim.sh <assignment-id>
#
# Sets subStatus=implementing + approvedAt + approvedBy + approvalContext in
# .claude/assignment-claims/<id>.json and commits it. The confirmation is read from
# /dev/tty, so the agent's Bash tool (no controlling terminal) cannot complete it, and
# hooks/enforce-spec-gate.sh denies agent tool calls that mention this script or change
# the approval fields. This is a guard rail, not cryptography — see the hook header for
# what remains bypassable.
#
# Exit codes: 0 approved | 1 usage/state error | 3 no terminal | 4 confirmation mismatch
set -euo pipefail

ID="${1:-}"
if [ -z "$ID" ]; then
  echo "usage: approve-claim.sh <assignment-id>" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "jq is required (apt install jq / brew install jq)" >&2; exit 1; }

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git worktree" >&2; exit 1; }
CLAIM="$ROOT/.claude/assignment-claims/$ID.json"
[ -f "$CLAIM" ] || { echo "claim file not found: $CLAIM" >&2; exit 1; }

SUB=$(jq -r '.subStatus // "none"' "$CLAIM")
if [ "$SUB" != "spec_review_complete" ]; then
  echo "subStatus is '$SUB'; approval needs 'spec_review_complete' (run /pr-autopilot:review-spec first)." >&2
  exit 1
fi

if ! { exec 3<>/dev/tty; } 2>/dev/null; then
  echo "No terminal available. Run this command yourself in a terminal, not through the agent." >&2
  exit 3
fi

SPEC=$(jq -r '.specFile // "<unknown>"' "$CLAIM")
IT=$(jq -r '.reviewIteration // 0' "$CLAIM")
FINDINGS=$(jq -c --argjson it "$IT" '
  [ (.reviewers // [])[] | select(.iteration == $it and .status == "complete") | .findings // {} ]
  | { p0: (map(.p0 // 0) | add // 0), p1: (map(.p1 // 0) | add // 0), p2: (map(.p2 // 0) | add // 0) }' "$CLAIM")

printf 'Approve spec for assignment %s?\n  spec: %s\n  review iteration: %s, findings: %s\nType the assignment id to approve: ' \
  "$ID" "$SPEC" "$IT" "$FINDINGS" >&3
IFS= read -r ANSWER <&3 || ANSWER=""
exec 3>&-
if [ "$ANSWER" != "$ID" ]; then
  echo "Confirmation did not match; nothing changed." >&2
  exit 4
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
WHO=$(git config user.email 2>/dev/null || true)
[ -n "$WHO" ] || WHO="${USER:-<unknown-user>}"

TMP="$CLAIM.tmp.$$"
jq --arg now "$NOW" --arg who "$WHO" --arg spec "$SPEC" --argjson it "$IT" --argjson f "$FINDINGS" '
  .subStatus = "implementing"
  | .approvedAt = $now
  | .approvedBy = $who
  | .approvalContext = { findings: $f, specFile: $spec, iterationAtApproval: $it }' "$CLAIM" > "$TMP"
mv "$TMP" "$CLAIM"

git -C "$ROOT" add ".claude/assignment-claims/$ID.json"
git -C "$ROOT" commit -q -m "chore(pr-autopilot): approve spec for $ID by $WHO"
echo "Approved $ID by $WHO at $NOW (subStatus=implementing, committed)."
