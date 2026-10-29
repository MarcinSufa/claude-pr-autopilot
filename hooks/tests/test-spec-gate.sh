#!/usr/bin/env bash
# pr-autopilot v0.5 — unit tests for hooks/enforce-spec-gate.sh + hooks/check-origin-main.sh.
#
# Self-contained: builds isolated git repos in a temp dir, simulates Claude Code
# tool-call JSON on stdin, asserts on the Claude Code PreToolUse blocking contract
# (exit 0 + permissionDecision "deny" JSON, or exit 2) — NOT on exit 1, which
# Claude Code treats as a non-blocking error.
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

# Claude Code PreToolUse blocking contract: a call is BLOCKED only if the hook
# (a) exits 0 and prints hookSpecificOutput.permissionDecision == "deny", or
# (b) exits 2. Exit 1 (or any other code) is a NON-blocking error → counts as "error".
# Args: $1 = name, $2 = expected (deny|allow), uses $ACTUAL, $STDOUT, $STDERR.
decision() {
  if [ "$ACTUAL" = "2" ]; then echo deny; return; fi
  if [ "$ACTUAL" != "0" ]; then echo "error(exit $ACTUAL)"; return; fi
  if [ -z "$STDOUT" ]; then echo allow; return; fi
  local d
  d=$(printf '%s' "$STDOUT" | jq -r 'select(.hookSpecificOutput.hookEventName == "PreToolUse") | .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  case "$d" in
    deny) echo deny ;;
    "") echo "error(unparseable stdout)" ;;
    *) echo "$d" ;;
  esac
}
assert_decision() {
  local name="$1" expected="$2" got
  got=$(decision)
  if [ "$got" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "✓ $name"
  else
    FAIL=$((FAIL + 1))
    echo "✗ $name — expected $expected, got $got"
    [ -n "$STDOUT" ] && echo "  stdout: $STDOUT" | head -3
    [ -n "$STDERR" ] && echo "  stderr: $STDERR" | head -3
  fi
}

# Build a fake git repo with a claim file
# Args: $1 = tmpdir name (under TESTS_TMP), $2 = subStatus, $3 = approvedAt (or null),
#       $4 = origin repo (default test-owner/test-repo)
make_claim_repo() {
  local dir="$TESTS_TMP/$1"
  local sub_status="$2"
  local approved_at="$3"
  local origin="${4:-test-owner/test-repo}"

  mkdir -p "$dir/.claude/assignment-claims" "$dir/specs"
  cd "$dir"
  git init --quiet --initial-branch=feat/test-assignment
  git remote add origin "https://github.com/$origin.git" 2>/dev/null || true
  cat > .claude/assignment-claims/test-assignment.json <<JSON
{
  "assignmentId": "test-assignment",
  "subStatus": "$sub_status",
  "approvedAt": $approved_at,
  "approvedBy": null,
  "approvalContext": null,
  "prNumber": null,
  "branch": "feat/test-assignment"
}
JSON
  git add . >/dev/null 2>&1
  git -c user.email=test@test.local -c user.name=test commit --quiet -m "test setup" 2>/dev/null || true
}

# Run gate with raw hook JSON. Args: $1 = repo dir, $2 = JSON. Sets ACTUAL/STDOUT/STDERR.
run_gate_json() {
  local dir="$1" input="$2"
  local stderr_file="$TESTS_TMP/stderr-$$"
  cd "$dir"
  STDOUT=$(printf '%s' "$input" | bash "$GATE" 2>"$stderr_file")
  ACTUAL=$?
  STDERR=$(cat "$stderr_file" 2>/dev/null || echo "")
  rm -f "$stderr_file"
}

# Run gate for a Write to a file. Args: $1 = repo dir, $2 = target file path
run_gate() {
  run_gate_json "$1" "$(jq -n --arg fp "$2" '{tool_name: "Write", tool_input: {file_path: $fp, content: "x"}}')"
}

# Run gate for a Bash command. Args: $1 = repo dir, $2 = command
run_bash() {
  run_gate_json "$1" "$(jq -n --arg c "$2" --arg w "$1" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $w}')"
}

CLAIM_REL=".claude/assignment-claims/test-assignment.json"

# ─── Setup isolated $HOME (avoids reading real allowlist + paused sentinel) ─
FAKE_HOME="$TESTS_TMP/fakehome"
mkdir -p "$FAKE_HOME/.pr-autopilot"
echo "test-owner/test-repo" > "$FAKE_HOME/.pr-autopilot/allowed-repos"
export HOME="$FAKE_HOME"

# ─── enforce-spec-gate.sh tests ────────────────────────────────────────────

echo ""
echo "─── enforce-spec-gate.sh: Write/Edit/NotebookEdit ──────────────────"

# T1: spec_drafting + edit OUTSIDE specs/ → BLOCK
make_claim_repo "t1" "spec_drafting" null
run_gate "$TESTS_TMP/t1" "src/foo.ts"
assert_decision "T1: spec_drafting + edit outside specs/ → deny" deny
assert_exit "T1b: deny is delivered as exit 0 + JSON (not exit 1)" 0 "$ACTUAL" "$STDERR"

# T2: spec_drafting + edit INSIDE specs/ → ALLOW
make_claim_repo "t2" "spec_drafting" null
run_gate "$TESTS_TMP/t2" "specs/2026-05-28-test.md"
assert_decision "T2: spec_drafting + edit inside specs/ → allow" allow

# T3: spec_drafting + Edit claim file (non-approval field) → ALLOW
make_claim_repo "t3" "spec_drafting" null
run_gate_json "$TESTS_TMP/t3" "$(jq -n --arg fp "$CLAIM_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"spec_drafting\"",new_string:"\"spec_review_requested\""}}')"
assert_decision "T3: spec_drafting + edit claim subStatus → allow" allow

