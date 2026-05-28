#!/usr/bin/env bash
# pr-autopilot v0.5.1 — bootstrap audit signal generator.
#
# Used by /pr-autopilot:review-spec --bootstrap to produce the exact ExoVault
# memory body. Centralising this in a script (not prose in SKILL.md) ensures
# the [BOOTSTRAP_FORCE] token is byte-exact + tested + grep-able, instead of
# trusting Claude to reproduce a literal string verbatim across sessions.
#
# Args:
#   $1 — spec absolute path (required)
#   $2 — "force" if --force was used (optional); any other value (or absent)
#        means enforcement guard was satisfied normally
#
# Stdout: a single line — the memory body
#   "Bootstrap review of <path> at <iso8601-utc>."
#   "[BOOTSTRAP_FORCE] Bootstrap review of <path> at <iso8601-utc>."  (when force)
#
# Stderr: short usage on missing args.
# Exit: 0 on success, 2 on usage error.

set -u

if [ "${1:-}" = "" ]; then
  echo "usage: bootstrap-force-audit.sh <spec-path> [force]" >&2
  exit 2
fi

SPEC_PATH="$1"
FORCE_MODE="${2:-}"

# ISO8601 UTC with millisecond precision when GNU date is available;
# fall back to second precision on BSD date (macOS).
ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null)
if [ -z "$ISO_TIMESTAMP" ] || echo "$ISO_TIMESTAMP" | grep -q '%3N'; then
  # BSD date doesn't support %3N — fall back to second precision
  ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

if [ "$FORCE_MODE" = "force" ]; then
  printf '[BOOTSTRAP_FORCE] Bootstrap review of %s at %s.\n' "$SPEC_PATH" "$ISO_TIMESTAMP"
else
  printf 'Bootstrap review of %s at %s.\n' "$SPEC_PATH" "$ISO_TIMESTAMP"
fi
