# Auto-merge (v0.4): merge-wait and `safeAutoMerge`

Moved from `skills/step/SKILL.md`. Read this at SUCCESS_STOP (Mode X step 9c, Mode Y Y.10), and at step 0.6 whenever `state.autoMergeQueued == true`. `ci_checks()` is defined in SKILL.md step 5.

## 0.6 Merge-wait short-circuit (v0.4 — runs BEFORE Mode dispatch)

If a previous tick queued an auto-merge (`state.autoMergeQueued == true`), this tick is waiting for GitHub to **complete** the queued merge — not for reviewers. Short-circuit here, *before* the Mode dispatch, so neither Mode X (step 9a final-pass) nor Mode Y (Y.5 `@copilot` re-trigger, Y.6 idle-counting) re-runs review logic on a PR that is merely waiting to merge. Placement is load-bearing: `safeAutoMerge` is called from BOTH modes, so a queued **Mode Y** loop must be caught here too — and running before Mode dispatch also pre-empts the generic Y.2 `MERGED` cleanup so the tailored "merged → run /land-and-deploy" message wins.

```
if state.autoMergeQueued == true:
  pr = gh pr view ${prNumber} --json state,isDraft,mergeStateStatus,baseRefName
  if pr.state == "MERGED":
    delete $STATE_FILE
    PushNotification("PR #${prNumber} merged → ${pr.baseRefName}", "Run /land-and-deploy for ${pr.baseRefName}→master + deploy.")
    return  # SUCCESS, terminate
  if pr.state == "CLOSED":
    delete $STATE_FILE
    PushNotification("PR #${prNumber} closed without merge", "auto-merge abandoned")
    return  # terminate
  if pr.mergeStateStatus == "DIRTY":                                   # DIRTY = GitHub's merge-conflict state. There is NO "CONFLICTING" enum value. BLOCKED (branch protection) falls through to the stuck-cap below.
    PushNotification("PR #${prNumber} auto-merge blocked (conflicts)", "resolve, then re-run /pr-autopilot:step ${prNumber}")
    return  # STOP, KEEP state (see "Recovery" in §Error handling)
  state.pollTicksWhileQueued += 1
  if state.pollTicksWhileQueued >= config.pollTickCap:                 # stuck (e.g. branch protection needs human review)
    PushNotification("PR #${prNumber} auto-merge still pending", "after ${config.pollTickCap} ticks — check PR / branch protection")
    saveState($STATE_FILE)
    return  # STOP, KEEP state
  saveState($STATE_FILE)
  ScheduleWakeup(config.pollIntervalSeconds, "/loop /pr-autopilot:step ${prNumber}", "waiting for queued auto-merge to complete")
  return  # still queued — wait; skip steps 1-11 AND Mode dispatch
```

## Auto-merge: `safeAutoMerge(prNumber, baseRef, readySummary)` (v0.4)

Shared SUCCESS_STOP handler called from **both** terminal sites — Mode X step 9c and Mode Y Y.10 — with the **same gates**. It applies the auto-merge gates; if all pass it queues the merge and lets **step 0.6** finish the job on a later tick. If any gate fails it falls back to the existing notify-and-stop (the v0.3 default — unchanged when no repo is opted in).

`readySummary` is the caller's mode-specific success summary, used only in the Gate-1 default notification so each mode keeps its existing "ready" message.

**Config:** read `prAutopilot.autoMerge` from `~/.claude/settings.json` (defaults: `allowedTargetBranches=["dev"]`, `neverMergeToBranches=["master","main","production"]`, `mergeMethod="squash"`).

**Notification discipline:** exactly ONE notification per terminal outcome. A gate failure fires its single "ready / not-merged" message and deletes state (loop done, manual merge). The queue path fires only the "auto-merge queued" message and KEEPS state. No double-notifying.

