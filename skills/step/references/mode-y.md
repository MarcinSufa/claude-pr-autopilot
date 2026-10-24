# Mode Y: Copilot SWE Agent as fixer, Claude as reviewer

Moved from `skills/step/SKILL.md`. Read this when pre-flight resolved `mode == "Y"` (`copilotSwe.mode=each-iter`); SKILL.md's Mode dispatch routes here. `PUSHBACK.md` is at the plugin root (`<skill-dir>/../../PUSHBACK.md`). `ci_checks()` is defined in SKILL.md step 5; `safeAutoMerge` is in `references/auto-merge.md`; state fields are in `references/state-schema.md`.

## Algorithm: Mode Y — prAutopilotStepModeY(prNumber)

### Mode Y loop overview

```
                       ┌─────────────────────────────────┐
                       │  /pr-autopilot:step <PR#>       │
                       │  (one tick, called by /loop)    │
                       └─────────────────┬───────────────┘
                                         │
                                         v
              Step Y.0:   pre-flight (mode-aware — SKILL.md §"Pre-flight: config validation")
                                         │
                                         v
              Step Y.0.5: mode-drift guard (`resolvedMode`, see state-schema.md)
                                         │
                                         v
              Step Y.1:   fetch PR state (same as Mode X step 1)
                                         │
                                         v
              Step Y.2:   lifecycle guard (same as Mode X step 2)
                                         │
                                         v
              Step Y.3:   branch protection guard (same as Mode X step 3)
                                         │
                                         v
              Step Y.4:   pushback-iteration cap (counter increments
                          on Claude pushback comments, NOT commits)
                                         │
                                         v
              Step Y.4.5: CI health check (NEW — mirror Mode X step 5)
                          ── if required checks failed on
                              lastHandledHeadOid (= last SWE commit
                              we reviewed) → ABORT
                          ── if any pending → CONTINUE wait
                                         │
                                         v
              Step Y.5:   trigger SWE Agent ONLY IF never triggered
                          (no @copilot mention from us in PR comments)
                          ── trigger present already → skip to Y.6
                          ── never triggered → post @copilot once,
                              set lastTriggerAt, CONTINUE wait
                                         │
                                         v
              Step Y.6:   detect SWE Agent activity since last handled
                          (new commits OR new top-level comments
                          since handledOids / handledCommentIds)
                                         │
                                         v
              Step Y.7:   classify SWE Agent output
                           ├─ refusal comment ("I cannot...") → ABORT
                           ├─ new commits → step Y.8
                           ├─ approval prose AND headRefOid unchanged
                           │   since lastTriggerAt → step Y.10
                           │   with PAUSE-by-default (see design notes)
                           ├─ approval prose AND headRefOid changed →
                           │   step Y.8 (review the new commits first)
                           └─ nothing new → idle: increment counter, save, CONTINUE wait
                                         │
                                         v
              Step Y.8:   review SWE Agent's commits against PUSHBACK.md
                          per-hunk verdict (one of):
                           ├─ APPROVE  — no concerns
                           ├─ PUSHBACK — minor concern, will be
                           │             included in re-trigger
                           └─ PAUSE    — behavior change / safety
                                         concern; terminate, notify
                                         │
                                         v
              Step Y.9:   post structured review comment with
                          per-hunk verdicts (audit trail)
                                         │
                                         v
              Step Y.10:  aggregate verdict
                           ├─ any PAUSE → PAUSE (terminate, notify,
                           │              KEEP state file)
                           ├─ all APPROVE → SUCCESS_STOP (terminate,
                           │                DELETE state file)
                           └─ any PUSHBACK → post explicit @copilot
                                             re-trigger referencing
                                             this iteration's comment,
                                             then CONTINUE
                                         │
                                         v
              Step Y.11:  save state, ScheduleWakeup(pollInterval, ...)
                          (or terminate if SUCCESS_STOP / PAUSE / ABORT)
```

### Helper functions (Mode Y)

