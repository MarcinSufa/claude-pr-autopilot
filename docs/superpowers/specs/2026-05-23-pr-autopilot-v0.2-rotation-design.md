# pr-autopilot v0.2 — Two-Mode Rotation Design

**Date:** 2026-05-23
**Status:** Approved for implementation (revised after 2nd code review pass)
**Author:** Marcin Sufa + Claude (with two independent review passes)
**Branch:** `feature/v0.2-rotation`
**Supersedes (partially):** `docs/DESIGN.md` Mode-X-only assumptions; `EVAL.md` "v0.2 follow-up required" note

## Why this exists

v0.1.0 testing on `MarcinSufa/exo-vault` PRs #127 + #128 surfaced an architectural insight the original spec didn't account for: **Copilot has two products** that look similar but have different roles.

| | Copilot Code Review | Copilot SWE Agent (Coding Agent) |
|---|---|---|
| Trigger | `gh api ... requested_reviewers -f 'reviewers[]=Copilot'` | `@copilot please review` mention |
| Role | Reviewer only — posts threaded comments | **Reviewer AND fixer** — applies fixes + pushes commits + adds tests |
| Output | Line-level threads + summary | Top-level conversational comment + committed code changes |

v0.1.0 spec assumed one rotation: reviewer scores → Claude fixes → reviewer re-scores. **SWE Agent collapses both roles** — it fixes the code itself, leaving Claude's "fixer" job redundant. This drives two rotation modes:

