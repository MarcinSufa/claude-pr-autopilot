#!/usr/bin/env bash
# Tests for pr-autopilot-trigger.sh. Run: bash hooks/tests/test-trigger.sh
set -u
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/pr-autopilot-trigger.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PR_AUTOPILOT_HOME="$TMP/home"
mkdir -p "$PR_AUTOPILOT_HOME"
pass=0; fail=0
check() { # name expected_substring actual
  if printf '%s' "$3" | grep -qF "$2"; then pass=$((pass+1)); echo "ok   - $1";
  else fail=$((fail+1)); echo "FAIL - $1 (wanted '$2', got '$3')"; fi
}
check_empty() { # name actual
  if [ -z "$2" ]; then pass=$((pass+1)); echo "ok   - $1";
  else fail=$((fail+1)); echo "FAIL - $1 (wanted empty, got '$2')"; fi
}
mkrepo() { # dir owner/repo  -> a git repo whose origin is that github repo
  local d="$TMP/$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" remote add origin "https://github.com/$2.git"; echo "$d"
}
payload() { # command cwd
  jq -n --arg c "$1" --arg w "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}'
}

REPO_OK="$(mkrepo allowed MarcinSufa/exo-vault)"
REPO_NO="$(mkrepo other MarcinSufa/secret-thing)"
printf 'MarcinSufa/exo-vault\n' > "$PR_AUTOPILOT_HOME/allowed-repos"

# W4: all gates pass -> nudge JSON
out="$(payload "gh pr create --fill" "$REPO_OK" | bash "$SCRIPT")"
check "W4 happy path emits nudge" '"additionalContext"' "$out"
check "W4 nudge names repo"        'MarcinSufa/exo-vault' "$out"

# Gate 0: not a pr-create command -> empty
out="$(payload "gh pr list" "$REPO_OK" | bash "$SCRIPT")"
check_empty "Gate0 non-pr-create -> empty" "$out"

# W1: draft -> empty
out="$(payload "gh pr create --draft" "$REPO_OK" | bash "$SCRIPT")"
check_empty "W1 --draft -> empty" "$out"
out="$(payload "gh pr create -d" "$REPO_OK" | bash "$SCRIPT")"
check_empty "W1 -d -> empty" "$out"

# W2: non-allowlisted repo -> empty
out="$(payload "gh pr create" "$REPO_NO" | bash "$SCRIPT")"
check_empty "W2 non-allowlisted -> empty" "$out"

# W3: paused -> empty
touch "$PR_AUTOPILOT_HOME/paused"
out="$(payload "gh pr create" "$REPO_OK" | bash "$SCRIPT")"
check_empty "W3 paused -> empty" "$out"
rm -f "$PR_AUTOPILOT_HOME/paused"

# W5: malformed stdin -> exit 0, empty stdout
out="$(printf 'not json' | bash "$SCRIPT"; echo "exit=$?")"
check "W5 malformed -> exit 0" "exit=0" "$out"

# Fix-1 regression: trailing slash in origin URL still matches allowlist
REPO_SLASH="$TMP/slashrepo"; mkdir -p "$REPO_SLASH"; git -C "$REPO_SLASH" init -q
git -C "$REPO_SLASH" remote add origin "https://github.com/MarcinSufa/exo-vault/"
out="$(payload "gh pr create" "$REPO_SLASH" | bash "$SCRIPT")"
check "trailing-slash URL still matches allowlist" '"additionalContext"' "$out"

# No origin remote -> skip silently
REPO_NOREMOTE="$TMP/noremote"; mkdir -p "$REPO_NOREMOTE"; git -C "$REPO_NOREMOTE" init -q
out="$(payload "gh pr create" "$REPO_NOREMOTE" | bash "$SCRIPT")"
check_empty "no origin remote -> empty" "$out"

# Trailing-whitespace allowlist line still matches (hygiene)
printf 'MarcinSufa/exo-vault   \n' > "$PR_AUTOPILOT_HOME/allowed-repos"
out="$(payload "gh pr create" "$REPO_OK" | bash "$SCRIPT")"
check "trailing-whitespace allowlist line matches" '"additionalContext"' "$out"
printf 'MarcinSufa/exo-vault\n' > "$PR_AUTOPILOT_HOME/allowed-repos"  # restore

# Fix-1 regression: .git WITH trailing slash still parses + matches
REPO_GITSLASH="$TMP/gitslash"; mkdir -p "$REPO_GITSLASH"; git -C "$REPO_GITSLASH" init -q
git -C "$REPO_GITSLASH" remote add origin "https://github.com/MarcinSufa/exo-vault.git/"
out="$(payload "gh pr create" "$REPO_GITSLASH" | bash "$SCRIPT")"
check "Fix1: .git/ trailing slash matches allowlist" '"additionalContext"' "$out"

# Fix-2 regression: case-insensitive allowlist match (lowercase origin vs canonical entry)
REPO_LC="$TMP/lcrepo"; mkdir -p "$REPO_LC"; git -C "$REPO_LC" init -q
git -C "$REPO_LC" remote add origin "https://github.com/marcinsufa/exo-vault.git"
out="$(payload "gh pr create" "$REPO_LC" | bash "$SCRIPT")"
check "Fix2: lowercase origin matches canonical allowlist entry" '"additionalContext"' "$out"

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" = "0" ]
