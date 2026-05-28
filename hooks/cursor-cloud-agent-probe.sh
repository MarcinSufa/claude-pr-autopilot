#!/usr/bin/env bash
# pr-autopilot v0.5.1 — Cursor Cloud Agent plan-eligibility probe.
#
# Pre-flight check before dispatching cursor-cloud-agent in /review-spec.
# Exit codes are consumed by skills/review-spec/SKILL.md via `case $?`:
#   0  — Pro plan, Cloud Agent available
#   42 — API key valid but plan is Free / plan_required
#   43 — API key invalid (401) or missing
#   44 — Network / timeout / parse failure / other (non-deterministic)
#
# Stdin: nothing.
# Stdout: nothing (silent).
# Stderr: short reason on non-zero exit (for skill to surface to user).
#
# Testability: CURSOR_API_URL env var overrides the endpoint ONLY when
# PR_AUTOPILOT_TEST_MODE=1 is also set. This gates testability behind explicit
# opt-in and prevents accidental override leaking into production dispatch.
#
# Discovered by: dogfood iteration onboarding Asistel (ExoVault memory c7e9c5d1).
# Spec: docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.1-review-spec-improvements.md §5.3.

set -u  # Intentionally NOT `set -e` — we capture curl/jq exit codes and translate.

# ─── Dependency checks ─────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "jq required (install: winget install jqlang.jq)" >&2
  exit 44
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl required" >&2
  exit 44
fi

# ─── Key check ─────────────────────────────────────────────────────────────
KEY="${CURSOR_API_KEY:-}"
if [ -z "$KEY" ]; then
  echo "no CURSOR_API_KEY set" >&2
  exit 43
fi

# ─── URL resolution (production by default, override only with TEST_MODE) ──
URL="https://api.cursor.com/v1/agents?limit=1"
if [ "${PR_AUTOPILOT_TEST_MODE:-0}" = "1" ] && [ -n "${CURSOR_API_URL:-}" ]; then
  URL="${CURSOR_API_URL}?limit=1"
fi

# ─── Probe ─────────────────────────────────────────────────────────────────
# mktemp avoids $$ collision when probe runs concurrently.
# Portable form: works on GNU coreutils (Linux) AND BSD (macOS, Git Bash for Windows).
# The bare-`mktemp -t pattern.XXX` form is GNU-only; explicit TMPDIR template works
# on both. Per review iter2 finding (mktemp portability).
TMP=$(mktemp "${TMPDIR:-/tmp}/pr-autopilot-cursor-probe.XXXXXX") || {
  echo "could not create temp file" >&2
  exit 44
}
trap 'rm -f "$TMP"' EXIT

HTTP=$(curl -sS -m 8 -o "$TMP" -w "%{http_code}" \
  -H "Authorization: Bearer $KEY" \
  "$URL" 2>/dev/null) || HTTP="000"

# ─── Decode response ───────────────────────────────────────────────────────
case "$HTTP" in
  200)
    # Body sanity check: a corp proxy may return HTTP 200 with HTML
    # ("You are blocked" pages, captive portals, etc.). Without this sniff,
    # probe greenlights Cloud Agent dispatch on a misconfigured network.
    # Per review iter2 finding (probe trusts 200 unconditionally).
    if ! head -c 1 "$TMP" 2>/dev/null | grep -q '{'; then
      echo "Cursor API returned 200 with non-JSON body (likely proxy or captive portal)" >&2
      exit 44
    fi
    exit 0
    ;;
  401)
    echo "Cursor API key invalid (401)" >&2
    exit 43
    ;;
  403)
    # Content-Type sniff: if body doesn't start with `{`, it's not JSON
    # (e.g., CloudFront WAF HTML 403). jq would fail silently — we explicit-classify
    # as 44 (parse failure) to avoid mis-classifying as plan_required.
    if ! head -c 1 "$TMP" 2>/dev/null | grep -q '{'; then
      echo "Cursor API returned 403 with non-JSON body (likely WAF/proxy)" >&2
      exit 44
    fi

    CODE=$(jq -r '.error.code // empty' "$TMP" 2>/dev/null)
    JQ_EXIT=$?
    if [ "$JQ_EXIT" -ne 0 ]; then
      echo "Cursor API returned 403 with unparseable JSON" >&2
      exit 44
    fi

    if [ "$CODE" = "plan_required" ]; then
      echo "Cursor Cloud Agent requires Pro plan (upgrade: https://cursor.com/settings/billing)" >&2
      exit 42
    else
      echo "Cursor API returned 403 (code: ${CODE:-unknown})" >&2
      exit 44
    fi
    ;;
  *)
    echo "Cursor API probe failed (HTTP $HTTP)" >&2
    exit 44
    ;;
esac
