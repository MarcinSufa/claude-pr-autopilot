---
name: step
description: Automated PR review loop for a GitHub pull request. Run /loop /pr-autopilot:step <PR#> after creating a PR; each tick fetches reviews from the enabled reviewers (Cursor, Copilot, Codex, Copilot SWE agent), applies fixes or pushes back with reasoning, pushes commits, and waits for re-review. Stops when all enabled per-iteration reviewers report success (by default Cursor score 5/5 + Copilot final pass with 0 unresolved threads). Needs at least one per-iteration reviewer (Cursor, Copilot or Codex, all paid); with none it ends ABORT_NO_DRIVER. Ten independent safety stops. Use when - "automate my PR review", "loop until merge-ready", "fix PR review comments automatically", "zautomatyzuj review PR", "popraw komentarze z review", "puść pętlę aż PR będzie gotowy do merge".
argument-hint: "<PR-number>"
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
      "copilotSwe": { "mode": "off", "login": "copilot-swe-agent", "scoreRegex": "(?i)readiness:\\s*([1-5])" },
      "codex":      { "mode": "off", "postCommentsToPR": false },
      "claudeSelf": { "enabled": false, "rubricFile": "SELF-REVIEW-RUBRIC.md" }
    },
    "flowVerify": {
      "mode": "off",
      "catalog": "flows.md",
      "command": "npm run verify:flow",
      "resultsJson": "test-results-verify/results.json",
      "baseUrl": "http://localhost:3000"
    },
    "preCommitProfiles": {
      "default-pnpm": [{"cmd": "pnpm run typecheck"}, {"cmd": "pnpm run lint"}, {"cmd": "pnpm test"}],
      "default-npm":  [{"cmd": "npm run typecheck"},  {"cmd": "npm run lint"},  {"cmd": "npm test"}],
      "default-yarn": [{"cmd": "yarn typecheck"},     {"cmd": "yarn lint"},     {"cmd": "yarn test"}]
    },
    "autoMerge": {
      "allowedTargetBranches": ["dev"],
      "neverMergeToBranches": ["master", "main", "production"],
      "mergeMethod": "squash"
    }
  }
}
```

**Per-repo pre-commit profile (optional):** `preCommitProfiles` keys are repo basenames; without one, step 11 falls back to `default-<package-manager>` from the lockfile. Example with per-entry `if` conditions: `${CLAUDE_SKILL_DIR}/references/config.md`.

**Flow-verification config (v0.5.4):** `prAutopilot.flowVerify` gates a **behavioural** check on top of the review legs — reviewers read the diff, this one drives the app. `mode: "off"` (the default) skips it entirely, so repos without the harness are unaffected. `mode: "final-only"` runs it once, after every reviewer is green and before the auto-merge gate. It never starts a server and never merges on its own. See [`references/flow-verify.md`](references/flow-verify.md) and [`reviewers/FLOW-VERIFY-SETUP.md`](../../reviewers/FLOW-VERIFY-SETUP.md).

**Auto-merge config (v0.4):** `prAutopilot.autoMerge` tunes the *target* + *method* guards for `safeAutoMerge` (see `references/auto-merge.md`). Safe hardcoded defaults shown above — it works with zero config. The per-repo **opt-in itself is file-based** (`~/.pr-autopilot/automerge-repos`, separate from v0.3's `allowed-repos`); absent ⇒ auto-merge OFF everywhere; the notify-and-stop control flow is unchanged from v0.3 (the notification just adds a "merge manually" hint).

## Config → algorithm derivation

| Config field | `enabledForEachIter` | `enabledForFinal` | `requiresTrigger` | `postsThreads` | Score signal |
|---|---|---|---|---|---|
| `cursor.enabled=true` | yes | no | no (auto on push) | yes | `Score: N/5` regex |
| `copilot.mode=each-iter` | yes | no | yes (`requested_reviewers` API with `Copilot` — NOT `@copilot` mention which triggers SWE Agent) | yes | "0 unresolved threads" |
| `copilot.mode=final-only` | no | yes | yes (same API, one-shot at end) | yes | "0 unresolved threads" |
| `copilotSwe.mode=each-iter` | yes | no | yes (`gh pr comment "@copilot please review"`) | no — top-level conversational comments | Claude judgment on comment body |
| `copilotSwe.mode=review-score` | yes | no | yes (`@copilot please review` mention, **review-only**) | no — top-level conversational comment | `Readiness: N/5` regex (`scoreRegex`) |
| `copilotSwe.mode=final-only` | no | yes | yes (same mention, one-shot at end) | no | Claude judgment on comment body |
| `codex.mode=each-iter` | yes | no | yes (`codex exec review --base`) | no | pass/fail |
| `codex.mode=final-only` | no | yes | yes (one-shot at end) | no | pass/fail |
| `claudeSelf.enabled=true` | no (final-only by design) | yes | no (internal) | no | 1-5 vs rubric |
| `flowVerify.mode=final-only` | no (too slow for every iter) | yes | no (internal) | no | `results.json` counters, NOT the exit code |

Copilot has two products (Code Review = `copilot`, SWE Agent = `copilotSwe`) and SWE Agent has two roles (`each-iter` fixer vs `review-score` reviewer). Read `${CLAUDE_SKILL_DIR}/references/config.md` when choosing or explaining reviewer config. If Copilot Code Review does not respond within 10 poll ticks, suggest `copilotSwe` instead.

## Mode derivation

`prAutopilot.primaryFixer` (new setting, default `"auto"`):

| `primaryFixer` | Resolved mode | Notes |
|---|---|---|
| `"claude"` | X | ABORT if `copilotSwe.mode == "each-iter"` (would conflict — see `references/config.md`). Otherwise standard Mode X. |
| `"copilotSwe"` | Y | Force Mode Y; derive_mode returns "Y", pre-flight validates copilotSwe.mode == each-iter (ABORTs there if not). |
| `"auto"` (default) | derived | Inspect reviewer config — `derive_mode()` below. |

The prose form of these rules (including the `primaryFixer="claude"` + `each-iter` conflict) is in `${CLAUDE_SKILL_DIR}/references/config.md`; `derive_mode()` below is authoritative.

```python
function derive_mode(config):
  pf = config.primaryFixer  # default "auto"
  swe_each = config.reviewers.copilotSwe.mode == "each-iter"  # Mode Y fixer ONLY
  any_xreviewer = config.reviewers.cursor.enabled
                  or config.reviewers.copilot.mode == "each-iter"
                  or config.reviewers.codex.mode == "each-iter"
                  or config.reviewers.copilotSwe.mode == "review-score"  # SWE Agent as scoring reviewer (Mode X)

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
mode = derive_mode(config)
if mode == ABORT_NO_DRIVER:
  push_notification("config error", "no per-iter reviewer or fixer enabled; nothing would drive the loop")
  return  # terminate (no ScheduleWakeup)
