---
name: step
description: Automated PR review loop. Run /loop /pr-autopilot:step <PR#> after creating a PR; the skill fetches reviews from enabled reviewers, applies fixes or pushes back with reasoning, pushes commits, and waits for re-review. Stops when all enabled per-iteration reviewers report success (default: Cursor score 5/5 + Copilot final-pass 0 unresolved). Ten independent safety stops. Use when - "automate my PR review", "loop until merge-ready", "fix PR review comments automatically".
---

# /pr-autopilot:step <PR_NUMBER>

One iteration of the PR review→fix loop. Invoked by `/loop` (Claude Code's dynamic-mode loop driver). Returns by either:

- Calling `ScheduleWakeup(delaySeconds=90, prompt="/loop /pr-autopilot:step <PR_NUMBER>", reason="polling for reviewer re-review")` to continue the loop
- Omitting the `ScheduleWakeup` call to terminate the loop

## Required tools on user machine

- `gh` (GitHub CLI, authenticated)
- `jq` (JSON processor)
- `git`

## Configuration

Read from `~/.claude/settings.json` under `prAutopilot`. Defaults if missing:

```json
{
  "prAutopilot": {
    "pollIntervalSeconds": 90,
    "fixIterationCap": 5,
    "pollTickCap": 10,
    "stallTickCap": 6,
    "reviewers": {
      "cursor":     { "enabled": true,  "login": "cursor[bot]", "scoreRegex": "(?i)score:\\s*([1-5])" },
      "copilot":    { "mode": "final-only", "login": "copilot-pull-request-reviewer[bot]" },
      "copilotSwe": { "mode": "off", "login": "copilot-swe-agent" },
      "codex":      { "mode": "off", "postCommentsToPR": false },
      "claudeSelf": { "enabled": false, "rubricFile": "SELF-REVIEW-RUBRIC.md" }
    },
    "preCommitProfiles": {
      "exo-vault": [
        {"cmd": "pnpm run build"},
        {"cmd": "cd mcp-server && pnpm run build", "if": "git diff --name-only HEAD~1 HEAD | grep -q '^mcp-server/'"},
        {"cmd": "pnpm run lint"},
        {"cmd": "pnpm test"},
        {"cmd": "pnpm exec tsc --noEmit"}
      ],
      "default-pnpm": [{"cmd": "pnpm run typecheck"}, {"cmd": "pnpm run lint"}, {"cmd": "pnpm test"}],
      "default-npm":  [{"cmd": "npm run typecheck"},  {"cmd": "npm run lint"},  {"cmd": "npm test"}],
      "default-yarn": [{"cmd": "yarn typecheck"},     {"cmd": "yarn lint"},     {"cmd": "yarn test"}]
    }
  }
}
```

## Config → algorithm derivation

| Config field | `enabledForEachIter` | `enabledForFinal` | `requiresTrigger` | `postsThreads` | Score signal |
|---|---|---|---|---|---|
| `cursor.enabled=true` | yes | no | no (auto on push) | yes | `Score: N/5` regex |
| `copilot.mode=each-iter` | yes | no | yes (`requested_reviewers` API with `Copilot` — NOT `@copilot` mention which triggers SWE Agent) | yes | "0 unresolved threads" |
| `copilot.mode=final-only` | no | yes | yes (same API, one-shot at end) | yes | "0 unresolved threads" |
| `copilotSwe.mode=each-iter` | yes | no | yes (`gh pr comment "@copilot please review"`) | no — top-level conversational comments | Claude judgment on comment body |
| `copilotSwe.mode=final-only` | no | yes | yes (same mention, one-shot at end) | no | Claude judgment on comment body |
| `codex.mode=each-iter` | yes | no | yes (`codex review --diff`) | no | pass/fail |
| `codex.mode=final-only` | no | yes | yes (one-shot at end) | no | pass/fail |
| `claudeSelf.enabled=true` | no (final-only by design) | yes | no (internal) | no | 1-5 vs rubric |

**⚠ Important: Copilot has TWO products** — `copilot` (Copilot Code Review) and `copilotSwe` (Copilot SWE Agent). They are DIFFERENT:
- **Code Review** posts structured line-level threads. Triggered by adding `Copilot` via the requested-reviewers API (the `@copilot` mention does NOT trigger this). May require specific repo setup (rulesets or manual reviewer add) and a paid Copilot tier with Code Review enabled.
- **SWE Agent** posts conversational top-level comments. Triggered by `@copilot please review` mention. Works out-of-box on most repos with Copilot installed. Applies line-level fixes by pushing commits (verified on exo-vault PR #128 — 7 fixes + a test file). Posts a conversational top-level comment alongside the commits.
Per real-world testing (2026-05-23), SWE Agent fires more reliably on private repos. Code Review may need additional setup most users don't have. Default to `copilotSwe` if Code Review doesn't respond within 10 poll-ticks.

## Mode derivation

`prAutopilot.primaryFixer` (new setting, default `"auto"`):

| `primaryFixer` | Resolved mode | Notes |
|---|---|---|
| `"claude"` | X | ABORT if `copilotSwe.mode == "each-iter"` (would conflict — see rule below). Otherwise standard Mode X. |
| `"copilotSwe"` | Y | Force Mode Y; derive_mode returns "Y", pre-flight validates copilotSwe.mode == each-iter (ABORTs there if not). |
| `"auto"` (default) | derived | Inspect reviewer config — see rules below. |

**`primaryFixer="claude"` + `copilotSwe.mode="each-iter"` rule:** ABORT with message — "primaryFixer=claude conflicts with copilotSwe.mode=each-iter. Either set copilotSwe.mode=off (or final-only) or change primaryFixer to copilotSwe or auto." Same reasoning as `auto` case 3 below: silently ignoring a reviewer config wastes user's paid quota.

**`auto` resolution rules** (first match wins):

1. If `copilotSwe.mode == "each-iter"` AND `cursor.enabled == false` AND `copilot.mode != "each-iter"` AND `codex.mode != "each-iter"` → **Mode Y**
2. Else if any of {`cursor.enabled`, `copilot.mode == "each-iter"`, `codex.mode == "each-iter"`} AND `copilotSwe.mode != "each-iter"` → **Mode X**
3. Else if BOTH a per-iter reviewer AND `copilotSwe.mode == "each-iter"` are enabled → **ABORT** with message: "ambiguous fixer config. Set `primaryFixer` to 'claude' or 'copilotSwe' explicitly to resolve."
4. Else (no per-iter anything) → **ABORT** with message: "no per-iter reviewer or fixer enabled; nothing would drive the loop"

```python
function derive_mode(config):
  pf = config.primaryFixer  # default "auto"
  swe_each = config.reviewers.copilotSwe.mode == "each-iter"
  any_xreviewer = config.reviewers.cursor.enabled
                  or config.reviewers.copilot.mode == "each-iter"
                  or config.reviewers.codex.mode == "each-iter"

  if pf == "claude":
    if swe_each: return ABORT_CONFIG  # conflict — see message in pre-flight
    return "X"
  if pf == "copilotSwe":
    return "Y"  # pre-flight validates copilotSwe.mode == each-iter
  # pf == "auto"
  if swe_each and not any_xreviewer: return "Y"
  if any_xreviewer and not swe_each: return "X"
  if any_xreviewer and swe_each:     return ABORT_CONFIG  # ambiguous
  return ABORT_NO_DRIVER
```

## Pre-flight: config validation

```python
# Detect mode (see §"Mode derivation" above)
mode = derive_mode(config)

if mode == ABORT_CONFIG:
  # Two ABORT_CONFIG sub-cases — distinguish by primaryFixer setting:
  if config.primaryFixer == "claude":
    # claude + copilotSwe.mode=each-iter conflict
    push_notification(
      "config error",
      "primaryFixer=claude conflicts with copilotSwe.mode=each-iter. Either set copilotSwe.mode=off (or final-only) or change primaryFixer to copilotSwe or auto."
    )
  else:
    # auto with both swe_each and any_xreviewer set — ambiguous
    push_notification(
      "config error",
      "ambiguous fixer config. Set primaryFixer to 'claude' or 'copilotSwe' explicitly to resolve."
    )
  return  # terminate

if mode == ABORT_NO_DRIVER:
  push_notification("config error", "no per-iter reviewer or fixer enabled; nothing would drive the loop")
  return  # terminate

# reachable when primaryFixer=claude is forced with no per-iter reviewer enabled
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

## Algorithm: prAutopilotStep(prNumber)

### Pre-flight checks (MUST run first; ABORT cleanly on any failure)

These checks were added after a v0.1.0 dry-run surfaced silent fallthroughs when prerequisites are missing. Each check returns ABORT without `ScheduleWakeup` so the loop terminates instead of retrying a doomed iteration.

```bash
# 0.1 Required CLIs present
for cmd in gh jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    PushNotification("ABORT", "Required CLI not on PATH: $cmd. See reviewers/CURSOR-SETUP.md or README.md for install instructions.")
    return  # terminate (no ScheduleWakeup)
  fi
done

# 0.2 In a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  PushNotification("ABORT", "Not in a git repository. cd into the repo containing PR #${prNumber} before invoking /pr-autopilot:step.")
  return  # terminate
fi

# 0.3 `gh` is authenticated
if ! gh auth status >/dev/null 2>&1; then
  PushNotification("ABORT", "gh CLI not authenticated. Run: gh auth login")
  return  # terminate
fi

# 0.4 The PR actually exists in the current repo
if ! gh pr view ${prNumber} --json number >/dev/null 2>&1; then
  PushNotification("ABORT", "PR #${prNumber} not found in $(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo 'this repo'). Verify the PR number and the current working directory.")
  return  # terminate
fi
```

### 0.5 Load state

```bash
STATE_FILE="$HOME/.pr-autopilot/$(gh repo view --json owner --jq '.owner.login')-$(gh repo view --json name --jq '.name')-${prNumber}.json"
if [ -f "$STATE_FILE" ]; then state = read $STATE_FILE; else state = createNew(prNumber); fi
```

**v1→v2 state migration (run immediately after load):** if a loaded state file predates the v2 schema, map the old `pushbackReplies` key onto `threadPushbacks` so Mode X does not lose pushback history. (Mode Y handles v1 state separately — it ABORTs; see Y.0.5.)

```
if state.pushbackReplies AND NOT state.threadPushbacks:
  state.threadPushbacks = state.pushbackReplies   # carry Mode X history forward
# `pushbackReplies` is no longer written; it is dropped entirely in v0.3
```

State schema:

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

**Backwards-compat:** Mode X reads/writes `threadPushbacks` (renamed from `pushbackReplies`). When a v1 state file is loaded, the migration step in `### 0.5 Load state` maps `pushbackReplies` onto `threadPushbacks` so no history is lost; `pushbackReplies` is no longer written and is dropped entirely in v0.3.

**Migration decision:** v1 state files (no `stateSchemaVersion` field) are treated as Mode X; if the current derived mode is Y, ABORT with a message telling the user to delete the stale state file to start fresh in Mode Y.

**Mode dispatch** — after pre-flight resolves `mode` and loads state, route to the Mode Y algorithm or fall through to Mode X:

```python
# After pre-flight resolves `mode` and the mode-drift guard:
if mode == "Y":
  return prAutopilotStepModeY(prNumber)   # see "Algorithm: Mode Y" below
# else fall through to Mode X (steps 1-11.5 unchanged)
```

### 1. Fetch PR state

```
pr = gh pr view ${prNumber} --json headRefName,baseRefName,headRefOid,number,state,reviews,statusCheckRollup
```

### 2. PR lifecycle guard

```
if pr.state in {CLOSED, MERGED}:
  delete $STATE_FILE
  PushNotification("PR ${prNumber} ${pr.state}", "loop done; state cleaned up")
  return  # terminate
```

### 3. Branch protection guard

```
if pr.headRefName in {dev, master, main}:
  PushNotification("ABORT", "refusing to operate on direct dev/master/main PR")
  return  # terminate
```

### 4. Fix-iteration cap

```
if state.fixIterations >= config.fixIterationCap:
  PushNotification("ABORT", "${config.fixIterationCap} fix-iteration cap reached; manual review required")
  return  # terminate
```

### 5. CI health check

`lastHandledHeadOid` was set in step 11 of the PREVIOUS iteration right after we pushed. If current `headRefOid` still matches, no other actor pushed in between — the failed CI is from OUR push.

```
required_checks = pr.statusCheckRollup | filter where isRequired
any_failed = required_checks | any where conclusion == "FAILURE"
any_pending = required_checks | any where state in {QUEUED, IN_PROGRESS, PENDING}

if any_failed AND pr.headRefOid == state.lastHandledHeadOid:
  PushNotification("ABORT", "CI failed on our last push; investigate before continuing")
  return  # terminate

if any_pending:
  # CONTINUE — wait for CI to settle
  saveState($STATE_FILE)
  ScheduleWakeup(90s, ...)
  return  # waiting
```

### 5.5 Trigger non-auto reviewers

```
per_iter_reviewers = config.reviewers | filter where derivation.enabledForEachIter == true
for r in per_iter_reviewers:
  if r.derivation.requiresTrigger:
    case r.name:
      "copilot":
        # Copilot CODE REVIEW (line-level threaded)
        # Use the requested_reviewers API, NOT @copilot mention (mention triggers SWE Agent)
        gh api repos/${owner}/${repo}/pulls/${prNumber}/requested_reviewers \
          --method POST -f 'reviewers[]=Copilot' >/dev/null 2>&1 || true
      "copilotSwe":
        # Copilot SWE AGENT (conversational top-level comment)
        # Only post the trigger if there's no recent comment from copilot-swe-agent
        # since our last push (avoid spamming)
        latest_swe_comment_after_our_head = gh pr view ${prNumber} --json comments \
          | jq --arg sha "${state.lastHandledHeadOid}" \
              'last(.comments[] | select(.author.login == "copilot-swe-agent"))'
        if no recent SWE comment OR last comment predates our push:
          gh pr comment ${prNumber} --body "@copilot please review"
      "codex":
        codex review --diff origin/${pr.baseRefName}..HEAD --format json > /tmp/codex_review_${prNumber}.json
```

### 6. Fetch outcomes from per-iter reviewers + unresolved threads

```
outcomes = {}  # per-adapter outcome
for r in per_iter_reviewers:
  case r.name:
    "cursor":
      outcomes["cursor"] = parse cursor reviews from pr.reviews where author.login == config.reviewers.cursor.login
      outcomes["cursor"].score = jq regex match config.reviewers.cursor.scoreRegex against last review body
    "copilot":
      outcomes["copilot"].hasReviewed = (any review in pr.reviews where author.login == config.reviewers.copilot.login)
    "copilotSwe":
      # SWE Agent uses TOP-LEVEL issue comments, not PR review threads
      swe_comments = gh pr view ${prNumber} --json comments \
        | jq --arg login "${config.reviewers.copilotSwe.login}" \
            '[.comments[] | select(.author.login == $login)]'
      outcomes["copilotSwe"].hasReviewed = (swe_comments.length > 0 AND timestamp of latest comment >= our headOid push time)
      outcomes["copilotSwe"].latestCommentBody = last(swe_comments).body
      # isSuccess determined by Claude reading the comment body — see step 9
    "codex":
      outcomes["codex"].result = parse pass/fail from /tmp/codex_review_${prNumber}.json

# Unified threads fetch — only for reviewers whose adapter.postsThreads == true
github_reviewer_logins = [config.reviewers[r.name].login for r in per_iter_reviewers if r.derivation.postsThreads]

threads_raw = gh api graphql -f query='
  query($n:Int!, $r:String!, $o:String!) {
    repository(owner:$o, name:$r) {
      pullRequest(number:$n) {
        reviewThreads(first:50) {
          totalCount
          nodes {
            id isResolved
            comments(first:5) {
              nodes { databaseId body path line author { login } }
            }
          }
        }
      }
    }
  }' \
  -F n=${prNumber} -F r=${repo} -F o=${owner}

total = threads_raw | jq '.data.repository.pullRequest.reviewThreads.totalCount'
if total >= 50:
  PushNotification("PAUSE", "≥50 review threads; likely truncation, manual cleanup needed")
  return  # PAUSE (terminate without scheduling)

threads = threads_raw | jq '
  .data.repository.pullRequest.reviewThreads.nodes
  | map(select(
      .isResolved == false
      and (.comments.nodes[0].author.login as $a | $logins | index($a))
    ))' --argjson logins "${github_reviewer_logins}"
```

### 8. Poll-tick counter

```
any_reviewer_has_reviewed = any(outcomes[r.name].hasReviewed for r in per_iter_reviewers)
if NOT any_reviewer_has_reviewed:
  state.pollTicksWithoutReview++
  if state.pollTicksWithoutReview >= config.pollTickCap:
    PushNotification("ABORT", "${config.pollTickCap} poll-tick cap reached without any per-iter reviewer reviewing; check setup docs for each enabled reviewer (Cursor/Copilot/Codex)")
    return  # terminate
  saveState($STATE_FILE)
  ScheduleWakeup(90s, ...)
  return  # waiting for first review
else:
  state.pollTicksWithoutReview = 0
```

### 9. Success path (multi-reviewer aggregate)

```
pushback_thread_ids = state.threadPushbacks | jq 'map(.threadId)'
unresolved_not_ours = threads | filter where (.id NOT IN pushback_thread_ids)

# Per-reviewer isSuccess (defined per-adapter):
# - cursor:     outcomes.cursor.score == "5"
# - copilot:    count of unresolved threads where author == copilot.login == 0
# - copilotSwe: Claude reads outcomes.copilotSwe.latestCommentBody and judges whether it expresses approval
#                ("no blockers", "looks good", "ready to merge", "approved", "no issues found", etc.)
#                vs lists issues to address. NO score; pure LLM judgment of natural language.
#                If body lists actionable issues, treat each as a pseudo-thread for triage in step 10.
# - codex:      outcomes.codex.result == "pass"

all_per_iter_happy = all(adapter.isSuccess(outcomes[r.name]) for r in per_iter_reviewers)

if all_per_iter_happy AND unresolved_not_ours.length == 0:
  # 9a. Run final-pass reviewers
  final_pass_reviewers = config.reviewers | filter where derivation.enabledForFinal == true
  for r in final_pass_reviewers:
    case r.name:
      "copilot":
        gh api repos/{owner}/{repo}/pulls/${prNumber}/requested_reviewers \
          -X POST -f 'reviewers[]=Copilot'
        # NOTE: @copilot mention triggers SWE Agent, NOT Code Review (see "Copilot has TWO products")
        sleep 5 minutes (or pollInterval * 4); fetch Copilot threads
        if any unresolved Copilot thread → PAUSE
      "codex":
        codex review --diff origin/${pr.baseRefName}..HEAD --format json
        if pass → continue; if fail → PAUSE
      "claudeSelf":
        read SELF-REVIEW-RUBRIC.md (from config.reviewers.claudeSelf.rubricFile)
        read git diff origin/${pr.baseRefName}..HEAD
        emit 1-5 score against rubric; if < 5 → PAUSE

  # 9b. All clear
  PushNotification("PR #${prNumber} ready", "all reviewers green; review summary: <per-reviewer outcomes>")
  delete $STATE_FILE
  return  # SUCCESS_STOP (terminate)

# Some reviewer not happy yet — fall through to triage + fix
```

### 10. Triage (multi-login dispatch)

Invoke the routine in `REVIEW-TRIAGE-COPY.md` with:

- `threads = unresolved_not_ours`
- `reviewerLogins = github_reviewer_logins`
- `pushbackRubric = read PUSHBACK.md`
- `mode = "unattended"`

```
triage_result = invokeReviewTriage(threads, reviewerLogins, pushbackRubric, mode="unattended")

if triage_result.askUser.length > 0:
  PushNotification("PAUSE", "ambiguous review thread; user input needed: ${triage_result.askUser[0].body[:120]}")
  return  # PAUSE
```

### 11. Pre-commit verification + push

```
if triage_result.editsApplied > 0:
  # Pick the profile
  repo_basename = gh repo view --json name --jq '.name'
  profile = config.preCommitProfiles[repo_basename]
       OR config.preCommitProfiles["default-${detect_pm_from_lockfile()}"]
       OR null  # no profile → skip with warning

  if profile:
    for entry in profile:
      if entry has "if": run entry.if; skip if exit != 0
      run entry.cmd
      if exit != 0:
        PushNotification("ABORT", "pre-commit check failed: ${entry.cmd} — not pushing broken code")
        return  # ABORT

  git add -A
  git commit -m "chore(pr-autopilot): iteration ${state.fixIterations + 1} (${triage_result.editsApplied} fixes, ${triage_result.pushbacks} pushbacks)"
  git push origin ${pr.headRefName}

  state.fixIterations++
  state.lastHandledHeadOid = $(git rev-parse HEAD)
  state.ticksWithoutProgress = 0
  state.threadPushbacks.extend([
    {"threadId": t.id, "iteration": state.fixIterations, "reason": t.reason}
    for t in triage_result.pushedBackThreads
  ])
  # lastSeenReviewId updated below in 11.5
```

### 11.5 Stall guard

```
current_review_id = pr.reviews | jq 'last.id // null'
did_anything = (triage_result.editsApplied > 0) OR (triage_result.pushbacks > 0)

# Compute review_unchanged BEFORE updating lastSeenReviewId — first-tick-after-review edge case
review_unchanged = (current_review_id != null AND current_review_id == state.lastSeenReviewId)

if NOT did_anything AND review_unchanged:
  state.ticksWithoutProgress++
  if state.ticksWithoutProgress >= config.stallTickCap:
    saveState($STATE_FILE)
    PushNotification("PAUSE", "loop spinning ≥${config.stallTickCap} ticks (~9 min) with no new review and no actions taken; manual intervention needed")
    return  # PAUSE
else:
  state.ticksWithoutProgress = 0

if current_review_id != null:
  state.lastSeenReviewId = current_review_id

saveState($STATE_FILE)
```

### 12. Continue: schedule next tick

```
ScheduleWakeup(delaySeconds=config.pollIntervalSeconds,
                prompt="/loop /pr-autopilot:step ${prNumber}",
                reason="polling for reviewer re-review")
return  # loop continues
```

## Algorithm: Mode Y — prAutopilotStepModeY(prNumber)

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

## Stop conditions summary

| Condition | Step | Outcome |
|---|---|---|
| Missing CLI on PATH (gh / jq / git) | pre-flight 0.1 | ABORT |
| Not in a git repo | pre-flight 0.2 | ABORT |
| `gh` not authenticated | pre-flight 0.3 | ABORT |
| PR not found in current repo | pre-flight 0.4 | ABORT |
| Config: no per-iter reviewer enabled | pre-flight | ABORT (terminate without ScheduleWakeup) |
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

## See also

- [`PUSHBACK.md`](../../PUSHBACK.md) — judgment rubric for triage (step 10)
- [`REVIEW-TRIAGE-COPY.md`](../../REVIEW-TRIAGE-COPY.md) — multi-login fetch/classify/reply routine
- [`reviewers/CURSOR-SETUP.md`](../../reviewers/CURSOR-SETUP.md) — one-time Cursor setup
- [`reviewers/COPILOT-SETUP.md`](../../reviewers/COPILOT-SETUP.md) — Copilot adapter modes
- [`EVAL.md`](../../EVAL.md) — test scenarios + Phase 1 gating
- [`docs/DESIGN.md`](../../docs/DESIGN.md) — full architecture spec