make_claim_repo "t3a" "spec_drafting" null
run_gate_json "$TESTS_TMP/t3a" "$(jq -n --arg fp "$CLAIM_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"spec_drafting\"",new_string:"\"a & b\""}}')"
assert_decision "T3a: Edit claim subStatus with ampersand → allow" allow

make_claim_repo "t3b" "spec_drafting" null
run_gate_json "$TESTS_TMP/t3b" "$(jq -n --arg fp "$CLAIM_REL" '{tool_name:"MultiEdit",tool_input:{file_path:$fp,edits:[{old_string:"\"spec_drafting\"",new_string:"\"a & b\""}]}}')"
assert_decision "T3b: MultiEdit claim subStatus with ampersand → allow" allow

# T4: implementing + approvedAt set → ALLOW
make_claim_repo "t4" "implementing" '"2026-05-28T18:00:00Z"'
run_gate "$TESTS_TMP/t4" "src/foo.ts"
assert_decision "T4: implementing + approvedAt set → allow (gate lifted)" allow

# T5: implementing + approvedAt = null → BLOCK (integrity check, P0-2 fix)
make_claim_repo "t5" "implementing" null
run_gate "$TESTS_TMP/t5" "src/foo.ts"
assert_decision "T5: implementing + approvedAt=null → deny (claim file tampered)" deny

# T6: pr_review_requested + approvedAt set → ALLOW
make_claim_repo "t6" "pr_review_requested" '"2026-05-28T18:00:00Z"'
run_gate "$TESTS_TMP/t6" "src/foo.ts"
assert_decision "T6: pr_review_requested + approvedAt → allow (PR fixes)" allow

# T7: paused sentinel → ALLOW regardless
touch "$FAKE_HOME/.pr-autopilot/paused"
make_claim_repo "t7" "spec_drafting" null
run_gate "$TESTS_TMP/t7" "src/foo.ts"
rm -f "$FAKE_HOME/.pr-autopilot/paused"
assert_decision "T7: paused sentinel → allow (gate off)" allow

# T8: repo not on allowlist → ALLOW (gate off)
echo "different-owner/different-repo" > "$FAKE_HOME/.pr-autopilot/allowed-repos"
make_claim_repo "t8" "spec_drafting" null
run_gate "$TESTS_TMP/t8" "src/foo.ts"
echo "test-owner/test-repo" > "$FAKE_HOME/.pr-autopilot/allowed-repos"  # restore
assert_decision "T8: repo not on allowlist → allow (gate off)" allow

