---
name: finish
description: Post-merge cleanup. After the PR merges (typically via v0.4 automerge), runs /pr-autopilot:finish <id> to update the claim file to `merged`, mirror to ExoVault `done`, update `assignments.yaml` on `main` with merge metadata, and best-effort cleanup of the worktree + local branch. Lists dependent assignments that became READY. Idempotent. Use when - "close the assignment", "PR merged, clean up", "what's next ready".
---

# /pr-autopilot:finish <ASSIGNMENT_ID>

The closing skill of the pre-PR lifecycle — paired symmetrically with `/assign`.

## Pre-flight

- `gh pr view <claimFile.prNumber> --json mergedAt -q .mergedAt` returns non-null. (EVAL 46.)

## Steps

1. **Read claim file** for `<assignment-id>`. If already `merged` → skip mutations, proceed to step 5–7 for worktree cleanup. Verify PR merged via `gh`; capture `mergedAt`, `mergedCommit`.

2. **Update claim file on feature branch** (before checkout):
   ```json
   {
     "subStatus": "merged",
     "mergedAt": "<iso>",
     "mergedInPr": <PR#>
   }
   ```
   Commit on feature branch:
   ```bash
   git add .claude/assignment-claims/<id>.json
   git commit -m "chore(pr-autopilot): finish assignment <id> (merged in #<PR#>)"
   ```

3. **Mirror to ExoVault:**
   ```
   mcp__exo-vault__update_task(taskId, status='done')
   ```
   Append `mergedAt` + `mergedInPr` to description markdown.

4. **Update `assignments.yaml` on `main`** (P1-3 v2.1 fix + PR review P1-3 simplification):
   ```bash
   # Canonical main worktree resolution — first entry in `git worktree list --porcelain`
   # is always the primary worktree (where main lives). Works for multi-worktree setups,
   # symlinks, and paths with spaces.
   MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
   cd "$MAIN"

   git fetch origin main
   git checkout main
   git pull --ff-only origin main   # defensive: abort if local main diverged

   # Edit assignments.yaml: locate the entry by id, set status: merged, add merged_at + merged_in_pr
   # Do NOT touch the excludes: array — that's for historical/external context only.
   # Use yq, jq, sed, or direct write depending on what's available.

   git add assignments.yaml
   git commit -m "chore(assignments): mark <id> merged in PR #<N>"
   git push origin main             # NO --no-verify (P1-8 fix)
   ```
   **If push fails (branch protection):** echo:
   ```
   main is push-protected. Open a cleanup PR with this commit:
       git checkout -b chore/finish-<id>-cleanup
       git push -u origin chore/finish-<id>-cleanup
       gh pr create --base main --title "chore(assignments): mark <id> merged" --body "Post-merge cleanup for #<N>"

   Steps 5–7 will continue once that PR merges. Re-run /pr-autopilot:finish <id> after.
   ```
   STOP gracefully (will retry on next invocation).

5. **Worktree cleanup (best-effort, non-blocking):**
   ```bash
   git worktree remove .claude/worktrees/<id> 2>&1 || \
     echo "⚠️ Could not remove worktree (uncommitted changes?). Inspect and remove manually."
   ```

6. **Local branch cleanup:**
   ```bash
   # If branch was deleted on remote (v0.4 automerge typically does this), local delete is safe.
   if ! git ls-remote --heads origin "<branch>" | grep -q .; then
     git branch -D <branch> 2>&1 || true
   else
     echo "Remote branch <branch> still exists. Delete manually if desired: git branch -D <branch>"
   fi
   ```

7. **List dependents newly READY** (informational, no auto-claim):
   ```
   📋 Newly READY after this merge:
     - admin-d2-agents (deps satisfied)
     - admin-d3-phone-numbers (deps satisfied)

   Claim any: /pr-autopilot:assign <id>
   ```

## Idempotency

- If claim file already `merged` AND main yaml already says `merged` → skip mutations.
- If main yaml says `merged` but claim file doesn't (e.g. previous run died at step 5) → run steps 2–3 + 5–7 only.
- If worktree already removed → skip step 5.
- If local branch already deleted → skip step 6.
- Always run step 7 (READY check is cheap and useful).

## Recovery

If `/finish` is run on a different machine (no worktree present): steps 2–3 use ExoVault as the truth source; steps 5–6 become no-ops; steps 4 + 7 still work.
