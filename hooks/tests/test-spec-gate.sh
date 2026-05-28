#!/usr/bin/env bash
# pr-autopilot v0.5 — unit tests for hooks/enforce-spec-gate.sh + hooks/check-origin-main.sh.
#
# Self-contained: builds isolated git repos in a temp dir, simulates Claude Code
# tool-call JSON on stdin, asserts on exit codes + stderr.
#
# Run: bash hooks/tests/test-spec-gate.sh
#
# Wzorowane na hooks/tests/test-trigger.sh (v0.3).

set -u  # nieumyślnie nieustawione zmienne = fail; ale NIE set -e (każdy test
        # raportowany niezależnie, suma `fail` wraca jako exit code).

# ─── Locate scripts under test ─────────────────────────────────────────────
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$HOOKS_DIR/enforce-spec-gate.sh"
ORIGIN_CHECK="$HOOKS_DIR/check-origin-main.sh"

for f in "$GATE" "$ORIGIN_CHECK"; do
  if [ ! -x "$f" ] && ! head -1 "$f" 2>/dev/null | grep -q '#!/usr/bin/env bash'; then
    echo "✗ script not found or not bash-runnable: $f" >&2
    exit 2
  fi
done

# ─── Test harness ──────────────────────────────────────────────────────────
PASS=0
FAIL=0
TESTS_TMP=$(mktemp -d -t pr-autopilot-tests.XXXXXX)
trap 'rm -rf "$TESTS_TMP"' EXIT

# Original $HOME (we override per test for allowlist/pause isolation)
REAL_HOME="$HOME"

assert_exit() {
  local name="$1" expected="$2" actual="$3" stderr="$4"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "✓ $name"
  else
    FAIL=$((FAIL + 1))
    echo "✗ $name — expected exit $expected, got $actual"
    [ -n "$stderr" ] && echo "  stderr: $stderr" | head -3
  fi
}

# Build a fake git repo with a claim file
# Args: $1 = tmpdir name (under TESTS_TMP), $2 = subStatus, $3 = approvedAt (or null)
make_claim_repo() {
  local dir="$TESTS_TMP/$1"
  local sub_status="$2"
  local approved_at="$3"

  mkdir -p "$dir/.claude/assignment-claims" "$dir/specs"
  cd "$dir"
  git init --quiet --initial-branch=feat/test-assignment
  git remote add origin "https://github.com/test-owner/test-repo.git" 2>/dev/null || true
  cat > .claude/assignment-claims/test-assignment.json <<JSON
{
  "assignmentId": "test-assignment",
  "subStatus": "$sub_status",
  "approvedAt": $approved_at,
  "branch": "feat/test-assignment"
}
JSON
  git add . >/dev/null 2>&1
  git -c user.email=test@test.local -c user.name=test commit --quiet -m "test setup" 2>/dev/null || true
}

# Run gate with given target file + claim repo dir
# Args: $1 = repo dir, $2 = target file path
run_gate() {
  local dir="$1" target="$2"
  local stderr_file="$TESTS_TMP/stderr-$$"
  local input
  input=$(jq -n --arg fp "$target" '{tool_input: {file_path: $fp}}')

  cd "$dir"
  echo "$input" | bash "$GATE" 2>"$stderr_file"
  local exit_code=$?
  STDERR=$(cat "$stderr_file" 2>/dev/null || echo "")
  rm -f "$stderr_file"
  return $exit_code
}

# ─── Setup isolated $HOME (avoids reading real allowlist + paused sentinel) ─
FAKE_HOME="$TESTS_TMP/fakehome"
mkdir -p "$FAKE_HOME/.pr-autopilot"
echo "test-owner/test-repo" > "$FAKE_HOME/.pr-autopilot/allowed-repos"
export HOME="$FAKE_HOME"

# ─── enforce-spec-gate.sh tests ────────────────────────────────────────────

echo ""
echo "─── enforce-spec-gate.sh ─────────────────────────────────────────────"

# T1: spec_drafting + edit OUTSIDE specs/ → BLOCK
make_claim_repo "t1" "spec_drafting" null
run_gate "$TESTS_TMP/t1" "src/foo.ts"; ACTUAL=$?
assert_exit "T1: spec_drafting + edit outside specs/ → exit 1 (BLOCK)" 1 "$ACTUAL" "$STDERR"

# T2: spec_drafting + edit INSIDE specs/ → ALLOW
make_claim_repo "t2" "spec_drafting" null
run_gate "$TESTS_TMP/t2" "specs/2026-05-28-test.md"; ACTUAL=$?
assert_exit "T2: spec_drafting + edit inside specs/ → exit 0 (ALLOW)" 0 "$ACTUAL" "$STDERR"

# T3: spec_drafting + edit claim file → ALLOW (skills need to write transitions)
make_claim_repo "t3" "spec_drafting" null
run_gate "$TESTS_TMP/t3" ".claude/assignment-claims/test-assignment.json"; ACTUAL=$?
assert_exit "T3: spec_drafting + edit claim file → exit 0 (ALLOW)" 0 "$ACTUAL" "$STDERR"

# T4: implementing + approvedAt set → ALLOW
make_claim_repo "t4" "implementing" '"2026-05-28T18:00:00Z"'
run_gate "$TESTS_TMP/t4" "src/foo.ts"; ACTUAL=$?
assert_exit "T4: implementing + approvedAt set → exit 0 (gate lifted)" 0 "$ACTUAL" "$STDERR"

