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
- **SWE Agent** posts conversational top-level comments. Triggered by `@copilot please review` mention. Works out-of-box on most repos with Copilot installed. Cannot do line-level fixes; gives prose feedback only.
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

**Backwards-compat:** Mode X reads/writes `threadPushbacks` (renamed from `pushbackReplies`); the migration writes both keys for one release if v1 state is detected, then `pushbackReplies` is dropped in v0.3.

**Migration decision:** v1 state files (no `stateSchemaVersion` field) are treated as Mode X; if the current derived mode is Y, ABORT with a message telling the user to delete the stale state file to start fresh in Mode Y.

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
pushback_thread_ids = state.pushbackReplies | jq 'map(.threadId)'
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
        gh pr comment ${prNumber} --body "@copilot please review this PR — primary reviewers scored it ready"
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
  appendPushbackReplies(state, triage_result)
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
