#!/usr/bin/env bash
# pr-autopilot v0.5 — PreToolUse hard gate: block Write/Edit outside specs/ until
# /pr-autopilot:approve-spec has flipped the claim file to `implementing` (or later).
#
# Receives Claude Code tool-call JSON on stdin. Exit non-zero ABORTS the tool call.
#
# Policy (per spec §"Hook policy summary"):
#   - Honors ~/.pr-autopilot/paused sentinel (skips gate if paused).
#   - Honors ~/.pr-autopilot/allowed-repos allowlist (case-insensitive match).
#   - Gate-lifted states: implementing, pr_opened, pr_review_requested, pr_revising, merged.
#   - Pre-approval states: spec_drafting, spec_review_requested, spec_revising, spec_review_complete.
#   - Allowed paths during pre-approval: specs/* and .claude/assignment-claims/*.
#   - Integrity check: a claim file claiming a gate-lifted subStatus but with approvedAt=null
#     is treated as TAMPERED and blocks all writes.

set -euo pipefail

# 1. Honor pause sentinel.
[ -f "$HOME/.pr-autopilot/paused" ] && exit 0

# 2. Honor allowlist (P1-5 v2.1 fix: case-insensitive grep, consistent with /allow).
REPO=$(git -C "$(pwd)" remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+/[^/.]+)(\.git)?$|\1|' || echo "")
ALLOWLIST="$HOME/.pr-autopilot/allowed-repos"
if [ -f "$ALLOWLIST" ] && [ -n "$REPO" ] && ! grep -qiFx "$REPO" "$ALLOWLIST" 2>/dev/null; then
  exit 0  # not opted in, no gate
fi

# 3. Parse tool call from stdin.
INPUT=$(cat)
TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
[ -z "$TARGET" ] && exit 0  # not a path-targeting tool call

# 4. Find current claim file (walk up CWD looking for .claude/assignment-claims/*.json).
CLAIM=""
DIR="$(pwd)"
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  CANDIDATE=$(find "$DIR/.claude/assignment-claims" -maxdepth 1 -name "*.json" 2>/dev/null | head -1)
  if [ -n "$CANDIDATE" ]; then CLAIM="$CANDIDATE"; break; fi
  if [ "$DIR" = "/" ]; then break; fi
  DIR=$(dirname "$DIR")
done

# 5. No claim found → outside the pre-PR lifecycle, allow.
[ -z "$CLAIM" ] && exit 0

# 6. Read claim file state.
SUB_STATUS=$(jq -r '.subStatus // "none"' "$CLAIM" 2>/dev/null || echo "none")
APPROVED_AT=$(jq -r '.approvedAt // "null"' "$CLAIM" 2>/dev/null || echo "null")

# 7. Gate logic.
case "$SUB_STATUS" in
  implementing|pr_opened|pr_review_requested|pr_revising|merged)
    # Gate is lifted — but only if approvedAt is set (P0-2 v2.1 integrity check).
    if [ "$APPROVED_AT" = "null" ] || [ -z "$APPROVED_AT" ]; then
      echo "[pr-autopilot/spec-gate] BLOCKED: subStatus=$SUB_STATUS but approvedAt is null." >&2
      echo "  Claim file appears tampered. /pr-autopilot:approve-spec must be invoked via AskUserQuestion to set approvedAt + approvedBy." >&2
      echo "  If this is intentional (e.g. recovering from a corrupted state), use /pr-autopilot:unassign first." >&2
      exit 1
    fi
    exit 0
    ;;
esac

# 8. Pre-approval states: allow only edits to specs/ + claim file itself.
case "$TARGET" in
  */specs/*|*/.claude/assignment-claims/*)
    exit 0
    ;;
  *)
    echo "[pr-autopilot/spec-gate] BLOCKED: spec not approved (subStatus=$SUB_STATUS)." >&2
    echo "  Allowed paths during pre-approval: specs/*, .claude/assignment-claims/*" >&2
    echo "  Workflow:" >&2
    echo "    1. Finish writing the spec at specs/<date>-<id>.md" >&2
    echo "    2. Run /pr-autopilot:review-spec" >&2
    echo "    3. After 0 P0 findings, ask user to run /pr-autopilot:approve-spec" >&2
    echo "    4. Sub-status flips to 'implementing' and this gate lifts" >&2
    exit 1
    ;;
esac