# T9: allowlist case-insensitive (P1-5 v2.1 fix)
echo "TEST-OWNER/TEST-REPO" > "$FAKE_HOME/.pr-autopilot/allowed-repos"  # uppercase
make_claim_repo "t9" "spec_drafting" null
run_gate "$TESTS_TMP/t9" "src/foo.ts"
echo "test-owner/test-repo" > "$FAKE_HOME/.pr-autopilot/allowed-repos"  # restore
assert_decision "T9: allowlist case-insensitive match → deny (gate active)" deny

# T10: no claim file (outside lifecycle) → ALLOW
mkdir -p "$TESTS_TMP/t10"
cd "$TESTS_TMP/t10"
git init --quiet --initial-branch=main 2>/dev/null
git remote add origin "https://github.com/test-owner/test-repo.git" 2>/dev/null || true
run_gate "$TESTS_TMP/t10" "src/foo.ts"
assert_decision "T10: no claim file → allow (outside lifecycle)" allow

# T11: Windows-style path normalisation (P1-5 PR review)
make_claim_repo "t11" "spec_drafting" null
run_gate "$TESTS_TMP/t11" 'C:\repo\specs\foo.md'
assert_decision "T11: Windows path with backslashes + specs/ → allow (normalised)" allow

# T12: Bash call that writes nothing → ALLOW
make_claim_repo "t12" "spec_drafting" null
cd "$TESTS_TMP/t12"
STDOUT=$(echo '{"tool_input": {"command": "ls -la"}}' | bash "$GATE" 2>/dev/null); ACTUAL=$?; STDERR=""
assert_decision "T12: Bash without write targets (no tool_name) → allow" allow

# T13: NotebookEdit outside specs/ (notebook_path, not file_path) → BLOCK
make_claim_repo "t13" "spec_drafting" null
run_gate_json "$TESTS_TMP/t13" '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"notebooks/a.ipynb","new_source":"x"}}'
assert_decision "T13: NotebookEdit outside specs/ → deny" deny

# T14: NotebookEdit inside specs/ → ALLOW
make_claim_repo "t14" "spec_drafting" null
run_gate_json "$TESTS_TMP/t14" '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"specs/a.ipynb","new_source":"x"}}'
assert_decision "T14: NotebookEdit inside specs/ → allow" allow

# T15: repo name containing a dot is still matched against the allowlist
echo "test-owner/my.repo" > "$FAKE_HOME/.pr-autopilot/allowed-repos"
make_claim_repo "t15" "spec_drafting" null "test-owner/my.repo"
run_gate "$TESTS_TMP/t15" "src/foo.ts"
echo "test-owner/test-repo" > "$FAKE_HOME/.pr-autopilot/allowed-repos"  # restore
assert_decision "T15: allowlisted repo name with a dot → deny (gate active)" deny

echo ""
echo "─── enforce-spec-gate.sh: Bash writes (pre-approval) ───────────────"

make_claim_repo "tb" "spec_drafting" null
TB="$TESTS_TMP/tb"
run_bash "$TB" 'echo hi > src/foo.ts';                     assert_decision "T30: redirect into src/ → deny" deny
run_bash "$TB" 'echo hi >> specs/notes.md';                assert_decision "T31: append into specs/ → allow" allow
run_bash "$TB" 'echo hi > /tmp/scratch.txt';               assert_decision "T32: redirect outside repo → allow" allow
run_bash "$TB" 'cat a.txt | tee -a src/a.ts';              assert_decision "T33: tee into src/ → deny" deny
run_bash "$TB" "sed -i 's/a/b/' src/a.ts";                 assert_decision "T34: sed -i on src/ file → deny" deny
run_bash "$TB" 'cp /tmp/x.ts src/';                        assert_decision "T35: cp into tree → deny" deny
run_bash "$TB" 'mv specs/a.md /tmp/a.md';                  assert_decision "T36: mv out to /tmp → allow" allow
run_bash "$TB" 'echo "a > b" | grep a 2>/dev/null';        assert_decision "T37: quoted > and 2>/dev/null → allow" allow
run_bash "$TB" "$(printf 'cat > /tmp/x.sh <<EOF\nif [ 1 > src/b ]; then :; fi\nEOF')"
assert_decision "T38: heredoc body is data, target /tmp → allow" allow
run_bash "$TB" "git status && npm test 2>&1 | head -5";    assert_decision "T39: read-only pipeline → allow" allow
run_bash "$TB" "echo x > $TB/src/abs.ts";                  assert_decision "T40: absolute path into tree → deny" deny
run_bash "$TB" "mv -t src/ /tmp/a.ts";                     assert_decision "T41: mv -t into tree → deny" deny