- **Mode X** — external agent reviews, Claude fixes (original v0.1.0 design)
- **Mode Y** — external agent (SWE Agent) fixes, Claude reviews against PUSHBACK.md (validated empirically on PR #128, not yet codified)

v0.2's scope is to codify Mode Y as first-class alongside Mode X, fix the pre-flight gate that currently rejects Mode Y configs, and update the reviewer-triage documentation. **No auto-trigger, no auto-merge, no final-pass in Mode Y** — those land in v0.3 and v0.4 (see Version plan).

## Version plan

| Release | Scope | Gate to release |
|---|---|---|
| **v0.2.0** (this spec) | Two-mode rotation; pre-flight fix; mode derivation; REVIEW-TRIAGE-COPY.md Mode Y section; doc reconciliation | Spec implemented, manual smoke-test on one Mode X PR + one Mode Y PR. Feature release, not stability claim. |
| **v0.2.x** (errata) | Bug fixes from real-PR usage | Per-issue; no scenario gate |
| **v1.0.0** (stability gate) | No new features; declares the manual API stable | EVAL scenarios **1, 4, 8, 11, 17Y, 22, 23, 24** all PASS on real `exo-vault` PRs (1 and 17Y validated on Mode X and Mode Y respectively; 22-24 are new for v0.2) |
| **v0.3.0** (separate spec) | Auto-trigger | PostToolUse hook on `gh pr create`; `/pr-autopilot:install` + `/pr-autopilot:allow` slash commands; allowlist; draft-PR handling; `PR_AUTOPILOT_DISABLE` env var; **Mode Y final-pass reviewers** (deferred from v0.2) |
| **v0.4.0** (separate spec) | Safe auto-merge | Terminal handoff with `neverMergeToBranches` guard; `gh pr merge --auto` to dev only; state-file cleanup; queued-merge notification; handoff doc for `/land-and-deploy` |

**Semver decision (resolves Blocker 6 from 2nd review):** v0.2.0 is a feature release (minor bump). v1.0.0 is the stability gate that requires Phase 1 scenarios AND the new Mode Y scenarios to pass on real PRs. ROADMAP.md's "v1.0.0 = manual loop proven on 10 real PRs" claim is updated to reflect this expanded gate set.

## Non-goals for v0.2

- Auto-trigger of any kind (deferred to v0.3 spec)
- Auto-merge of any kind (deferred to v0.4 spec)
- **Mode Y final-pass reviewers** — Mode Y SUCCESS_STOP terminates without running `claudeSelf`/Codex/Copilot final-pass; that orchestration moves to v0.3 (deferred per 2nd code review Blocker 5)
- Cursor-native runtime port (ROADMAP's original v0.2 — re-prioritized; see Reconciliation)
- Hybrid mode where both Claude AND SWE Agent fix concurrently (research item, no version target)
- Multi-PR concurrent loops

## Mode X — recap (unchanged behavior from v0.1.0)

| Aspect | Mode X |
|---|---|
| Primary fixer | Claude |
| Primary reviewer | One of: `cursor`, `copilot` (Code Review), `codex` |
| Loop tick (post-push) | Reviewer scores → if pass, SUCCESS_STOP → else triage threads → Claude applies fixes → push → wait for re-review |
| Success signal | Configured score regex matched OR zero unresolved threads (per reviewer) |
| Fix-iteration counter | Increments on Claude's pushes |
| Existing algorithm | `skills/step/SKILL.md` steps 1-11.5 — no semantic change |

Mode X covers the standard "human-style code review where someone else writes the fixes." No spec changes here other than dispatch wiring.

## Mode Y — algorithm (NEW — codifies the empirical PR #128 walkthrough)

### Mode Y loop overview

```
                       ┌─────────────────────────────────┐
                       │  /pr-autopilot:step <PR#>       │
                       │  (one tick, called by /loop)    │
                       └─────────────────┬───────────────┘
                                         │
                                         v
              Step Y.0:   pre-flight (mode-aware — see §"Pre-flight fix")
                                         │
                                         v
              Step Y.0.5: mode-drift guard (see §"State schema")
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
                           │   with PAUSE-by-default (see §note)
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
# Y.0 — pre-flight (see §"Pre-flight fix" below for mode-aware check)

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
  "number", "state", "comments", "commits",
  "statusCheckRollup"
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
#  Claude never commits in Mode Y. SWE Agent's pushes are limited by Copilot
#  tier quota, not our cap.)
if len(state.commitPushbacks) >= config.fixIterationCap:
  push_notification(
    "ABORT",
    f"{config.fixIterationCap} pushback cap reached; "
    f"SWE Agent and Claude are not converging — manual review required"
  )
  return  # terminate, KEEP state (so user can inspect pushback history)

# Y.4.5 — CI health check (NEW; mirrors Mode X step 5)
required_checks = [c for c in pr.statusCheckRollup if c.isRequired]
any_failed = any(c.conclusion == "FAILURE" for c in required_checks)
any_pending = any(c.state in {"QUEUED", "IN_PROGRESS", "PENDING"} for c in required_checks)

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
  verdict, reason = apply_pushback_rubric(hunk, rubric_file="PUSHBACK.md")
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
  push_notification(
    f"PR #{pr_number} ready",
    f"Mode Y: SWE Agent fixes APPROVED by Claude (iteration {state.reviewIteration})"
  )
  delete(STATE_FILE)
  return  # SUCCESS_STOP (terminate, no Mode Y final-pass in v0.2)

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

**The `is_refusal` and `is_approval_prose` heuristics** are simple regex over comment body, defined in the Helper functions (Mode Y) subsection above; simple regex over the comment body.

## Pre-flight fix (resolves Blocker 2 from 1st code review)

Current `SKILL.md:74`:
```
if NOT any(r.enabledForEachIter for r in {cursor, copilot, codex}):
  PushNotification("config error", "no per-iter reviewer enabled; nothing would drive the loop")
  return  # terminate
```

**Problem:** `copilotSwe` is excluded from the set. Mode Y with `copilotSwe.mode=each-iter` and no other per-iter reviewer would ABORT on tick 1.

**Replacement — mode-aware pre-flight:**

```python
# Detect mode (see §"Mode derivation rules" below)
mode = derive_mode(config)

if mode == ABORT_CONFIG:
  push_notification("config error", "no valid Mode X or Mode Y configuration; see settings")
  return  # terminate

if mode == "X":
  if not any(getattr(r, "enabledForEachIter", False)
             for r in [config.reviewers.cursor,
                       config.reviewers.copilot,
                       config.reviewers.codex]):
    push_notification(
      "config error",
      "Mode X requires at least one per-iter reviewer in {cursor, copilot, codex}"
    )
    return  # terminate

if mode == "Y":
  if config.reviewers.copilotSwe.mode != "each-iter":
    push_notification("config error", "Mode Y requires copilotSwe.mode=each-iter")
    return  # terminate
```

## Mode derivation rules (resolves Blocker 3 from 1st code review + Medium #9 from 2nd)

`prAutopilot.primaryFixer` (new setting, default `"auto"`):

| `primaryFixer` | Resolved mode | Notes |
|---|---|---|
| `"claude"` | X | ABORT if `copilotSwe.mode == "each-iter"` (would conflict — see rule below). Otherwise standard Mode X. |
| `"copilotSwe"` | Y | Force Mode Y; ABORT if `copilotSwe.mode != "each-iter"`. |
| `"auto"` (default) | derived | Inspect reviewer config — see rules below. |

**`primaryFixer="claude"` + `copilotSwe.mode="each-iter"` rule (NEW per Medium #9):** ABORT with message — "primaryFixer=claude conflicts with copilotSwe.mode=each-iter. Either set copilotSwe.mode=off (or final-only) or change primaryFixer to copilotSwe or auto." Same reasoning as `auto` case 3 below: silently ignoring a reviewer config wastes user's paid quota.

**`auto` resolution rules** (first match wins):

1. If `copilotSwe.mode == "each-iter"` AND `cursor.enabled == false` AND `copilot.mode != "each-iter"` AND `codex.mode != "each-iter"` → **Mode Y**
2. Else if any of {`cursor.enabled`, `copilot.mode == "each-iter"`, `codex.mode == "each-iter"`} AND `copilotSwe.mode != "each-iter"` → **Mode X**
3. Else if BOTH a per-iter reviewer AND `copilotSwe.mode == "each-iter"` are enabled → **ABORT** with message: "ambiguous fixer config. Set `primaryFixer` to 'claude' or 'copilotSwe' explicitly to resolve."
4. Else (no per-iter anything) → **ABORT** with message: "no per-iter reviewer or fixer enabled; nothing would drive the loop"

## State schema (resolves Blocker 4 from 2nd code review)

```json
{
  "stateSchemaVersion": 2,
  "prNumber": 0,
  "repo": "<owner>/<name>",
  "headRef": "<branch>",
  "resolvedMode": "X" | "Y",
  "createdAt": "<iso>",
  "updatedAt": "<iso>",

  "fixIterations": 0,
  "pollTicksWithoutReview": 0,
  "pollTicksWithoutActivity": 0,
  "ticksWithoutProgress": 0,
  "lastHandledHeadOid": "<sha>",
  "lastSeenReviewId": "<gh-review-id>",
  "lastTriggerAt": "<iso>",

  "threadPushbacks": [
    {"threadId": "<id>", "iteration": 0, "reason": "..."}
  ],

  "commitPushbacks": [
    {
      "iteration": 1,
      "atOid": "<sha>",
      "pushbacks": [{"file": "...", "range": "...", "reason": "..."}]
    }
  ],

  "handledOids": ["<sha>", "..."],
  "handledCommentIds": [123456],
  "reviewIteration": 0
}
```

**Key changes from v0.1 state:**

- `stateSchemaVersion: 2` — bumped from implicit v1 (no field). Migration: state files without `stateSchemaVersion` are treated as v1 (Mode X) and require fresh start if user switches to Mode Y.
- `resolvedMode` — persisted on first tick; mode-drift guard (Y.0.5) aborts if config-derived mode differs from stored mode.
- `pushbackReplies` (v0.1) → **split into** `threadPushbacks` (Mode X, was Mode X-only in practice anyway) and `commitPushbacks` (Mode Y new).
- `handledOids`, `handledCommentIds`, `lastTriggerAt`, `pollTicksWithoutActivity`, `reviewIteration` — all Mode Y additions.
- `handledOids` and `handledCommentIds` persist as JSON arrays but are loaded into sets at runtime (see Y.0 set-conversion lines).

**Backwards-compat:** Mode X reads/writes `threadPushbacks` (renamed from `pushbackReplies`); the migration writes both keys for one release if v1 state is detected, then `pushbackReplies` is dropped in v0.3.

## REVIEW-TRIAGE-COPY.md changes

Add a new top-level section: **"Mode Y triage — reviewing SWE Agent commits"** (the existing file assumes Mode X — thread-and-comment input).

Minimum content for the Mode Y section:

- **Inputs:** `headOid`, `baseRef`, list of SWE Agent commits since `lastHandledHeadOid`
- **Per-hunk decision:** for each hunk in the diff, apply PUSHBACK.md rubric — APPROVE / PUSHBACK / PAUSE
- **Outputs:** structured `gh pr comment` body with per-change verdict + aggregate verdict
- **When to skip thread fetch:** ALWAYS in Mode Y. SWE Agent doesn't post threads on the lines it changes; it pushes commits. Fetching reviewer threads would just pull stale Mode X data if the PR previously ran in Mode X.

Example output comment template:

```markdown
## pr-autopilot Mode Y review — iteration {N}

Reviewed SWE Agent commit `{shortSha}` ({M} hunks):

- ✅ APPROVE — `path/to/file.ts:12-18` — typo fix
- ✅ APPROVE — `path/to/file.ts:42-50` — return-type annotation
- ⚠ PUSHBACK — `path/to/file.ts:88-95` — error message lost the {field} value, breaking the debug trail
- 🛑 PAUSE — `path/to/file.ts:120-128` — `age > 18` → `age >= 18` is a behavior change. Eligibility cutoff requires human confirmation.

**Aggregate:** PAUSE (1 behavior-change concern)
```

## PUSHBACK.md audit (NEW per 2nd review Medium #11)

PUSHBACK.md was written from Mode X perspective ("when to push back on a reviewer's comment"). Some rules don't translate cleanly to Mode Y ("when to push back on someone else's commit"). v0.2 implementation must include an audit pass:

- Read PUSHBACK.md rule-by-rule
- For each rule, add a Mode Y example (or note "Mode X only")
- New rules unique to Mode Y (the obvious one: "behavior-change without intent signal" → PAUSE) get explicit entries
- Cross-reference from SKILL.md Mode Y section to specific PUSHBACK.md rules

## Reconciliation appendix — docs to update for v0.2

| File | Current state | v0.2 change |
|---|---|---|
| `skills/step/SKILL.md` (general) | Mode X only, pre-flight excludes `copilotSwe` | Add Mode Y algorithm (steps Y.0-Y.11); replace pre-flight with mode-aware check; add `primaryFixer` + `derive_mode` block; update state schema for v2 |
| `skills/step/SKILL.md:68` | "Cannot do line-level fixes; gives prose feedback only" (about SWE Agent) | Replace with: "SWE Agent CAN apply line-level fixes via commits; the 'prose only' description applied to early Copilot Code Review behavior" — empirical verification on PR #128 |
| `skills/step/SKILL.md:309` | Final-pass for `copilot` triggers via `@copilot please review` mention | Replace with `gh api ... requested_reviewers` API call (the `@copilot` mention triggers SWE Agent, NOT Code Review — internal contradiction with SKILL.md:67) |
| `REVIEW-TRIAGE-COPY.md` | Thread-and-comment triage only | Add "Mode Y triage" section per outline above |
| `PUSHBACK.md` | Mode X (review-thread) examples only | Add Mode Y (commit-hunk) examples; new rule for behavior-change PAUSE |
| `EVAL.md` | Notes "v0.2 follow-up required: rewrite SKILL.md to first-class both rotation modes" | Mark resolved; rename Scenario 17 → 17Y; add scenarios 22, 23, 24 to gating set |
| `ROADMAP.md` | Says v0.2 = Cursor-native runtime port; anti-roadmap "Automatic merge after 5/5" | Rewrite v0.2 entry = "Two-mode rotation"; move Cursor port to "Future" or v0.5; keep anti-roadmap for production-bound merges (v0.4 only merges to dev with explicit guard) |
| `SHIP-INTEGRATION.md` | Says Stop hook + `PR_AUTOPILOT_DISABLE=1` planned in "v0.2+" | Update "v0.2+ planned behavior" → "v0.3+ planned behavior"; clarify Stop vs PostToolUse hook decided in v0.3 spec |
| `reviewers/COPILOT-SETUP.md` | Line 24 says `@copilot please review` triggers Code Review (contradicts SKILL.md:67) | Fix lines 24-27 — `@copilot` mention triggers SWE Agent; Code Review uses `requested_reviewers` API. Cross-reference SKILL.md table. |
| `README.md` | Mentions Mode X workflow only | Add 2-3 sentence overview of Mode X vs Mode Y + when to use each |
| `docs/DESIGN.md` | 985-line single-source-of-truth pre-v0.2 | Add a stub at the top: "PARTIALLY SUPERSEDED by `docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md` for Mode Y/rotation; sections on auto-trigger and auto-merge remain canonical until v0.3/v0.4 specs land" |
| `.claude-plugin/plugin.json` | `"version": "0.1.0"` | Bump to `"0.2.0"` after implementation completes |

## Deliverables checklist for v0.2 implementation plan

**Code/spec files to modify (12):**

- [ ] `skills/step/SKILL.md` — replace pre-flight, add Mode Y algorithm + `derive_mode`, update state schema doc, fix L68 + L309
- [ ] `REVIEW-TRIAGE-COPY.md` — append Mode Y triage section
- [ ] `PUSHBACK.md` — audit rules, add Mode Y examples, add behavior-change PAUSE rule
- [ ] `ROADMAP.md` — rewrite v0.2 entry, move Cursor port, version-numbering update
- [ ] `SHIP-INTEGRATION.md` — re-version v0.2 → v0.3
- [ ] `reviewers/COPILOT-SETUP.md` — fix `@copilot` mention semantics
- [ ] `README.md` — Mode X/Y overview paragraph
- [ ] `EVAL.md` — mark follow-up resolved, rename 17 → 17Y, add 22, 23, 24
- [ ] `docs/DESIGN.md` — add partial-supersession stub at top
- [ ] `.claude-plugin/plugin.json` — bump to `0.2.0`
- [ ] (new file) `docs/superpowers/plans/2026-05-23-pr-autopilot-v0.2-rotation.md` — implementation plan from writing-plans
- [ ] State-file migration logic — handle v1 state files (no `stateSchemaVersion`) gracefully

**EVAL scenarios to add (gated for v1.0.0 sign-off):**

- **Scenario 17Y — Mode Y happy path** (renamed from 17): `copilotSwe.mode=each-iter`, others off. SWE Agent fixes, Claude approves, SUCCESS_STOP. (Variant of empirically-validated PR #128.)
- **Scenario 22 — Mode Y refusal handling.** SWE Agent posts "I cannot help with this" → autopilot ABORTs cleanly with informative push notification, state file deleted.
- **Scenario 23 — Mode Y ambiguous config ABORT.** Settings: `cursor.enabled=true`, `copilotSwe.mode=each-iter`, `primaryFixer=auto`. Autopilot ABORTs at pre-flight with message asking user to set `primaryFixer` explicitly.
- **Scenario 24 — Mode Y PAUSE on behavior change.** PR with a hunk that changes user-visible behavior (e.g., comparison operator on eligibility cutoff). Autopilot PAUSEs at Y.10, state file kept, user notified.

**v1.0.0 sign-off gate** (resolves Blocker 6 from 2nd review):
Scenarios **1, 4, 8, 11, 17Y, 22, 23, 24** all PASS on real `MarcinSufa/exo-vault` PRs. Scenario 17X (Cursor each-iter as Mode X, Claude fixes) added if Marcin subscribes to Cursor Pro before v1.0.0 tag — otherwise 17X is post-1.0 work.

## Pre-merge verification matrix (resolves Medium #13)

This plugin is markdown-only; there is no test runner. These are manual verification steps to run before merging `feature/v0.2-rotation` to `main`:

| # | Check | How to verify |
|---|---|---|
| V1 | `derive_mode` truth table | Write 12 `~/.claude/settings.json` permutations (3 `primaryFixer` × 4 reviewer combos), invoke `/pr-autopilot:step` on a no-op PR, confirm log line "resolvedMode=X" or "resolvedMode=Y" or "ABORT: ambiguous" |
| V2 | State schema round-trip | Save → read → save produces identical JSON (no field reorder or default-value drift) |
| V3 | State migration from v1 | Hand-craft a v1 state file (no `stateSchemaVersion`); invoke loop; confirm graceful start-fresh or in-place upgrade (decision: start-fresh, write the migration note) |
| V4 | Pre-flight Mode Y accept | `copilotSwe.mode=each-iter, primaryFixer=auto` no longer ABORTs; PR #127's reproduction works |
| V5 | PUSHBACK audit coverage | Every rule in PUSHBACK.md has at least one Mode Y synthetic-hunk example |
| V6 | SKILL.md L68 + L309 fixed | `grep -nE "Cannot do line-level fixes\|@copilot please review.*primary reviewers scored" SKILL.md` returns nothing |

**Integration (real PRs on `MarcinSufa/exo-vault`):**

- Mode X regression — scenario 1 with `cursor.enabled=true, copilotSwe.mode=off, primaryFixer=auto` — must still work end-to-end
- Mode Y happy path — scenario 17Y
- Mode Y PAUSE — scenario 24
- Scenarios 22, 23 as defined above

## Open questions (intentionally narrow for v0.2)

1. **Mode Y comment dedup:** if Claude posts a structured review comment every iteration, the PR can accumulate many of them. Acceptable for v0.2 (audit trail is valuable); revisit in v0.3 with "edit the previous comment in place" pattern if noise becomes a problem.
2. **`is_approval_prose` heuristic confidence:** the v0.1.0 helper is regex-based. For v0.2, keep as-is; if false positives appear in real-PR testing, escalate to an LLM call in v0.3.
3. **`copilot-swe-agent` login verification:** EVAL Step 0 verified this login on PR #127; same caveat as Cursor/Copilot Code Review logins applies (GitHub bot names can change). v0.2 implementation should add a one-line check on first tick — log the actual login observed if it differs from config default.

## Out of scope for v0.2 (intentionally — see Version plan)

- Auto-trigger via PostToolUse / Stop hook (v0.3)
- `/pr-autopilot:install`, `/pr-autopilot:allow` slash commands (v0.3)
- `PR_AUTOPILOT_DISABLE` env var (v0.3)
- Draft-PR handling rules (v0.3 — orthogonal to rotation)
- **Mode Y final-pass reviewers** (v0.3 — defer per 2nd review Blocker 5)
- `neverMergeToBranches` setting (v0.4)
- `gh pr merge --auto` terminal handoff (v0.4)
- State-file cleanup on auto-merge (v0.4)
- `/land-and-deploy` chaining (v0.4 — explicit handoff in docs, no auto-invocation)
- Cursor-native runtime port (v0.5 or "Future" — re-prioritized below this v0.2 work)
