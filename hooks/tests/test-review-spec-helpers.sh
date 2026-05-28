#!/usr/bin/env bash
# pr-autopilot v0.5.1 — unit tests for hooks/cursor-cloud-agent-probe.sh
#
# Run: bash hooks/tests/test-review-spec-helpers.sh
#
# Pattern follows hooks/tests/test-spec-gate.sh (v0.5):
#   - set -u (not -e) so each test reports independently
#   - PASS/FAIL counts + non-zero exit on any failure
#   - mock server via python3 http.server (no extra deps)
#   - testable URL via CURSOR_API_URL env var, gated by PR_AUTOPILOT_TEST_MODE=1
#
# Coverage:
#   T1 — no CURSOR_API_KEY                       → exit 43
#   T2 — HTTP 200 (Pro)                          → exit 0
#   T3 — HTTP 401 (invalid key)                  → exit 43
#   T4 — HTTP 403 plan_required (Free)           → exit 42
#   T5 — HTTP 403 other code                     → exit 44
#   T6 — connection refused (network)            → exit 44
#   T7 — TEST_MODE not set, URL override leaks?  → exit != 0 (production URL used)
#   T8 — HTTP 403 with non-JSON HTML body         → exit 44 (parse failure)

set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$HOOKS_DIR/cursor-cloud-agent-probe.sh"

if [ ! -f "$PROBE" ]; then
  echo "✗ probe not found at: $PROBE" >&2
  echo "  (this is expected during TDD red phase — implement the probe next)" >&2
  exit 2
fi

chmod +x "$PROBE" 2>/dev/null

# ─── Dependency check ──────────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
  echo "✗ python3 required for mock server (winget install Python.Python.3.12 or similar)" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq required by probe (winget install jqlang.jq)" >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "✗ curl required by probe" >&2
  exit 2
fi

# ─── Test harness ──────────────────────────────────────────────────────────
PASS=0
FAIL=0

assert_exit() {
  local name="$1" expected="$2" actual="$3" stderr="${4:-}"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "✓ $name"
  else
    FAIL=$((FAIL + 1))
    echo "✗ $name — expected exit $expected, got $actual"
    [ -n "$stderr" ] && echo "  stderr: $stderr" | head -c 300 && echo ""
  fi
}

# Start a mock server. Args: $1=http_code, $2=body_json (single-line).
# Sets MOCK_PORT + MOCK_PID. Caller must call stop_mock when done.
start_mock() {
  local http_code="$1" body="$2"
  # Pick a high port unlikely to collide
  local port=$((50000 + RANDOM % 10000))

  python3 -c "
import http.server, socketserver, sys
class H(http.server.BaseHTTPRequestHandler):
  def do_GET(self):
    self.send_response($http_code)
    self.send_header('Content-Type', 'application/json')
    self.end_headers()
    self.wfile.write('''$body'''.encode())
  def log_message(self, *args, **kwargs):
    pass
srv = socketserver.TCPServer(('127.0.0.1', $port), H)
srv.serve_forever()
" &
  MOCK_PID=$!
  MOCK_PORT=$port

  # Give the server a moment to bind
  local i
  for i in 1 2 3 4 5; do
    if curl -sS -m 1 -o /dev/null "http://127.0.0.1:$MOCK_PORT/" 2>/dev/null; then
      return 0
    fi
    sleep 0.2
  done
  echo "  (mock server failed to start on port $MOCK_PORT)" >&2
  return 1
}

stop_mock() {
  # NOTE: do NOT `wait $MOCK_PID` — on MSYS/Git-Bash for Windows the python
  # subprocess may not be a direct child of this shell, so wait hangs forever.
  # `kill` + small sleep is more portable. Per code-reviewer iter2 finding.
  if [ -n "${MOCK_PID:-}" ]; then
    kill "$MOCK_PID" 2>/dev/null
    sleep 0.2
    unset MOCK_PID
    unset MOCK_PORT
  fi
  if [ -n "${MOCK_LOG:-}" ]; then
    rm -f "$MOCK_LOG"
    unset MOCK_LOG
  fi
}

# Start a mock that returns HTML (non-JSON body) for T8.
start_mock_html() {
  local http_code="$1" body="$2"
  local port=$((50000 + RANDOM % 10000))

  python3 -c "
import http.server, socketserver, sys
class H(http.server.BaseHTTPRequestHandler):
  def do_GET(self):
    self.send_response($http_code)
    self.send_header('Content-Type', 'text/html')
    self.end_headers()
    self.wfile.write('''$body'''.encode())
  def log_message(self, *args, **kwargs):
    pass
srv = socketserver.TCPServer(('127.0.0.1', $port), H)
srv.serve_forever()
" &
  MOCK_PID=$!
  MOCK_PORT=$port

  local i
  for i in 1 2 3 4 5; do
    if curl -sS -m 1 -o /dev/null "http://127.0.0.1:$MOCK_PORT/" 2>/dev/null; then
      return 0
    fi
    sleep 0.2
  done
  echo "  (mock server failed to start on port $MOCK_PORT)" >&2
  return 1
}

