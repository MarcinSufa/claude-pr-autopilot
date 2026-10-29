#!/usr/bin/env bash
set -u
SNIPPET="$(cd "$(dirname "$0")/../.." && pwd)/templates/settings-snippet.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check_run() {
  local name="$1" expected="$2" actual="$3" status="$4"
  if [ "$status" = "0" ] && [ "$actual" = "$expected" ]; then
    pass=$((pass+1)); echo "ok   - $name"
  else
    fail=$((fail+1)); echo "FAIL - $name (wanted '$expected' with exit 0, got '$actual' with exit $status)"
  fi
}
write_stub() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
  cat > "$target" <<'EOF'
#!/bin/sh
printf '%s\n' "$(basename "$(dirname "$(dirname "$0")")")"
EOF
  chmod +x "$target"
}

for version in 0.5.4 0.5.10; do
  for hook in enforce-spec-gate.sh check-origin-main.sh; do
    write_stub "$TMP/my home/.claude/plugins/cache/claude-pr-autopilot/pr-autopilot/$version/hooks/$hook"
  done
done
for hook in enforce-spec-gate.sh check-origin-main.sh; do
  write_stub "$TMP/plugin root/hooks/$hook"
done

commands=()
while IFS= read -r line; do
  commands+=("$line")
done < <(jq -r '.hooks[][].hooks[].command' "$SNIPPET")
if [ "${#commands[@]}" = "2" ]; then
  pass=$((pass+1)); echo "ok   - found both hook commands"
else
  fail=$((fail+1)); echo "FAIL - expected 2 hook commands, found ${#commands[@]}"
fi

index=0
for cmd in "${commands[@]}"; do
  index=$((index+1))
  case "$cmd" in
    *'<version>'*) fail=$((fail+1)); echo "FAIL - hook command $index still contains <version>" ;;
    *) pass=$((pass+1)); echo "ok   - hook command $index has no <version>" ;;
  esac

  out="$(env -u CLAUDE_PLUGIN_ROOT HOME="$TMP/my home" sh -c "$cmd" 2>&1)"
  status=$?
  check_run "cached hook command $index selects 0.5.10" "0.5.10" "$out" "$status"

  out="$(env HOME="$TMP/my home" CLAUDE_PLUGIN_ROOT="$TMP/plugin root" sh -c "$cmd" 2>&1)"
  status=$?
  check_run "root hook command $index uses CLAUDE_PLUGIN_ROOT" "plugin root" "$out" "$status"
done

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" = "0" ]
