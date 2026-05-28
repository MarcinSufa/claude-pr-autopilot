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

# 2. Honor allowlist (P1-5 v2.1 fix: case-insensitive match, consistent with /allow).
# Uses awk because `grep -qiFx` core-dumps on some Git Bash builds when matching
# UTF-8 lines — observed by hooks/tests/test-spec-gate.sh T1/T5/T9.
REPO=$(git -C "$(pwd)" remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+/[^/.]+)(\.git)?$|\1|' || echo "")
ALLOWLIST="$HOME/.pr-autopilot/allowed-repos"
if [ -f "$ALLOWLIST" ] && [ -n "$REPO" ]; then
  ALLOW_MATCH=$(awk -v r="$REPO" 'tolower($0) == tolower(r) {print "1"; exit}' "$ALLOWLIST" 2>/dev/null)
  if [ "$ALLOW_MATCH" != "1" ]; then
    exit 0  # not opted in, no gate
  fi
fi

# 3. Parse tool call from stdin.
INPUT=$(cat)
TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
[ -z "$TARGET" ] && exit 0  # not a path-targeting tool call

# Normalise Windows paths so the `case` match below works regardless of OS
# (Claude Code on Windows may pass `C:\repo\specs\foo.md`). P1-5 from v0.5 PR review.
TARGET=$(printf '%s' "$TARGET" | tr '\\' '/')

# 4. Find current claim file. Claim files live at <repo-root>/.claude/assignment-claims/
# by convention (spec §"Atomic claim — git as primitive"); no need to walk up the
# filesystem. This avoids two failure modes uncovered by hooks/tests/test-spec-gate.sh
# T10: (a) reading a sibling project's claim file, (b) string-mismatch between
# `pwd` and `git rev-parse --show-toplevel` on Windows (UNIX `/tmp/...` vs `C:/Users/...`).
REPO_ROOT=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || echo "")
CLAIM=""
if [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT/.claude/assignment-claims" ]; then
  # The `|| true` guards against `set -e` + `pipefail` killing the script when
  # find returns non-zero (e.g. directory contains no matches; some bash builds
  # treat the pipeline exit as fatal under set -euo pipefail).
  CLAIM=$(find "$REPO_ROOT/.claude/assignment-claims" -maxdepth 1 -name "*.json" 2>/dev/null | head -1 || true)
fi

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
# Path patterns cover both relative paths (`specs/foo.md` from CWD) and absolute
# paths (`/repo/specs/foo.md`). P1-pattern fix from v0.5 PR review hook-tests.
case "$TARGET" in
  specs/*|*/specs/*|.claude/assignment-claims/*|*/.claude/assignment-claims/*)
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