# Cleanup any stray mock on exit
trap 'stop_mock' EXIT

# ─── Tests ─────────────────────────────────────────────────────────────────

# T1: no CURSOR_API_KEY set → exit 43
unset CURSOR_API_KEY 2>/dev/null
unset PR_AUTOPILOT_TEST_MODE 2>/dev/null
unset CURSOR_API_URL 2>/dev/null
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T1 no CURSOR_API_KEY → 43 (treat-missing-as-invalid)" 43 $? "$STDERR"

# T2: HTTP 200 (Pro available) → exit 0
export CURSOR_API_KEY="test-key-200"
export PR_AUTOPILOT_TEST_MODE=1
start_mock 200 '{"runs":[]}'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T2 HTTP 200 → 0 (Pro)" 0 $? "$STDERR"
stop_mock

# T3: HTTP 401 (invalid key) → exit 43
export CURSOR_API_KEY="test-key-401"
export PR_AUTOPILOT_TEST_MODE=1
start_mock 401 '{"error":{"code":"invalid_key","message":"unauthorized"}}'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T3 HTTP 401 → 43 (invalid_key)" 43 $? "$STDERR"
stop_mock

# T4: HTTP 403 plan_required (Cursor Free) → exit 42
export CURSOR_API_KEY="test-key-403-pr"
export PR_AUTOPILOT_TEST_MODE=1
start_mock 403 '{"error":{"code":"plan_required","message":"Cloud Agent is not available for free users. Please upgrade to Pro."}}'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T4 HTTP 403 plan_required → 42 (Free)" 42 $? "$STDERR"
stop_mock

# T5: HTTP 403 other code → exit 44
export CURSOR_API_KEY="test-key-403-other"
export PR_AUTOPILOT_TEST_MODE=1
start_mock 403 '{"error":{"code":"forbidden","message":"WAF block"}}'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T5 HTTP 403 unknown code → 44" 44 $? "$STDERR"
stop_mock

# T6: connection refused (network) → exit 44
export CURSOR_API_KEY="test-key-network"
export PR_AUTOPILOT_TEST_MODE=1
# Port 1 is unbindable in user space on Windows/Linux → ECONNREFUSED
export CURSOR_API_URL="http://127.0.0.1:1/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T6 connection refused → 44 (network)" 44 $? "$STDERR"

# T7: PR_AUTOPILOT_TEST_MODE NOT set + CURSOR_API_URL → override MUST NOT leak.
# Signal: probe exit code. If probe exits 0, override leaked (only mock returns
# 200; production api.cursor.com always 401s a bogus key). If probe exits
# non-zero (43/44), override correctly ignored → production URL was used.
# Per hostile review iter2 finding: old test accepted exit 43 OR 44, which was
# ambiguous because 44 could mean leak (override hit unbindable :1) OR no-leak
# (real Cursor returned non-401). New signal — "not 0" — is unambiguous.
#
# Network requirement: T7 reaches https://api.cursor.com — needs egress. In
# air-gapped CI this would return 44 (network failure) which still satisfies
# the "not 0" assertion → no-leak is correctly inferred. Per Composer review
# iter3 finding (P1-3).

unset PR_AUTOPILOT_TEST_MODE
export CURSOR_API_KEY="bogus-not-real-cursor-key-for-T7"
start_mock 200 '{"runs":[]}'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"   # MUST be ignored
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
ACTUAL=$?
if [ "$ACTUAL" != "0" ]; then
  PASS=$((PASS + 1))
  echo "✓ T7 TEST_MODE=off + override URL — probe did NOT exit 0 (no leak; exit=$ACTUAL)"
else
  FAIL=$((FAIL + 1))
  echo "✗ T7 probe exited 0 — CURSOR_API_URL leaked (probe hit mock returning 200 instead of production)"
fi
stop_mock

# T7b: TEST_MODE=1 + CURSOR_API_URL=mock(returns 200) → probe MUST exit 0
# (Proves the gate's positive case — override is honored when explicitly opted in.)
export PR_AUTOPILOT_TEST_MODE=1
export CURSOR_API_KEY="test-key-T7b"
start_mock 200 '{"runs":[]}'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T7b TEST_MODE=on + override URL → 0 (mock hit, override active)" 0 $? "$STDERR"
stop_mock
unset PR_AUTOPILOT_TEST_MODE

# T8: HTTP 403 with HTML body (e.g., CloudFront WAF) → exit 44 (parse failure)
export CURSOR_API_KEY="test-key-html"
export PR_AUTOPILOT_TEST_MODE=1
start_mock_html 403 '<html><body><h1>403 Forbidden</h1></body></html>'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T8 HTTP 403 with HTML body → 44 (non-JSON, no silent 42)" 44 $? "$STDERR"
stop_mock