# T5: implementing + approvedAt = null → BLOCK (integrity check, P0-2 fix)
make_claim_repo "t5" "implementing" null
run_gate "$TESTS_TMP/t5" "src/foo.ts"; ACTUAL=$?
assert_exit "T5: implementing + approvedAt=null → exit 1 (claim file tampered)" 1 "$ACTUAL" "$STDERR"

# T6: pr_review_requested + approvedAt set → ALLOW
make_claim_repo "t6" "pr_review_requested" '"2026-05-28T18:00:00Z"'
run_gate "$TESTS_TMP/t6" "src/foo.ts"; ACTUAL=$?
assert_exit "T6: pr_review_requested + approvedAt → exit 0 (allow PR fixes)" 0 "$ACTUAL" "$STDERR"

# T7: paused sentinel → ALLOW regardless
touch "$FAKE_HOME/.pr-autopilot/paused"
make_claim_repo "t7" "spec_drafting" null
run_gate "$TESTS_TMP/t7" "src/foo.ts"; ACTUAL=$?
rm -f "$FAKE_HOME/.pr-autopilot/paused"
assert_exit "T7: paused sentinel → exit 0 (gate off)" 0 "$ACTUAL" "$STDERR"

# T8: repo not on allowlist → ALLOW (gate off)
echo "different-owner/different-repo" > "$FAKE_HOME/.pr-autopilot/allowed-repos"
make_claim_repo "t8" "spec_drafting" null
run_gate "$TESTS_TMP/t8" "src/foo.ts"; ACTUAL=$?
echo "test-owner/test-repo" > "$FAKE_HOME/.pr-autopilot/allowed-repos"  # restore
assert_exit "T8: repo not on allowlist → exit 0 (gate off)" 0 "$ACTUAL" "$STDERR"

# T9: allowlist case-insensitive (P1-5 v2.1 fix)
echo "TEST-OWNER/TEST-REPO" > "$FAKE_HOME/.pr-autopilot/allowed-repos"  # uppercase
make_claim_repo "t9" "spec_drafting" null
run_gate "$TESTS_TMP/t9" "src/foo.ts"; ACTUAL=$?
echo "test-owner/test-repo" > "$FAKE_HOME/.pr-autopilot/allowed-repos"  # restore
assert_exit "T9: allowlist case-insensitive match → exit 1 (gate active)" 1 "$ACTUAL" "$STDERR"

# T10: no claim file (outside lifecycle) → ALLOW
mkdir -p "$TESTS_TMP/t10"
cd "$TESTS_TMP/t10"
git init --quiet --initial-branch=main 2>/dev/null
git remote add origin "https://github.com/test-owner/test-repo.git" 2>/dev/null || true
INPUT=$(jq -n --arg fp "src/foo.ts" '{tool_input: {file_path: $fp}}')
STDERR_FILE="$TESTS_TMP/stderr-$$"
echo "$INPUT" | bash "$GATE" 2>"$STDERR_FILE"; ACTUAL=$?
STDERR=$(cat "$STDERR_FILE"); rm -f "$STDERR_FILE"
assert_exit "T10: no claim file → exit 0 (outside lifecycle)" 0 "$ACTUAL" "$STDERR"

# T11: Windows-style path normalisation (P1-5 PR review)
make_claim_repo "t11" "spec_drafting" null
INPUT=$(jq -n --arg fp 'C:\\repo\\specs\\foo.md' '{tool_input: {file_path: $fp}}')
STDERR_FILE="$TESTS_TMP/stderr-$$"
cd "$TESTS_TMP/t11"
echo "$INPUT" | bash "$GATE" 2>"$STDERR_FILE"; ACTUAL=$?
STDERR=$(cat "$STDERR_FILE"); rm -f "$STDERR_FILE"
assert_exit "T11: Windows path with backslashes + specs/ → exit 0 (normalised)" 0 "$ACTUAL" "$STDERR"

# T12: non-path tool call (e.g. Bash) → ALLOW
make_claim_repo "t12" "spec_drafting" null
cd "$TESTS_TMP/t12"
echo '{"tool_input": {"command": "ls -la"}}' | bash "$GATE" 2>/dev/null; ACTUAL=$?
assert_exit "T12: tool call without file_path → exit 0 (not gated)" 0 "$ACTUAL" ""

# ─── check-origin-main.sh tests ───────────────────────────────────────────

echo ""
echo "─── check-origin-main.sh ────────────────────────────────────────────"

# T20: not a git repo → exit 0, no crash
mkdir -p "$TESTS_TMP/t20-notgit"
cd "$TESTS_TMP/t20-notgit"
bash "$ORIGIN_CHECK" >/dev/null 2>&1; ACTUAL=$?
assert_exit "T20: not in a git repo → exit 0 (graceful)" 0 "$ACTUAL" ""

# T21: git repo with no `main` branch (e.g. fresh repo) → exit 0 (informative output)
mkdir -p "$TESTS_TMP/t21-no-main"
cd "$TESTS_TMP/t21-no-main"
git init --quiet --initial-branch=trunk 2>/dev/null
bash "$ORIGIN_CHECK" >/dev/null 2>&1; ACTUAL=$?
assert_exit "T21: no 'main' branch → exit 0 (informative)" 0 "$ACTUAL" ""

# ─── Restore real HOME ─────────────────────────────────────────────────────
export HOME="$REAL_HOME"

# ─── Report ────────────────────────────────────────────────────────────────
echo ""
echo "─── Summary ──────────────────────────────────────────────────────────"
TOTAL=$((PASS + FAIL))
echo "pass=$PASS fail=$FAIL total=$TOTAL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
