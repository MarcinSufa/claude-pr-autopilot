---
name: pr-opened
description: Bridge from pre-PR (v0.5) to post-PR (v0.4 step loop). After `gh pr create`, run /pr-autopilot:pr-opened <PR#> to record the PR linkage in the claim file, flip sub-status to `pr_review_requested`, and prompt user to start the v0.4 review loop. 5-line skill; the value is the audit-trail entry. Use when - "PR created, hand off to autopilot", "bridge to step loop".
---

# /pr-autopilot:pr-opened <PR_NUMBER>

The handoff between v0.5 pre-PR lifecycle and v0.4 post-PR review loop.

## Pre-flight

- Inside a worktree with `.claude/assignment-claims/<id>.json` present.
- `subStatus == implementing` (or stale `spec_approved` from v2 design — accepted with deprecation warning).
- `gh pr view <PR#>` succeeds (PR exists).
- `gh pr view <PR#> --json headRefName` matches `claimFile.branch` (defensive — caller-typo guard).

## Steps

1. **Read claim file.** Verify sub-status. Reject if not `implementing` (or `spec_approved` for back-compat) — likely user invoked before any commits / before TDD.

2. **Fetch PR metadata:**
   ```bash
   gh pr view <PR#> --json url,number,headRefName,state -q '{url, number, headRefName, state}'
   ```
   If `state != OPEN` → echo "PR #<N> state is <state> — not OPEN, refusing to flip sub-status" and STOP.
   If `headRefName != claimFile.branch` → echo "Branch mismatch: PR is on <headRefName>, claim file says <branch>. Likely wrong PR#." and STOP.

3. **Update claim file** (P1-2 fix: flip directly to `pr_review_requested` since PR exists ⇒ review loop is about to start; v0.4 `step` will not touch this file):
   ```json
   {
     "subStatus": "pr_review_requested",
     "prNumber": <PR#>,
     "prUrl": "<url>"
   }
   ```
   Commit:
   ```bash
   git add .claude/assignment-claims/<id>.json
   git commit -m "chore(pr-autopilot): PR #<N> opened for <id> — hand off to step loop"
   git push origin <branch>
   ```

4. **Mirror to ExoVault**: `update_task(taskId, ...)` — append PR linkage to description.

5. **Echo handoff message:**
   ```
   ✅ PR #<N> linked to assignment <id>. Sub-status: pr_review_requested.
   
   📋 PR: <url>
   📁 Branch: <branch>
   
   Hand off to v0.4 review loop:
       /loop /pr-autopilot:step <PR#>
   
   The step loop will run until reviewers report 5/5 + automerge fires (if enabled).
   After merge, run /pr-autopilot:finish <id> to close the lifecycle.
   ```

## Note on `pr_opened` sub-status

There is no separate `pr_opened` sub-status in the claim file. Conceptually it exists between `gh pr create` and `/pr-opened` invocation (a few seconds). The claim file jumps directly from `implementing` to `pr_review_requested`. This avoids a one-state-step-with-no-purpose.

## Idempotency

Re-running `/pr-opened <PR#>` after first invocation:
- If `subStatus` already `pr_review_requested` and `prNumber` matches → no-op confirmation.
- If `prNumber` differs → echo "Already linked to PR #<existing>. Refusing to re-link." (use `/unassign` if you really need to start over with a different PR.)
