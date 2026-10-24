# Stop conditions summary

Moved from `skills/step/SKILL.md`. Read this when explaining to the user why the loop stopped, paused or aborted. Step numbers refer to SKILL.md (Mode X), `references/mode-y.md` (Y.*), `references/auto-merge.md` (0.6, gates) and `references/graphify.md` (0.6a).

| Condition | Step | Outcome |
|---|---|---|
| Missing CLI on PATH (gh / jq / git) | pre-flight 0.1 | ABORT |
| Not in a git repo | pre-flight 0.2 | ABORT |
| `gh` not authenticated | pre-flight 0.3 | ABORT |
| PR not found in current repo | pre-flight 0.4 | ABORT |
| Config: no driver at all — no per-iter reviewer in {cursor,copilot,codex,copilotSwe(review-score)} AND copilotSwe.mode≠each-iter | pre-flight | ABORT_NO_DRIVER (terminate without ScheduleWakeup). NB: copilotSwe.mode=each-iter IS a Mode Y driver, and copilotSwe.mode=review-score IS a Mode X reviewer — neither is an error. |
| Config: primaryFixer=claude conflicts with copilotSwe.mode=each-iter | pre-flight | ABORT |
| Config: ambiguous fixer (per-iter reviewer + copilotSwe each-iter, primaryFixer=auto) | pre-flight | ABORT |
| PR closed or merged | 2 | SUCCESS_STOP |
| PR targets dev/master/main directly | 3 | ABORT |
| `fixIterationCap` fix cap | 4 | ABORT |
| CI failed on our last push | 5 | ABORT |
| `pollTickCap` ticks without any per-iter reviewer reviewing | 8 | ABORT |
| All per-iter reviewers report success AND all final-pass reviewers agree | 9b | SUCCESS_STOP |
| ≥50 review threads (likely truncation) | 6 | PAUSE |
| Triage flagged ASK_USER | 10 | PAUSE |
| Local pre-commit suite failed | 11 | ABORT |
| `stallTickCap` ticks with same review and zero actions (stall) | 11.5 | PAUSE |
| Final-pass reviewer disagrees | 9a | PAUSE |
| Reviewers green, auto-merge gate fails (not opted-in / paused / base unsafe / not-ready / CI not green) | 9c / Y.10 (`safeAutoMerge` gates 1–5) | SUCCESS_STOP (notify "ready", manual merge) |
| Reviewers green, all auto-merge gates pass → merge queued, waiting for GitHub | 9c / Y.10 → 0.6 | CONTINUE (wait) |
| Auto-merge blocked (conflicts / `mergeStateStatus` DIRTY) | 0.6 | STOP (KEEP state) |
| Auto-merge stuck (`pollTickCap` ticks while queued) | 0.6 | STOP (KEEP state) |
| PR merged after queue | 0.6 | SUCCESS_STOP (state deleted) |
| **Graphify (v0.5.3+):** `advisory=off` AND any filesystem state | 0.6a | PASS (no notification, `state.graphifyAvailable=false`) |
| **Graphify:** `state.autoMergeQueued=true` (queued-merge wait) | 0.6 short-circuits BEFORE 0.6a | §0.6a never runs; merge wait proceeds normally |
| **Graphify:** `advisory=auto` AND `graph.json` present | 0.6a | PASS (silent, `state.graphifyAvailable=true`) |
| **Graphify:** `advisory=auto` AND `graph.json` absent (no folder) | 0.6a | INFO once per repo (notice flag), continue |
| **Graphify:** `advisory=auto` AND broken folder (cache without graph.json) | 0.6a | PAUSE (KEEP state, rebuild message) |
| **Graphify:** `advisory=always` AND `graph.json` absent | 0.6a | PAUSE (KEEP state, strict-mode message) |
| **Graphify:** `advisory=always` AND broken folder | 0.6a | PAUSE (KEEP state, rebuild message) |
