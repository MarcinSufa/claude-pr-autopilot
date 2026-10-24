---
name: approve-spec
description: User-only gate from spec to TDD. Asks the user (AskUserQuestion) to approve, show or reject the reviewed spec; on approve the user runs approve-claim.sh in their own terminal, which writes `approvedAt` + `approvedBy` to the claim file and flips sub-status to `implementing`. The PreToolUse hook (`enforce-spec-gate.sh`) then unblocks writes outside `specs/`. Use when - "approve the spec", "give green light to TDD", "spec is good, proceed".
disable-model-invocation: true
---

# /pr-autopilot:approve-spec

The hard gate between spec lifecycle and code lifecycle. **Must be invoked by user**, not autonomously by agent. The approval fields (`approvedAt`, `approvedBy`, `approvalContext`) are written only by `${CLAUDE_SKILL_DIR}/scripts/approve-claim.sh`, which the **user runs in their own terminal** (it reads a typed confirmation from `/dev/tty`; the agent's Bash tool has no terminal). The PreToolUse hook `enforce-spec-gate.sh` denies agent Write/Edit/Bash calls that change those fields or run that script. It is NOT cryptographic — see the hook header for what remains bypassable.

Full algorithm + gate strength analysis: `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5-pre-pr-lifecycle-design.md` (v2.2 §`/approve-spec` + §`enforce-spec-gate.sh`).

## Pre-flight

- Inside a worktree with `.claude/assignment-claims/<id>.json` present.
- `subStatus == spec_review_complete` (P0-6 fix — must have reviewed first; EVAL 44 covers attempting approve without review).

## Steps

1. **Read claim file.** Verify `subStatus == spec_review_complete`. Reject otherwise:
   - If `spec_drafting` or `spec_review_requested` → "Spec hasn't completed review. Run `/pr-autopilot:review-spec` first."
   - If `spec_revising` → "Spec has open P0 findings. Address them, re-run `/review-spec`, then come back."
   - If `implementing` or later → "Already approved. Nothing to do."

2. **AskUserQuestion (MANDATORY — lets the user choose approve / show / reject):**

   Generate the question with:
   - **Question:** `"Approve spec for assignment '<id>'? This unlocks Write/Edit across the entire codebase for this branch."`
   - **Header:** `"Approve spec"`
   - **Options (single-select):**
     - `"✅ Approve — unlock TDD"` with description listing aggregated review summary: `"Reviewers: <list>. Findings: 0 P0, <M> P1, <K> P2. Spec: <path>"`
     - `"🔵 Show full spec first"` with description: `"Print the spec content to chat for review, then re-run /approve-spec."`
     - `"❌ Reject — back to spec_revising"` with description: `"Sub-status flips to spec_revising. Agent will need to address concerns and re-run /review-spec."`

3. **Branch on user response:**

   **If user picked "Show full spec":** print spec file content to chat, exit (do NOT mutate state). User re-runs `/approve-spec` when ready.

   **If user picked "Reject":** update the claim file `subStatus: spec_revising` with the Edit tool (the spec gate denies Bash writes into `.claude/assignment-claims/`), then commit:
   ```bash
   git add .claude/assignment-claims/<id>.json
   git commit -m "chore(pr-autopilot): user rejected spec for <id> — back to spec_revising"
   ```
   Echo: "Spec rejected by user. Address concerns and re-run `/pr-autopilot:review-spec` then `/approve-spec`."

   **If user picked "Approve":** do NOT edit the claim file yourself (the hook will deny it). Print this for the user and stop until they confirm it ran:
   ```
   Run this in your own terminal, inside the worktree (it asks you to type the id):
     bash "${CLAUDE_SKILL_DIR}/scripts/approve-claim.sh" <id>
   ```
   The script checks `subStatus == spec_review_complete`, asks for the id on `/dev/tty`, then writes and commits:
   ```json
   {
     "subStatus": "implementing",
     "approvedAt": "<iso>",
     "approvedBy": "<git config user.email, else $USER>",
     "approvalContext": {
       "findings": { "p0": 0, "p1": <M>, "p2": <K> },
       "specFile": "<path>",
       "iterationAtApproval": <reviewIteration>
     }
   }
   ```
   Commit message: `chore(pr-autopilot): approve spec for <id> by <user-id>`.
   When the user says it ran, re-read the claim file and confirm `approvedAt` is set before continuing.

4. **Mirror to ExoVault**: `mcp__exo-vault__update_task(taskId, status='in_progress')` (status doesn't change; description markdown gets new approval entry).

5. **Echo to agent:**
   ```
   ✅ Spec APPROVED by <user-id> at <iso> (read back from the claim file).

   Sub-status: implementing
   Hard gate: LIFTED — PreToolUse hook will allow Write/Edit outside specs/.

   Next steps:
   1. TDD red → green → refactor (follow the project's own CLAUDE.md / contributing rules)
   2. When PR opens via `gh pr create`, run `/pr-autopilot:pr-opened <PR#>` to hand off to v0.4 step loop
   3. After PR merges, run `/pr-autopilot:finish <id>` to close the lifecycle
   ```

## Why this is the gate

Three layers of defense (per spec §"Gate strength"):

1. **User-only invocation**: `disable-model-invocation: true` keeps the model from starting this skill, and the approval write happens in `approve-claim.sh`, which needs a real terminal and a typed confirmation.
2. **Claim file integrity**: the hook denies agent changes to `approvedAt` / `approvedBy` / `approvalContext`, denies flipping `subStatus` to a coding state without `approvedAt`, and blocks all writes if a claim says `implementing` with `approvedAt: null`.
3. **Audit trail**: every transition is a git commit on the worktree branch. Any tampering is permanently logged.

This is **strong**, not bulletproof: an agent determined to bypass it can still write files through an interpreter, delete the claim file, or create the pause sentinel (full list in `hooks/enforce-spec-gate.sh`). Bulletproof would require cryptographic signing (overkill for v0.5).

## Idempotency

Re-running after approval (`subStatus: implementing` already set):
- Print current approval metadata (who, when).
- No-op. Do not re-trigger AskUserQuestion (would be confusing).