make_claim_repo "tb2" "implementing" '"2026-05-28T18:00:00Z"'
run_bash "$TESTS_TMP/tb2" 'echo hi > src/foo.ts';          assert_decision "T42: gate lifted + redirect into src/ → allow" allow

echo ""
echo "─── enforce-spec-gate.sh: claim-file approval fields ───────────────"

make_claim_repo "tc" "spec_review_complete" null
TC="$TESTS_TMP/tc"
run_gate_json "$TC" "$(jq -n --arg fp "$CLAIM_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"approvedAt\": null",new_string:"\"approvedAt\": \"2026-01-01T00:00:00Z\""}}')"
assert_decision "T50: Edit adds approvedAt → deny" deny

CUR=$(cat "$TC/$CLAIM_REL")
run_gate_json "$TC" "$(jq -n --arg fp "$TC/$CLAIM_REL" --arg c "$(printf '%s' "$CUR" | jq '.subStatus="implementing" | .approvedAt="2026-01-01T00:00:00Z" | .approvedBy="me"')" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')"
assert_decision "T51: Write sets approvedAt/approvedBy → deny" deny

run_gate_json "$TC" "$(jq -n --arg fp "$CLAIM_REL" --arg c "$(printf '%s' "$CUR" | jq '.subStatus="implementing"')" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')"
assert_decision "T52: Write flips to implementing without approvedAt → deny" deny

run_gate_json "$TC" "$(jq -n --arg fp "$CLAIM_REL" --arg c "$(printf '%s' "$CUR" | jq '.subStatus="spec_revising"')" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')"
assert_decision "T53: Write subStatus → spec_revising (no approval change) → allow" allow

run_gate_json "$TC" "$(jq -n --arg fp "$CLAIM_REL" '{tool_name:"Write",tool_input:{file_path:$fp,content:"{not json"}}')"
assert_decision "T54: Write invalid JSON to claim file → deny" deny

run_bash "$TC" "jq '.approvedAt=\"x\"' $CLAIM_REL > /tmp/claim.json"
assert_decision "T55: Bash jq writing approvedAt → deny" deny
run_bash "$TC" "echo '{}' > $CLAIM_REL"
assert_decision "T56: Bash redirect into claim dir → deny" deny
run_bash "$TC" "bash /plugins/pr-autopilot/skills/approve-spec/scripts/approve-claim.sh test-assignment"
assert_decision "T57: Bash runs approve-claim.sh → deny" deny
run_bash "$TC" "jq -r .approvedAt $CLAIM_REL"
assert_decision "T58: Bash reads approvedAt → allow" allow

make_claim_repo "td" "implementing" '"2026-05-28T18:00:00Z"'
run_gate_json "$TESTS_TMP/td" "$(jq -n --arg fp "$CLAIM_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"prNumber\": null",new_string:"\"prNumber\": 42"}}')"
assert_decision "T59: implementing + Edit prNumber → allow" allow
run_gate_json "$TESTS_TMP/td" "$(jq -n --arg fp "$CLAIM_REL" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"\"approvedBy\": null",new_string:"\"approvedBy\": \"someone\""}}')"
assert_decision "T60: implementing + Edit approvedBy → deny" deny

# T61: jq missing → fall back to exit 2 + stderr (still blocking)
NOJQ="$TESTS_TMP/nojq-bin"
mkdir -p "$NOJQ"
for b in bash git sed awk tr cat find sort grep head date dirname mktemp rm; do
  p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$NOJQ/$b"
done
make_claim_repo "t61" "spec_drafting" null
cd "$TESTS_TMP/t61"
STDOUT=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"src/foo.ts"}}' | PATH="$NOJQ" "$NOJQ/bash" "$GATE" 2>"$TESTS_TMP/nojq-err"); ACTUAL=$?
STDERR=$(cat "$TESTS_TMP/nojq-err")
assert_exit "T61: no jq in PATH → exit 2 (blocking fallback)" 2 "$ACTUAL" "$STDERR"

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
