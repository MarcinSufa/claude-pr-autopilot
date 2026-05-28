---
name: unassign
description: Release an assignment claim WITHOUT merging — agent changed mind, assignment re-classified, deps blocked indefinitely. Removes worktree, deletes branch, resets ExoVault task to `todo`. Confirms destructively (requires AskUserQuestion). Symmetric counterpart to `/assign`. Use when - "abandon this assignment", "release the claim", "I'm not working on X anymore".
---

# /pr-autopilot:unassign <ASSIGNMENT_ID>

Housekeeping skill. Symmetric counterpart to `/assign`. **Destructive** — requires interactive user confirmation.

## Pre-flight

- Claim file or remote branch matching `<assignment-id>` exists.
- Run from main worktree or anywhere outside the target's worktree (worktree removal can't be done from inside the worktree being removed).

## Steps

1. **Read claim file** (from worktree path if accessible, else from remote branch via `git show <branch>:.claude/assignment-claims/<id>.json`).
   - If `subStatus == merged` → reject: "Assignment <id> is already merged. Use git revert workflows, not `/unassign`."
   - If claim file missing but ExoVault task `in_progress` → orphan recovery: proceed but with explicit warning.

2. **AskUserQuestion (MANDATORY — destructive action):**
   - **Question:** `"Unassign '<id>'? This will DELETE the worktree, local branch '<branch>', and reset the ExoVault task to 'todo' for re-claim."`
   - **Header:** `"Unassign"`
   - **Options:**
     - `"❌ Cancel — keep claim"` (default safe option)
     - `"⚠️ Unassign — delete worktree + branch"` with description: `"Destructive. Lost: <N> uncommitted edits (if any), <M> commits not in any other branch. Sub-status was: <current>. Approved by: <approvedBy or 'never'>."`
     - `"📋 Show current state first"` with description: `"Print claim file + git status + git log of this branch, then re-run /unassign."`

3. **Branch on response:**

   **Cancel:** no-op, exit gracefully.

   **Show state:** print:
   ```
   claim file: <full json>
   git log <branch> --oneline | head -20
   git status (if worktree accessible)
   ```
   Exit. User re-runs `/unassign` when ready.

   **Unassign — proceed:**

4. **`cd` to main worktree root** (outside target's worktree):
   ```bash
   MAIN=$(git worktree list | head -1 | awk '{print $1}')
   cd "$MAIN"
   ```

5. **Remove worktree:**
   ```bash
   git worktree remove ".claude/worktrees/<id>" 2>&1 || \
     git worktree remove --force ".claude/worktrees/<id>" 2>&1 || \
     echo "⚠️ Worktree at .claude/worktrees/<id> not removable. Inspect manually."
   ```

6. **Delete local branch:**
   ```bash
   git branch -D "<branch>" 2>&1 || echo "Branch <branch> not present locally (already deleted?)"
   ```

7. **Delete remote branch (if pushed):**
   ```bash
   if git ls-remote --heads origin "<branch>" | grep -q .; then
     echo "Branch was pushed. Delete remote: git push origin --delete <branch>"
     # Optionally auto-execute if user pre-confirmed in step 2; default = prompt first
   fi
   ```

8. **Reset ExoVault task:**
   ```
   mcp__exo-vault__update_task(taskId, status='todo', assignedAgentId=null)
   ```
   This re-opens the assignment for any agent to claim.

9. **`assignments.yaml` on main (P2 note — usually no-op):**
   - If yaml says `status: in_progress` for this id → reset to `todo` and commit. (Shouldn't happen post P0-3 v2 fix, but defensive.)
   - If yaml says `blocked` → preserve (block is intentional).
   - If yaml already `todo` → no-op (most common case after P0-3 truth model).

10. **Echo confirmation:**
    ```
    ✅ Assignment <id> released.
    
    Worktree: removed
    Local branch: deleted
    Remote branch: <still exists | deleted>
    ExoVault task: reset to todo
    
    /pr-autopilot:assign <id> may be invoked by any agent now.
    ```

## Why interactive confirmation is mandatory

Unlike `/assign` (creative, low-risk), `/unassign` is destructive:
- Deletes work-in-progress (uncommitted edits in worktree)
- Removes audit trail (local branch git history)
- Resets ExoVault task

AskUserQuestion enforces that a human (not just the agent acting autonomously) authorized the destruction.

## Recovery

If `/unassign` partially completed (e.g. worktree removed but ExoVault update failed):
- Re-run `/unassign <id>` → idempotent steps 5–9 will skip what's done and complete what's not.
- Or manually clean: `git branch -D <branch>`, `mcp__exo-vault__update_task(...)`.
