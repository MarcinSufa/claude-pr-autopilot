#!/usr/bin/env bash
# pr-autopilot v0.5 — SessionStart safety net.
#
# Warns if local `main` branch or current feature-branch base is stale vs origin/main.
# Output to stdout becomes Claude Code session-prefix context.
#
# Policy:
#   - Always runs (does NOT honor /pr-autopilot:allow allowlist or ~/.pr-autopilot/paused
#     sentinel) because the cost is tiny (8s timeout) and the value is high (prevents
#     "spent 1h planning on stale main" failure mode).
#   - Always exits 0 — never blocks a session.

set -u

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$REPO_ROOT" || exit 0

# Fetch with timeout. Offline → graceful skip.
if ! timeout 8 git fetch --quiet origin main 2>/dev/null; then
  echo "[pr-autopilot/origin-check] could not fetch origin/main (offline or slow); skipping."
  exit 0
fi

# A) is local `main` branch behind origin/main?
MAIN_BEHIND=$(git rev-list --count main..origin/main 2>/dev/null || echo "?")

# B) is current branch's base behind origin/main? (true rebase signal for feature branches)
BASE=$(git merge-base HEAD origin/main 2>/dev/null || echo "")
if [ -n "$BASE" ]; then
  BASE_BEHIND=$(git rev-list --count "$BASE"..origin/main 2>/dev/null || echo "?")
else
  BASE_BEHIND="?"
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "(detached)")

case "$MAIN_BEHIND/$BASE_BEHIND" in
  "0/0")
    echo "[pr-autopilot/origin-check] up to date with origin/main ✓ (branch: $CURRENT_BRANCH)"
    ;;
  "0/"*)
    echo "[pr-autopilot/origin-check] ⚠ assignment base is $BASE_BEHIND commit(s) behind origin/main on '$CURRENT_BRANCH'."
    echo "  Recent missed commits:"
    git log --oneline "$BASE"..origin/main 2>/dev/null | head -5 | sed 's/^/    /'
    echo "  Consider rebasing: git fetch && git rebase origin/main"
    ;;
  *)
    echo "[pr-autopilot/origin-check] ⚠ local 'main' is $MAIN_BEHIND commit(s) behind origin/main."
    echo "  Recent missed commits:"
    git log --oneline main..origin/main 2>/dev/null | head -5 | sed 's/^/    /'
    echo "  If starting new work: git worktree add .claude/worktrees/<id> -b <branch> origin/main"
    ;;
esac

exit 0  # never block a session
