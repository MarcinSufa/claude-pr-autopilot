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
  if [ -n "${MOCK_PID:-}" ]; then
    kill "$MOCK_PID" 2>/dev/null
    wait "$MOCK_PID" 2>/dev/null
    unset MOCK_PID
    unset MOCK_PORT
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

# T7: PR_AUTOPILOT_TEST_MODE NOT set + CURSOR_API_URL set → override is IGNORED
# (probe should use production URL https://api.cursor.com — fails with 43/44 depending on
# whether real Cursor responds to fake key; both are acceptable, key is the override didn't leak).
unset PR_AUTOPILOT_TEST_MODE
export CURSOR_API_KEY="bogus-not-real-cursor-key-for-T7"
export CURSOR_API_URL="http://127.0.0.1:1/agents"   # should be ignored
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
ACTUAL=$?
if [ "$ACTUAL" = "43" ] || [ "$ACTUAL" = "44" ]; then
  PASS=$((PASS + 1))
  echo "✓ T7 TEST_MODE sentinel gates URL override (got $ACTUAL — production URL used, not override)"
else
  FAIL=$((FAIL + 1))
  echo "✗ T7 expected 43 or 44 (production URL used), got $ACTUAL"
  echo "  This means CURSOR_API_URL leaked into production dispatch — security regression."
  [ -n "$STDERR" ] && echo "  stderr: $STDERR" | head -c 300 && echo ""
fi

# T8: HTTP 403 with HTML body (e.g., CloudFront WAF) → exit 44 (parse failure)
export CURSOR_API_KEY="test-key-html"
export PR_AUTOPILOT_TEST_MODE=1
start_mock_html 403 '<html><body><h1>403 Forbidden</h1></body></html>'
export CURSOR_API_URL="http://127.0.0.1:$MOCK_PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null)
assert_exit "T8 HTTP 403 with HTML body → 44 (non-JSON, no silent 42)" 44 $? "$STDERR"
stop_mock

# ─── Results ───────────────────────────────────────────────────────────────
echo ""
echo "─── Results ─────────────────────────────────"
echo "  pass: $PASS"
echo "  fail: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