if mode == ABORT_CONFIG
   or (mode == "X" and no reviewer in {cursor, copilot, codex, copilotSwe(review-score)} has enabledForEachIter)
   or (mode == "Y" and config.reviewers.copilotSwe.mode != "each-iter"):
  # exact config-error messages for each case: ${CLAUDE_SKILL_DIR}/references/config.md §"Pre-flight config errors"
  push_notification("config error", <message for that case>)
  return  # terminate
```

## Algorithm: prAutopilotStep(prNumber)

### Pre-flight checks (MUST run first; ABORT cleanly on any failure)

These checks were added after a v0.1.0 dry-run surfaced silent fallthroughs when prerequisites are missing. Each check returns ABORT without `ScheduleWakeup` so the loop terminates instead of retrying a doomed iteration.

```bash
# 0.1 Required CLIs present
for cmd in gh jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    PushNotification("ABORT", "Required CLI not on PATH: $cmd. See README.md in the pr-autopilot plugin for install instructions.")
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

# 0.4b — cache owner/repo for §0.5 STATE_FILE and the graphify notice flag (§0.6a);
# avoids triple `gh repo view` per tick. The graphify filesystem check is in references/graphify.md.
GRAPHIFY_OWNER=$(gh repo view --json owner --jq '.owner.login')
GRAPHIFY_REPO=$(gh repo view --json name --jq '.name')
GRAPHIFY_NOTICE_FLAG="$HOME/.pr-autopilot/${GRAPHIFY_OWNER}-${GRAPHIFY_REPO}-graphify-notice.flag"
```

### 0.5 Load state

```bash
# Reuse cached GRAPHIFY_OWNER / GRAPHIFY_REPO from §0.4b (DRY — avoids extra `gh repo view` calls)
STATE_FILE="$HOME/.pr-autopilot/${GRAPHIFY_OWNER}-${GRAPHIFY_REPO}-${prNumber}.json"
if [ -f "$STATE_FILE" ]; then state = read $STATE_FILE; else state = createNew(prNumber); fi
```

**Auto-trigger provenance:** When this step was reached because the auto-trigger hook nudged you (the invoking prompt is `/loop /pr-autopilot:step <N>` originating from the hook's `additionalContext`, not a manual user invocation), set on the new state: `"autoTriggered": true, "triggerSource": "posttooluse-hook"`. For manual invocations, set `"autoTriggered": false`. This is informational only (telemetry / debugging) and does not change loop behavior.

#### State schema

Current `stateSchemaVersion` is 4. If the loaded file has an older or missing `stateSchemaVersion`, apply the v1→v2 migration in `${CLAUDE_SKILL_DIR}/references/state-schema.md` right after loading. Read the same file when creating a new state file, migrating an older one, or when unsure what a field means. v2/v3 files load additively (missing fields default); a v1 file (no `stateSchemaVersion`) is treated as Mode X, and Mode Y ABORTs on it (Y.0).

### 0.6 Merge-wait short-circuit (v0.4 — runs BEFORE Mode dispatch)

If `state.autoMergeQueued == true`, read `${CLAUDE_SKILL_DIR}/references/auto-merge.md` §"0.6 Merge-wait short-circuit" and follow it. It always returns (wait, stop or done) and never falls through to 0.6a or Mode dispatch.

### 0.6a graphify advisory dispatch (v0.5.3+)

If `config.graphify.advisory == "off"`: set `state.graphifyAvailable = false` and continue. Otherwise (`"auto"`, the default, or `"always"`) read `${CLAUDE_SKILL_DIR}/references/graphify.md` and follow it; it may PAUSE.

**Mode dispatch** — after pre-flight resolves `mode` and loads state, route to the Mode Y algorithm or fall through to Mode X:

```python
# After pre-flight resolves `mode`, the mode-drift guard, AND step 0.6:
if mode == "Y":
  return prAutopilotStepModeY(prNumber)   # read ${CLAUDE_SKILL_DIR}/references/mode-y.md
