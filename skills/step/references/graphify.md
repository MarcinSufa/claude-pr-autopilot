# graphify advisory (v0.5.3+)

Moved from `skills/step/SKILL.md`. Read this at step 0.6a unless `config.graphify.advisory == "off"`. `_graphifyFsState` and `$GRAPHIFY_NOTICE_FLAG` are set in SKILL.md pre-flight 0.4b.

## 0.4b filesystem detection (run first)

Pure filesystem check, formerly SKILL.md pre-flight 0.4b. Run it at the start of 0.6a; `GRAPHIFY_OWNER`, `GRAPHIFY_REPO` and `GRAPHIFY_NOTICE_FLAG` are still set in SKILL.md 0.4b.

```bash
# 0.4b — graphify code knowledge graph filesystem detection (v0.5.3+)
# Pure filesystem check; NO state interaction yet (state loads in §0.5).
# (GRAPHIFY_OWNER / GRAPHIFY_REPO / GRAPHIFY_NOTICE_FLAG are cached in SKILL.md 0.4b.)
if [ -f "graphify-out/graph.json" ]; then
  _graphifyFsState="present"
elif [ -d "graphify-out" ]; then
  _graphifyFsState="broken"   # folder exists but no graph.json — last `graphify extract` failed
else
  _graphifyFsState="absent"
fi
```

## 0.6a graphify advisory dispatch (v0.5.3+)

Placed AFTER §0.6 merge-wait short-circuit so queued-merge ticks are NEVER disturbed by graphify notifications. Reads `_graphifyFsState` cached in §0.4b. Runs BEFORE Mode dispatch so both Mode X and Mode Y get a consistent `state.graphifyAvailable`.

```python
# 0.6a — graphify state + advisory (runs AFTER §0.6, BEFORE Mode dispatch)

cfg_advisory = config.graphify.advisory  # "auto" (default) | "always" | "off"

# advisory=off short-circuits at TOP — skips ALL filesystem dispatches.
# Defends advisory=off + broken folder from firing PAUSE.
if cfg_advisory == "off":
  state.graphifyAvailable = false
  goto __graphify_advisory_done__   # fall through to Mode dispatch

# advisory in {"auto", "always"} — apply filesystem state from §0.4b
case _graphifyFsState of:

  "present":
    state.graphifyAvailable = true
    # Hardened jq with type check — defends against future graphify versions emitting
    # an object {} or null for .built_at_commit (current Asistel-verified value: real SHA).
    BUILT_AT=$(jq -r 'if (.built_at_commit | type) == "string" then .built_at_commit else "" end' graphify-out/graph.json 2>/dev/null || echo "")
    state.graphifyBuiltAtCommit = "$BUILT_AT"
    # NOT used to gate behavior in v0.5.3 — persisted for v0.5.4 minimumStaleness ancestry check.

  "broken":
    # Rationale: broken folder indicates a failed prior build — the graph state is
    # indeterminate. `advisory=auto` still PAUSEs here (asymmetric vs the absent case
    # which only INFOs) because continuing the loop with unknown graph state is less
    # safe than blocking once with an actionable rebuild message. `advisory=off`
    # short-circuited above and never reaches this branch.
    state.graphifyAvailable = false
    PushNotification("PR #${prNumber} PAUSED — graphify build incomplete", "graphify-out/ exists but graph.json is missing (last `graphify extract` may have failed). Run `graphify extract . --backend deepseek` to rebuild, then re-run /pr-autopilot:step ${prNumber}.")
    saveState($STATE_FILE)
    return  # PAUSE; KEEP state

  "absent":
    state.graphifyAvailable = false
    if cfg_advisory == "always":
      PushNotification("PR #${prNumber} PAUSED — graphify required but missing", "graphify.advisory=always but no graphify-out/graph.json found. Run `/graphify .` first, then re-run /pr-autopilot:step ${prNumber}. To disable strict mode set graphify.advisory=auto in ~/.claude/settings.json.")
      saveState($STATE_FILE)
      return  # PAUSE; KEEP state
    else:  # cfg_advisory == "auto"
      # Per-repo notice flag (NOT per-PR) — uses $GRAPHIFY_NOTICE_FLAG cached in §0.4b
      if [ ! -f "$GRAPHIFY_NOTICE_FLAG" ]; then
        PushNotification("INFO: graphify recommendation", "This repo has no graphify code knowledge graph. Run `/graphify .` once for token-reduction during PR review loops. (See README §'Code knowledge graph awareness'.)")
        touch "$GRAPHIFY_NOTICE_FLAG"
      fi
      # fall through normally — loop continues

__graphify_advisory_done__:
```