# T8b: HTTP 200 with HTML body (corp proxy "you are blocked") → exit 44 (don't trust 200 unconditionally)
# Per hostile review iter2 finding (probe trusted 200 unconditionally).
export CURSOR_API_KEY="test-key-html-200"
export PR_AUTOPILOT_TEST_MODE=1
start_mock_html 200 '<html><body>Corporate proxy: blocked.</body></html>'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T8b HTTP 200 with HTML body → 44 (no false Pro-OK on proxy/captive page)" 44 $? "$STDERR"
stop_mock

# T12: HTTP 400 with Privacy Mode (Legacy) message → exit 45 (Gap E, v0.5.2).
# Discovered live 2026-05-28: Marcin upgraded to Cursor Pro but API returned 400 with
# "Cloud agent is not supported in Privacy Mode (Legacy)" message. v0.5.1 classified
# as generic exit 44; v0.5.2 detects message OR error.code → actionable exit 45.
export CURSOR_API_KEY="test-key-T12"
export PR_AUTOPILOT_TEST_MODE=1
start_mock 400 '{"error":{"code":"validation_error","message":"Bad Request: Cloud agent is not supported in Privacy Mode (Legacy). Switch to Privacy Mode to use cloud agents."}}'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T12 HTTP 400 Privacy Mode (Legacy) message → 45" 45 $? "$STDERR"
stop_mock

# T12b: HTTP 400 with privacy_mode_required CODE but unrelated message → exit 45 (code path).
# Defense-in-depth: detect via error.code field too, not just message text.
# Per Composer review iter3 P1-4 (message-only detection was half-tested).
export CURSOR_API_KEY="test-key-T12b"
export PR_AUTOPILOT_TEST_MODE=1
start_mock 400 '{"error":{"code":"privacy_mode_required","message":"Configuration error"}}'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T12b HTTP 400 privacy_mode_required code → 45 (code-based detection)" 45 $? "$STDERR"
stop_mock

# T13: HTTP 400 with generic validation_error → exit 44 (no privacy_mode mention).
# Ensures we don't over-classify all 400s as privacy_mode.
export CURSOR_API_KEY="test-key-T13"
export PR_AUTOPILOT_TEST_MODE=1
start_mock 400 '{"error":{"code":"validation_error","message":"Required parameter missing"}}'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T13 HTTP 400 generic validation_error → 44 (not privacy_mode)" 44 $? "$STDERR"
stop_mock

# T9: bootstrap-force-audit.sh — no force flag → output starts with "Bootstrap review of"
AUDIT_SCRIPT="$HOOKS_DIR/bootstrap-force-audit.sh"
if [ ! -x "$AUDIT_SCRIPT" ]; then chmod +x "$AUDIT_SCRIPT" 2>/dev/null; fi
OUTPUT=$(bash "$AUDIT_SCRIPT" "/tmp/test-spec.md" 2>/dev/null)
ACTUAL=$?
if [ "$ACTUAL" = "0" ] && echo "$OUTPUT" | grep -q "^Bootstrap review of /tmp/test-spec.md at "; then
  PASS=$((PASS + 1))
  echo "✓ T9 audit (no force) → exit 0 + 'Bootstrap review of <path> at <iso>'"
else
  FAIL=$((FAIL + 1))
  echo "✗ T9 expected exit 0 + 'Bootstrap review of /tmp/test-spec.md at ...'; got exit=$ACTUAL, output=$OUTPUT"
fi

# T10: bootstrap-force-audit.sh — with force flag → output starts with "[BOOTSTRAP_FORCE]"
OUTPUT=$(bash "$AUDIT_SCRIPT" "/tmp/test-spec.md" force 2>/dev/null)
ACTUAL=$?
if [ "$ACTUAL" = "0" ] && echo "$OUTPUT" | grep -q "^\[BOOTSTRAP_FORCE\] Bootstrap review of /tmp/test-spec.md at "; then
  PASS=$((PASS + 1))
  echo "✓ T10 audit (force) → exit 0 + '[BOOTSTRAP_FORCE] Bootstrap review of <path> at <iso>'"
else
  FAIL=$((FAIL + 1))
  echo "✗ T10 expected exit 0 + '[BOOTSTRAP_FORCE] ...'; got exit=$ACTUAL, output=$OUTPUT"
fi

# T11: bootstrap-force-audit.sh — missing args → exit 2
OUTPUT=$(bash "$AUDIT_SCRIPT" 2>&1)
ACTUAL=$?
if [ "$ACTUAL" = "2" ] && echo "$OUTPUT" | grep -qi "usage"; then
  PASS=$((PASS + 1))
  echo "✓ T11 audit (no args) → exit 2 + usage message"
else
  FAIL=$((FAIL + 1))
  echo "✗ T11 expected exit 2 + usage message; got exit=$ACTUAL, output=$OUTPUT"
fi

# ─── Results ───────────────────────────────────────────────────────────────
echo ""
echo "─── Results ─────────────────────────────────"
echo "  pass: $PASS"
echo "  fail: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
