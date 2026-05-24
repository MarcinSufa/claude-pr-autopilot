#!/usr/bin/env bash
# pr-autopilot auto-trigger gate (PostToolUse hook).
# Reads hook JSON on stdin. Emits an additionalContext nudge IFF the command is
# `gh pr create`, not a draft, the repo is allowlisted, and not paused.
# ALWAYS exits 0 — a hook error must never break the user's Bash flow.
set -u
HOME_DIR="${PR_AUTOPILOT_HOME:-$HOME/.pr-autopilot}"
mkdir -p "$HOME_DIR" 2>/dev/null || true
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$HOME_DIR/hook.log" 2>/dev/null || true; }

payload="$(cat 2>/dev/null || true)"
command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$command" ] || { log "no command; skip"; exit 0; }

# GATE 0 — must be `gh pr create` (correctness floor when `if` unavailable)
printf '%s' "$command" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || exit 0

# GATE 1 — skip drafts (--draft, --draft=true, -d)
if printf '%s' "$command" | grep -qE '(^|[[:space:]])(--draft|-d)([[:space:]=]|$)'; then
  log "draft; skip"; exit 0
fi

# GATE 3 — paused  (intentionally checked before GATE 2: a file stat is cheaper than the git call below)
[ -f "$HOME_DIR/paused" ] && { log "paused; skip"; exit 0; }

# GATE 2 — allowlist
[ -n "$cwd" ] || { log "no cwd; skip"; exit 0; }
url="$(git -C "$cwd" remote get-url origin 2>/dev/null || true)"   # origin only
[ -n "$url" ] || { log "no origin remote; skip"; exit 0; }
repo="$(printf '%s' "$url" | sed -E 's#^.*github\.com[:/]+##; s#(\.git)?/*$##')"
case "$repo" in */*) : ;; *) log "cannot parse repo from $url; skip"; exit 0 ;; esac
allow="$HOME_DIR/allowed-repos"
[ -f "$allow" ] || { log "no allowlist; skip"; exit 0; }
repo_lc="$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"
match=0
while IFS= read -r line || [ -n "$line" ]; do
  line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"  # trim
  [ -z "$line" ] && continue                                                       # skip blank
  case "$line" in */*) : ;; *) continue ;; esac                                    # require slash
  line_lc="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
  [ "$line_lc" = "$repo_lc" ] && { match=1; break; }
done < "$allow"
[ "$match" = "1" ] || { log "repo $repo not allowed; skip"; exit 0; }

# All gates passed — emit nudge. Claude supplies the PR number.
nudge="pr-autopilot auto-trigger: you just created a PR in ${repo} (an allowed repo). When you finish your current task (e.g. /ship), start the autopilot loop on it: (1) resolve the PR number with \`gh pr view --json number -q .number\` on the current branch; (2) before starting, check whether a loop is already running for this PR: resolve the canonical repo with \`gh repo view --json nameWithOwner -q .nameWithOwner\`, and if \`~/.pr-autopilot/<owner>-<name>-<N>.json\` (owner/name from that canonical value, slashes→dashes) already exists, do NOT start a second loop; (3) otherwise call ScheduleWakeup(delaySeconds=30, prompt='/loop /pr-autopilot:step <N>', reason='autopilot auto-start'). Do not begin unrelated work to start this loop."
jq -n --arg ctx "$nudge" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
log "nudged for $repo"
exit 0