# else fall through to Mode X (steps 1-11.5 unchanged)
```

### 1. Fetch PR state

```
pr = gh pr view ${prNumber} --json headRefName,baseRefName,headRefOid,number,state,reviews
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

`gh pr view --json statusCheckRollup` has no `isRequired` field, so the check list comes from `gh pr checks`, which can filter to required checks itself. `ci_checks()` is reused by Y.4.5 and auto-merge Gate 5:

```
def ci_checks(prNumber):
  r = run("gh pr checks ${prNumber} --required --json name,state,bucket")
  # exit 0 = all required checks finished; exit 8 = some still pending (JSON is still printed)
  if r.exit == 1 AND r.stderr matches "no required checks reported":
    # repo has no required checks (no branch protection / rulesets) → use ALL checks
    r = run("gh pr checks ${prNumber} --json name,state,bucket")
  if r.exit == 1 AND r.stderr matches "no checks reported":
    return []          # no CI configured on this PR
  return parse_json(r.stdout)   # [{name, state, bucket}], bucket ∈ {pass, fail, pending, skipping, cancel}

checks = ci_checks(prNumber)
any_failed = checks | any where bucket == "fail"
any_pending = checks | any where bucket == "pending"

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
          # review-score mode: review ONLY (Claude fixes) + emit a parseable 1-5 score.
          # (In Mode X, copilotSwe in per_iter_reviewers always means review-score —
          #  each-iter is the Mode Y fixer, handled in its own flow.)
          gh pr comment ${prNumber} --body $'@copilot please review this PR. Review ONLY — do NOT push code changes.\n\nList any blocking issues, then end with a line in EXACTLY this format:\n\nReadiness: X/5\n\nwhere 1 = not mergeable and 5 = ready to merge.'
      "codex":
        # codex-cli ≥0.159: `review` takes --base/--commit/--uncommitted (no --diff, no --format);
        # `codex exec review` adds -o/--output-last-message for the final review text.
        codex exec review --base origin/${pr.baseRefName} \
          -o "${TMPDIR:-/tmp}/codex_review_${prNumber}.md" > /dev/null
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
      if config.reviewers.copilotSwe.mode == "review-score":
        # Parse the structured verdict, same as cursor — gate on score, not LLM judgment.
        outcomes["copilotSwe"].score = regex match config.reviewers.copilotSwe.scoreRegex against latestCommentBody
      # else (each-iter/final-only): isSuccess determined by Claude reading the comment body — see step 9
    "codex":
      # Read the review text; "pass" = Codex reports no actionable (P0/P1) findings, else "fail".
      outcomes["codex"].result = judge pass/fail from "${TMPDIR:-/tmp}/codex_review_${prNumber}.md"

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

There is no step 7: the numbering has skipped it since v0.1 and is kept so the stop-condition table, EVAL.md and docs that cite steps 8–12 stay valid.

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
# - copilotSwe (review-score): outcomes.copilotSwe.score == "5". Review-only; Claude is the fixer.
#                If score < 5 (or score missing — re-trigger next tick), treat the issues listed
#                in the comment body as pseudo-threads for triage in step 10, same as below.
# - copilotSwe (each-iter/final-only): Claude reads outcomes.copilotSwe.latestCommentBody and judges whether it expresses approval
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
        codex exec review --base origin/${pr.baseRefName} \
          -o "${TMPDIR:-/tmp}/codex_final_${prNumber}.md" > /dev/null
        if the review text reports no actionable (P0/P1) findings → continue; else → PAUSE
      "claudeSelf":
        read ${CLAUDE_SKILL_DIR}/../../SELF-REVIEW-RUBRIC.md (config.reviewers.claudeSelf.rubricFile, relative to the plugin root)
        read git diff origin/${pr.baseRefName}..HEAD
        emit 1-5 score against rubric; if < 5 → PAUSE

  # 9a-bis. Flow verification leg (v0.5.4) — behavioural, runs AFTER the reading
  #         reviewers and BEFORE the auto-merge gate. Every reviewer above reads
  #         the diff; this one drives the running app. The helper is defined in `references/flow-verify.md`.
  verdict = flowVerifyLeg(prNumber, pr.baseRefName)
  if verdict.status == "FAIL":
    gh pr comment ${prNumber} --body "${verdict.comment}"
    PushNotification("PAUSE", "flow verification failed: ${verdict.failedFlows}")
    return  # PAUSE — never merge over a red behavioural check
  if verdict.status == "BLOCKED":
    PushNotification("PAUSE", "flow verification could not run: ${verdict.reason}")
    return  # PAUSE — a check that did not run is not a check that passed
  # "SKIPPED" (mode off, or repo has no harness) and "PASS" both fall through.

  # 9b. All final-pass reviewers clear.
  # 9c. SUCCESS_STOP → hand off to the shared auto-merge gate (v0.4).
  #     With no opt-in (the default), safeAutoMerge's Gate 1 keeps the old
  #     notify-ready + delete-state control flow (the message adds a "merge
  #     manually" hint). readySummary preserves this mode's existing message.
  return safeAutoMerge(prNumber, pr.baseRefName,
                       readySummary="all reviewers green; review summary: <per-reviewer outcomes>")

# Some reviewer not happy yet — fall through to triage + fix
```

