---
name: assign
description: Atomically claim an assignment from `assignments.yaml`, create a worktree off `origin/main`, write the claim file, and brief the agent. Uses git branch creation as the atomic lock primitive — concurrent calls on the same id are racing on `git worktree add -b`; loser gets a graceful "claimed by X" message. Use when starting work on a pre-declared unit ("claim admin-d1", "start the next ready assignment").
---

# /pr-autopilot:assign [<assignment-id>]

Pre-PR lifecycle entry point. Claims an assignment, creates an isolated worktree off `origin/main`, and instructs the agent to draft a spec **first** — coding is hard-gated by `enforce-spec-gate.sh` until `/pr-autopilot:approve-spec` runs.

Full algorithm + state machine + claim file schema: `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5-pre-pr-lifecycle-design.md` (v2.2 APPROVED 2026-05-28).

## Required tools on user machine

- `gh` (GitHub CLI, authenticated)
- `jq` (JSON processor)
- `git` (with worktree support)
- ExoVault MCP reachable + `EXOVAULT_VAULT_ID` env or vault id in project settings

## Pre-flight

- Repo present in `~/.pr-autopilot/allowed-repos` (case-insensitive match).
- `~/.pr-autopilot/paused` sentinel **absent**.
- `assignments.yaml` exists at repo root.

## Steps

1. **Read** `assignments.yaml`. If `<assignment-id>` provided → locate matching entry. If missing → EVAL 39 graceful error.

2. **List sets** (if id not provided):
   - **READY**: `status: todo` in yaml AND every `dep` is either in `excludes` with `pr` merged, OR has `status: merged` in yaml, OR has ExoVault task `status: done`.
   - **IN_PROGRESS**: `mcp__exo-vault__list_tasks(status='in_progress')` filtered by `title` matching `assignment:*`. Cross-check `git branch -r feat/*` for recovery scenarios.
   - **BLOCKED**: `status: blocked` in yaml.
   - Present numbered list. Ask user to pick.

3. **Verify deps satisfied** for chosen id (EVAL 40 — graceful reject if any unmerged).

4. **Atomic claim via git** (the heart of v0.5):
   ```bash
   git fetch origin main
   git worktree add ".claude/worktrees/<id>" -b "<branch>" "origin/main"
   ```
   - If exit ≠ 0 with "branch already exists" → claim file already on that branch:
     ```bash
     git show "<branch>:.claude/assignment-claims/<id>.json" | jq '{agentId, claimedAt, subStatus}'
     ```
     STOP: `"Assignment <id> claimed by <agentId> since <claimedAt> (subStatus: <subStatus>). Use /pr-autopilot:unassign <id> if you want to release."`
   - If exit ≠ 0 with worktree-already-exists → recovery branch (EVAL 47):
     ```bash
     EXISTING=$(git worktree list | grep ".claude/worktrees/<id>" | awk '{print $1}')
     if [ -d "$EXISTING/.claude/assignment-claims/<id>.json" ]; then
       STATE=$(jq -r '.subStatus' "$EXISTING/.claude/assignment-claims/<id>.json")
       echo "Existing worktree found at $EXISTING (subStatus=$STATE). Continue there? (Cmd+I to cd)"
     else
       echo "Orphan worktree at $EXISTING without claim file. Run /pr-autopilot:unassign <id> to clean up, then retry."
     fi
     STOP gracefully.
   - Otherwise propagate.

5. **`cd` into worktree** `.claude/worktrees/<id>`.

6. **Write initial claim file** `.claude/assignment-claims/<id>.json`:
   ```json
   {
     "assignmentId": "<id>",
     "agentId": "<from CLAUDE_USER env or session metadata>",
     "claimedAt": "<iso now>",
     "subStatus": "spec_drafting",
     "branch": "<branch>",
     "worktreePath": ".claude/worktrees/<id>",
     "specFile": null,
     "prNumber": null,
     "prUrl": null,
     "reviewIteration": 0,
     "reviewers": [],
     "approvedAt": null,
     "approvedBy": null,
     "approvalContext": null,
     "mergedAt": null,
     "mergedInPr": null
   }
   ```
   Commit:
   ```bash
   git add .claude/assignment-claims/<id>.json
   git commit -m "chore(pr-autopilot): claim assignment <id>"
   ```

7. **Mirror to ExoVault** (idempotent, P1-6 fix):
   - `mcp__exo-vault__list_tasks` → find task with exact title `assignment:<id>`.
   - If exists with `status: in_progress` and same `assignedAgentId` → no-op.
   - If exists with different `assignedAgentId` → STOP (defensive — branch race should have caught this earlier).
   - If exists with `status: done` → `mcp__exo-vault__update_task(taskId, status='in_progress', assignedAgentId=<me>)`.
   - Otherwise → `mcp__exo-vault__create_task(title="assignment:<id>", status="in_progress", assignedAgentId=<me>, description=<task-schema markdown>)`.
   - If MCP unreachable: log warning, continue (not critical path).

8. **DO NOT mutate `assignments.yaml`.** Main yaml truth excludes `in_progress` — runtime state lives only in claim file. (P0-3 v2 fix.)

9. **Load and echo `first_prompt`** from the assignment's yaml entry. Append directive:

   ```
   📍 Assignment <id> is now CLAIMED on branch <branch>.
   📁 Worktree: .claude/worktrees/<id>
   📋 Sub-status: spec_drafting

   Step 1: WRITE THE SPEC at `specs/<YYYY-MM-DD>-<id>.md`. This is the only file you may modify until approval.
   Step 2: When done, run `/pr-autopilot:review-spec` to dispatch reviewers.
   Step 3: After 0 P0 findings, ask Marcin to run `/pr-autopilot:approve-spec`.
   Step 4: Only after sub-status flips to `implementing` will the PreToolUse hook unblock Write/Edit outside `specs/`.

   ⚠️ The hook will BLOCK any Write/Edit outside `specs/` until you've completed the spec lifecycle.
   ```

## Confirmation output

- `branch` name
- `worktreePath`
- Expected `specFile` path (`specs/<YYYY-MM-DD>-<id>.md`)
- Current `subStatus: spec_drafting`
- ExoVault task id (if created/updated)

## Idempotency

Re-running `/assign <id>` from outside any worktree:
- If branch already exists → graceful "already claimed" message (no clobber).
- If worktree already exists → offer to `cd` there (no recreate).
- If everything aligned → no-op confirmation.