```
function safeAutoMerge(prNumber, baseRef, readySummary):
  cfg = config.autoMerge   # defaults above if absent
  canon = $(gh repo view --json nameWithOwner -q .nameWithOwner)   # canonical owner/repo — same source as /pr-autopilot:allow + :automerge

  # GATE 1 — opt-in. DEFAULT path: absent ⇒ same notify-and-stop control flow as v0.3.
  # Match ~/.pr-autopilot/automerge-repos reusing the v0.3 allowlist matching VERBATIM:
  # trim each line, skip blanks, require a '/', compare case-insensitively.
  if NOT lineMatchCaseInsensitive(canon, "~/.pr-autopilot/automerge-repos"):
    PushNotification("PR #${prNumber} ready", "${readySummary} — merge manually or run /land-and-deploy")
    delete $STATE_FILE
    return  # SUCCESS_STOP (unchanged v0.3 default)

  # GATE 2 — not paused (shared kill switch with v0.3).
  if exists "~/.pr-autopilot/paused":
    PushNotification("PR #${prNumber} ready (auto-merge paused)", "${readySummary} — paused sentinel present; merge manually or /pr-autopilot:resume")
    delete $STATE_FILE
    return  # SUCCESS_STOP

  # GATE 3 — base safe. Positive allowlist AND blocklist (production guard).
  if (baseRef NOT in cfg.allowedTargetBranches) OR (baseRef in cfg.neverMergeToBranches):
    PushNotification("PR #${prNumber} ready", "PR targets ${baseRef} — not an auto-merge target. Run /land-and-deploy.")
    delete $STATE_FILE
    return  # SUCCESS_STOP

  # GATE 4 — PR ready (open + non-draft).
  pr_now = gh pr view ${prNumber} --json state,isDraft
  if pr_now.state != "OPEN" OR pr_now.isDraft == true:
    PushNotification("PR #${prNumber} not auto-merged", "PR not open/non-draft at SUCCESS_STOP — merge manually")
    delete $STATE_FILE
    return  # SUCCESS_STOP

  # GATE 5 — CI green on current headRefOid (same logic as step 5 / Y.4.5).
  checks = ci_checks(prNumber)   # step 5 helper: required checks, else all checks (re-fetched now)
  if any check has bucket NOT in {pass, skipping}:   # fail, pending or cancel → not green
    PushNotification("PR #${prNumber} ready", "reviewers green but CI not green — not auto-merging; merge manually after CI passes")
    delete $STATE_FILE
    return  # SUCCESS_STOP

  # GATE 6 — idempotent. Defensive: step 0.6 normally short-circuits a queued PR
  # before we ever reach here. If reached with autoMergeQueued already true, do NOT
  # re-queue — fall into the wait instead.
  if state.autoMergeQueued == true:
    saveState($STATE_FILE)
    ScheduleWakeup(config.pollIntervalSeconds, "/loop /pr-autopilot:step ${prNumber}", "waiting for queued auto-merge to complete")
    return  # go to wait (step 0.6 handles next tick)

  # All gates pass → merge. TWO distinct outcomes: --auto QUEUES (async); the direct
  # fallback merges NOW (sync). They must NOT be conflated — a synchronous merge is
  # already done, so it must delete state + notify "merged", never set autoMergeQueued.
  auto = run("gh pr merge ${prNumber} --auto --${cfg.mergeMethod} --delete-branch")   # capture exit + stderr
  if auto.failed AND auto.stderr matches "auto-merge .* not enabled":
    # Repo has no merge queue → direct, SYNCHRONOUS squash (CI + reviews already green at SUCCESS_STOP).
    direct = run("gh pr merge ${prNumber} --${cfg.mergeMethod} --delete-branch")
    if direct.succeeded:
      delete $STATE_FILE   # already merged — nothing to wait for
      PushNotification("PR #${prNumber} merged → ${baseRef}", "direct ${cfg.mergeMethod} (repo has no auto-merge queue). Run /land-and-deploy for ${baseRef}→master + deploy.")
      return  # merged synchronously — terminate (do NOT set autoMergeQueued / wait)
    else:
      # e.g. branch protection needs a human approval the bot can't satisfy
      PushNotification("PR #${prNumber} auto-merge blocked", "direct merge refused (branch protection?) — merge manually or run /land-and-deploy")
      delete $STATE_FILE
      return  # terminate

  # --auto succeeded → merge is QUEUED; GitHub completes it asynchronously.
  state.autoMergeQueued = true
  state.autoMergeAt = now()
  PushNotification("PR #${prNumber} auto-merge queued → ${baseRef}",
                   "${cfg.mergeMethod}; completes when checks/branch-protection clear. Run /land-and-deploy for ${baseRef}→master + deploy.")
  saveState($STATE_FILE)   # do NOT delete — "queued" ≠ "merged"
  ScheduleWakeup(config.pollIntervalSeconds, "/loop /pr-autopilot:step ${prNumber}", "waiting for queued auto-merge to complete")
  return  # merge queued — step 0.6 handles subsequent ticks
```

**Gate semantics (precise):**

| Gate | Check | On fail |
|---|---|---|
| 1 — opt-in | `canon` ∈ `~/.pr-autopilot/automerge-repos`, case-insensitive | notify "ready; merge manually or run /land-and-deploy"; delete state; STOP (**DEFAULT** — same notify-and-stop control flow as v0.3) |
| 2 — not paused | `~/.pr-autopilot/paused` absent | notify + STOP |
| 3 — base safe | `baseRef` ∈ `allowedTargetBranches` AND ∉ `neverMergeToBranches` | notify "run /land-and-deploy"; STOP |
| 4 — PR ready | `state == OPEN` AND `isDraft == false` | notify + STOP |
| 5 — CI green | all required checks green on `headRefOid` | notify "CI not green — not auto-merging"; STOP |
| 6 — idempotent | `state.autoMergeQueued != true` | skip re-queue; go to wait |

Gates 1 (default-off) + 3 (production guard) are the safety floor. `lineMatchCaseInsensitive` reuses the v0.3 auto-trigger gate-script matching helper verbatim.

## Error handling (auto-merge, v0.4)

| Condition | Behavior |
|---|---|
| `--auto` not enabled on repo | fall back to direct `gh pr merge --${mergeMethod} --delete-branch` (synchronous; CI + reviews already green). On success → delete state + notify "merged" (do NOT set `autoMergeQueued`/wait); if refused (e.g. branch protection) → notify "blocked" + STOP |
| Merge blocked (branch protection needs human approval, conflicts, no permission) | step 0.6 notifies; **keeps** state; STOP (no infinite loop) |
| Queue stuck (open + queued beyond `pollTickCap` ticks) | step 0.6 notifies; STOP; keeps state |
| PR merged/closed externally while queued | step 0.6 sees `MERGED`/`CLOSED` → cleanup + terminate |

**Recovery from a kept-state STOP (blocked/stuck):** state is retained so nothing is lost. Either (a) resolve the PR (fix conflicts / obtain the required human approval) and re-run `/pr-autopilot:step <PR#>` — step 0.6 picks up the queued merge and finishes — or (b) delete `~/.pr-autopilot/<owner>-<repo>-<N>.json` to abandon. A dedicated `/pr-autopilot:clear` is out of scope for v0.4.