### 10. Triage (multi-login dispatch)

**Graphify preamble (v0.5.3+):** If `state.graphifyAvailable == true` AND `config.graphify.promptHint == true` (default), apply this reasoning rule BEFORE invoking review triage:

> Before judging reviewer comments about symbol X, query `graphify explain "X"` to see X's connections/community. Use `graphify path "X" "Y"` for dependency-validity questions. Only `Read` source files when graphify returns insufficient context.

Invoke the routine in `${CLAUDE_SKILL_DIR}/../../REVIEW-TRIAGE-COPY.md` with:

- `threads = unresolved_not_ours`
- `reviewerLogins = github_reviewer_logins`
- `pushbackRubric = read ${CLAUDE_SKILL_DIR}/../../PUSHBACK.md`
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

## Algorithm: Mode Y and auto-merge

In `references/*.md`, `<skill-dir>` means `${CLAUDE_SKILL_DIR}` (so the plugin root is `${CLAUDE_SKILL_DIR}/../..`).

- **Mode Y** (`mode == "Y"`): read `${CLAUDE_SKILL_DIR}/references/mode-y.md` and run `prAutopilotStepModeY(prNumber)` from there.
- **`safeAutoMerge(prNumber, baseRef, readySummary)`** (SUCCESS_STOP in step 9c and Y.10): read `${CLAUDE_SKILL_DIR}/references/auto-merge.md` and apply its six gates. With no opt-in (the default) it notifies "ready", deletes state and stops.
- **Why did it stop?** The full stop-condition table is in `${CLAUDE_SKILL_DIR}/references/stop-conditions.md`.
- **`flowVerifyLeg(prNumber, baseRef)`** (Mode X step 9a-bis and Mode Y Y.9-bis): read `${CLAUDE_SKILL_DIR}/references/flow-verify.md`. Mode off or no harness means SKIPPED; never merges, never starts a server.

## See also

- [`PUSHBACK.md`](../../PUSHBACK.md) — judgment rubric for triage (step 10)
- [`REVIEW-TRIAGE-COPY.md`](../../REVIEW-TRIAGE-COPY.md) — multi-login fetch/classify/reply routine
- [`reviewers/CURSOR-SETUP.md`](../../reviewers/CURSOR-SETUP.md) — one-time Cursor setup
- [`reviewers/COPILOT-SETUP.md`](../../reviewers/COPILOT-SETUP.md) — Copilot adapter modes
- [`reviewers/FLOW-VERIFY-SETUP.md`](../../reviewers/FLOW-VERIFY-SETUP.md) — behavioural flow-verification leg
- [`EVAL.md`](../../EVAL.md) — test scenarios + Phase 1 gating
- [`docs/DESIGN.md`](../../docs/DESIGN.md) — full architecture spec