```python
def is_refusal(body: str) -> bool:
    """True if SWE Agent declined to act."""
    return bool(re.search(r"(?i)(i cannot|i('m| am) unable|not able to|can't proceed|outside.*scope)", body))

def is_approval_prose(body: str) -> bool:
    """True if SWE Agent expressed approval without listing action items."""
    return bool(re.search(r"(?i)(lgtm|looks good|no issues|ready to merge|approved|no changes needed)", body))
```

### Step-by-step (pseudocode)

```python
# Y.0 — pre-flight (mode-aware check: SKILL.md §"Pre-flight: config validation")

# state and STATE_FILE are loaded by the outer dispatcher (### 0.5 Load state) before this function is called; `mode` is in scope from the outer pre-flight.

# JSON arrays load as lists; treat the handled-id collections as sets for O(1) membership + .update()
state.handledOids = set(state.handledOids)
state.handledCommentIds = set(state.handledCommentIds)

# v1 state file (pre-v2 schema) reaching the Mode Y path must not silently adopt Mode Y
if state.stateSchemaVersion is None:
  push_notification("ABORT", "Stale v1 state file detected. Delete ~/.pr-autopilot/<owner>-<repo>-<pr>.json to start fresh in Mode Y.")
  return  # terminate, KEEP state file so user can inspect

# Y.0.5 — mode-drift guard
if state.resolvedMode and state.resolvedMode != mode:
  push_notification(
    "ABORT",
    f"mode drifted: state={state.resolvedMode}, current config={mode}. "
    f"Either restore the original config or delete {STATE_FILE} to start fresh."
  )
  return  # terminate, KEEP state file (user must resolve)

if not state.resolvedMode:
  state.resolvedMode = mode  # first tick — persist

# Y.1 — fetch PR state (reuse Mode X step 1)
pr = gh.pr.view(pr_number, json=[
  "headRefName", "baseRefName", "headRefOid",
  "number", "state", "comments", "commits"
])

# Initialize lastHandledHeadOid on first tick if not set:
# baseline is the PR HEAD before our first @copilot trigger
if not state.lastHandledHeadOid:
  state.lastHandledHeadOid = pr.headRefOid

# Y.2 — lifecycle guard (reuse Mode X step 2)
if pr.state in {CLOSED, MERGED}:
  delete(STATE_FILE)
  push_notification(f"PR #{pr_number} {pr.state}", "loop done; state cleaned up")
  return  # terminate

# Y.3 — branch protection (reuse Mode X step 3)
if pr.headRefName in {"dev", "master", "main"}:
  push_notification("ABORT", "refusing to operate on direct dev/master/main PR")
  delete(STATE_FILE)
  return  # terminate

# Y.4 — pushback-iteration cap
# (Mode Y bounded resource is Claude's pushback count, not Claude commits —
#  Claude never commits in Mode Y. SWE Agent's pushes are limited by GitHub/Copilot
#  tier quota, not our cap.)
if len(state.commitPushbacks) >= config.fixIterationCap:
  push_notification(
    "ABORT",
    f"{config.fixIterationCap} pushback cap reached; "
    f"SWE Agent and Claude are not converging — manual review required"
  )
  return  # terminate, KEEP state (so user can inspect pushback history)

# Y.4.5 — CI health check (NEW; mirrors Mode X step 5)
checks = ci_checks(pr_number)   # defined in Mode X step 5: required checks, else all checks
any_failed = any(c.bucket == "fail" for c in checks)
any_pending = any(c.bucket == "pending" for c in checks)

if any_failed and pr.headRefOid == state.lastHandledHeadOid:
  push_notification(
    "ABORT",
    f"CI failed on SWE Agent's last commit ({pr.headRefOid[:7]}). "
    f"Investigate before continuing."
  )
  return  # terminate, KEEP state

if any_pending:
  save_state(STATE_FILE)
  schedule_wakeup(config.pollIntervalSeconds, ...)
  return  # CONTINUE — wait for CI to settle

# Y.5 — trigger SWE Agent ONLY IF never triggered
# (anti-spam fix from 2nd code review Blocker 1)
# guard: lastTriggerAt is None means we have never posted a trigger
if state.lastTriggerAt is None:
  gh.pr.comment(pr_number, body="@copilot please review and fix any issues")
  state.lastTriggerAt = now()
  save_state(STATE_FILE)
  schedule_wakeup(config.pollIntervalSeconds, ...)
  return  # waiting for SWE Agent's first response

# Y.6 — detect SWE Agent activity since last handled
swe_login = config.reviewers.copilotSwe.login  # "copilot-swe-agent"
new_commits = [
  c for c in pr.commits
  if c.author.login == swe_login
  and c.oid not in state.handledOids
]
new_comments = [
  c for c in pr.comments
  if c.author.login == swe_login
  and c.databaseId not in state.handledCommentIds
  and c.createdAt > state.lastTriggerAt
]

# Y.7 — classify SWE Agent output
if any(is_refusal(c.body) for c in new_comments):
  refused_msg = next(c.body for c in new_comments if is_refusal(c.body))
  push_notification("ABORT", f"SWE Agent refused: {refused_msg[:200]}")
  delete(STATE_FILE)
  return  # terminate

if not new_commits and not new_comments:
  state.pollTicksWithoutActivity += 1
  if state.pollTicksWithoutActivity >= config.pollTickCap:
    push_notification(
      "ABORT",
      f"SWE Agent inactive for {config.pollTickCap} ticks "
      f"after @copilot trigger; check Copilot quota / setup"
    )
    delete(STATE_FILE)
    return  # terminate

  save_state(STATE_FILE)
  schedule_wakeup(config.pollIntervalSeconds, ...)
  return  # waiting

# Reset idle counter — we have activity
state.pollTicksWithoutActivity = 0

if new_commits:
  goto Y_8_review_commits

# else: only comments, no commits
if any(is_approval_prose(c.body) for c in new_comments):
  if pr.headRefOid == state.lastHandledHeadOid:
    # SWE Agent approved without changing anything since loop start.
    # PR #127's pattern (PR body said "deliberate smells").
    # Default to PAUSE for safety (2nd code review Medium #8).
    state.handledCommentIds.update([c.databaseId for c in new_comments])
    push_notification(
      f"PR #{pr_number} PAUSED",
      f"SWE Agent approved without commits (headRefOid unchanged). "
      f"This is the 'PR body framed as deliberate' pattern — confirm manually."
    )
    save_state(STATE_FILE)
    return  # PAUSE, KEEP state
  else:
    # head changed since we last handled — someone else pushed, review what's new
    # head changed without new SWE commits in our filter — capture all unhandled commits so Y.8 tracks them
    new_commits = [c for c in pr.commits if c.oid not in state.handledOids]
    goto Y_8_review_commits

# Neither commit nor approval-prose comment — log and idle
state.handledCommentIds.update([c.databaseId for c in new_comments])
save_state(STATE_FILE)
schedule_wakeup(config.pollIntervalSeconds, ...)
return  # CONTINUE

# === Y.8 — review SWE Agent's commits against PUSHBACK.md ===
Y_8_review_commits:
verdicts = []  # list of (file, hunk_range, verdict, reason)
diff = git.diff(state.lastHandledHeadOid, pr.headRefOid)

for hunk in parse_diff_hunks(diff):
  verdict, reason = apply_pushback_rubric(hunk, rubric_file="<skill-dir>/../../PUSHBACK.md")
  # verdict in {APPROVE, PUSHBACK, PAUSE}
  verdicts.append((hunk.file, hunk.range, verdict, reason))

# Mark these commits handled BEFORE the verdict-driven actions
state.lastHandledHeadOid = pr.headRefOid
state.handledOids.update([c.oid for c in new_commits])
state.handledCommentIds.update([c.databaseId for c in new_comments])

# Y.9 — post structured review comment (audit trail on PR)
state.reviewIteration += 1  # 1-based: first review iteration is "1"
comment_body = format_verdict_comment(verdicts, iteration=state.reviewIteration)
gh.pr.comment(pr_number, body=comment_body)

# Y.10 — aggregate verdict
pause_verdicts = [v for v in verdicts if v[2] == PAUSE]
pushback_verdicts = [v for v in verdicts if v[2] == PUSHBACK]

if pause_verdicts:
  push_notification(
    f"PR #{pr_number} PAUSED",
    f"Behavior-change / safety concern: {pause_verdicts[0][3][:200]}"
  )
  save_state(STATE_FILE)  # KEEP state for user resume
  return  # PAUSE (terminate)

if not pushback_verdicts:  # all APPROVE
  # Y.9-bis — flow verification leg (v0.5.4), after reading legs and before auto-merge.
  verdict = flowVerifyLeg(pr_number, pr.baseRefName)
  if verdict.status in ("FAIL", "BLOCKED"):
    if verdict.status == "FAIL":
      gh pr comment ${pr_number} --body "${verdict.comment}"
    push_notification(f"PR #{pr_number} PAUSED",
                      f"Flow verification {verdict.status}: {verdict.reason}")
    save_state(STATE_FILE)  # KEEP state for user resume
    return  # PAUSE

  # SUCCESS_STOP → shared auto-merge gate (v0.4). Same gates as Mode X; no Mode Y
  # final-pass in v0.2. Default (no opt-in) path reproduces the old notify+delete,
  # preserving this mode's message via readySummary.
  return safeAutoMerge(
    pr_number, pr.baseRefName,
    readySummary=f"Mode Y: SWE Agent fixes APPROVED by Claude (iteration {state.reviewIteration})"
  )

# else: pushback_verdicts non-empty — re-trigger SWE Agent
# (fix from 2nd code review Blocker 2 — structured review comment alone
#  doesn't wake SWE Agent; needs explicit @copilot mention)
state.commitPushbacks.append({
  "iteration": state.reviewIteration,
  "atOid": pr.headRefOid,
  "pushbacks": [
    {"file": v[0], "range": v[1], "reason": v[3]}
    for v in pushback_verdicts
  ]
})
gh.pr.comment(
  pr_number,
  body=f"@copilot please address the pushback items in the review above (iteration {state.reviewIteration})"
)
state.lastTriggerAt = now()

# Y.11 — save state, schedule next tick
save_state(STATE_FILE)
schedule_wakeup(config.pollIntervalSeconds, ...)
return  # CONTINUE
```

### Mode Y design notes

**Why no final-pass in Mode Y v0.2** (resolves Blocker 5): Mode X step 9a runs final-pass reviewers (claudeSelf, Codex, Copilot Code Review) after primary success. Adding final-pass to Mode Y SUCCESS_STOP creates a multi-reviewer orchestration problem (PUSHBACK rubric applied to commits vs threads, different success signals to aggregate). Defer to v0.3 alongside the auto-trigger work — v0.3 owns reviewer-orchestration improvements.

**Why pushback counter, not commit counter:** SWE Agent's pushes count against ITS own iteration cap (managed by GitHub/Copilot tier limits), not Claude's. Claude's bounded resource in Mode Y is "how many times have I posted pushback comments" — that's what `fixIterationCap` protects against (a ping-pong loop where SWE Agent keeps pushing changes that don't address Claude's concerns). `reviewIteration` and `len(commitPushbacks)` differ by one only when the most recent review was all-APPROVE — they otherwise increment together.

**The "approval prose without commits → PAUSE-by-default" branch** (resolves Medium #8) handles the case where SWE Agent posts "LGTM" without pushing anything. PR #127 worked because the body said "deliberate smells" — without that signal, "LGTM with no changes" is too weak a signal to auto-succeed on. Default to PAUSE; user confirms manually.

**The `is_refusal` and `is_approval_prose` heuristics** are simple regex over comment body, defined in the Helper functions (Mode Y) subsection above.
