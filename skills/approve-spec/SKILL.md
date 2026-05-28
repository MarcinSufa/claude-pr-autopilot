---
name: approve-spec
description: User-only gate from spec to TDD. Uses AskUserQuestion interactive primitive (cannot be fabricated by agent) to capture explicit user approval, then writes `approvedAt` + `approvedBy` to the claim file and flips sub-status to `implementing`. The PreToolUse hook (`enforce-spec-gate.sh`) then unblocks Write/Edit outside `specs/`. Use when - "approve the spec", "give green light to TDD", "spec is good, proceed".
---

# /pr-autopilot:approve-spec

The hard gate between spec lifecycle and code lifecycle. **Must be invoked by user**, not autonomously by agent — the AskUserQuestion primitive is the cryptographically-equivalent guarantee (interactive UI element that requires physical click).

Full algorithm + gate strength analysis: `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5-pre-pr-lifecycle-design.md` (v2.2 §`/approve-spec` + §`enforce-spec-gate.sh`).

## Pre-flight

- Inside a worktree with `.claude/assignment-claims/<id>.json` present.
- `subStatus == spec_review_complete` (P0-6 fix — must have reviewed first; EVAL 44 covers attempting approve without review).

## Steps

1. **Read claim file.** Verify `subStatus == spec_review_complete`. Reject otherwise:
   - If `spec_drafting` or `spec_review_requested` → "Spec hasn't completed review. Run `/pr-autopilot:review-spec` first."
   - If `spec_revising` → "Spec has open P0 findings. Address them, re-run `/review-spec`, then come back."
   - If `implementing` or later → "Already approved. Nothing to do."

2. **AskUserQuestion (MANDATORY — the interactive primitive that constitutes the gate):**

   Generate the question with:
   - **Question:** `"Approve spec for assignment '<id>'? This unlocks Write/Edit across the entire codebase for this branch."`
   - **Header:** `"Approve spec"`
   - **Options (single-select):**
     - `"✅ Approve — unlock TDD"` with description listing aggregated review summary: `"Reviewers: <list>. Findings: 0 P0, <M> P1, <K> P2. Spec: <path>"`
     - `"🔵 Show full spec first"` with description: `"Print the spec content to chat for review, then re-run /approve-spec."`
     - `"❌ Reject — back to spec_revising"` with description: `"Sub-status flips to spec_revising. Agent will need to address concerns and re-run /review-spec."`

3. **Branch on user response:**

   **If user picked "Show full spec":** print spec file content to chat, exit (do NOT mutate state). User re-runs `/approve-spec` when ready.

   **If user picked "Reject":** update claim file `subStatus: spec_revising`, commit:
   ```bash
   git add .claude/assignment-claims/<id>.json
   git commit -m "chore(pr-autopilot): user rejected spec for <id> — back to spec_revising"
   ```
   Echo: "Spec rejected by user. Address concerns and re-run `/pr-autopilot:review-spec` then `/approve-spec`."

   **If user picked "Approve":**
   - Capture `<iso-timestamp>` and `<user-identifier>` (`$CLAUDE_USER` env, fallback `git config user.email`, fallback `"<unknown-user>"`).
   - Update claim file:
     ```json
     {
       "subStatus": "implementing",
       "approvedAt": "<iso>",
       "approvedBy": "<user-id>",
       "approvalContext": {
         "findings": { "p0": 0, "p1": <M>, "p2": <K> },
         "specFile": "<path>",
         "iterationAtApproval": <reviewIteration>
       }
     }
     ```
   - Commit:
     ```bash
     git add .claude/assignment-claims/<id>.json
     git commit -m "chore(pr-autopilot): approve spec for <id> by <user-id>"
     ```

4. **Mirror to ExoVault**: `mcp__exo-vault__update_task(taskId, status='in_progress')` (status doesn't change; description markdown gets new approval entry).

5. **Echo to agent:**
   ```
   ✅ Spec APPROVED by <user-id> at <iso>.
   
   Sub-status: implementing
   Hard gate: LIFTED — PreToolUse hook will allow Write/Edit outside specs/.
   
   Next steps:
   1. TDD red → green → refactor per CLAUDE.md rule #4
   2. When PR opens via `gh pr create`, run `/pr-autopilot:pr-opened <PR#>` to hand off to v0.4 step loop
   3. After PR merges, run `/pr-autopilot:finish <id>` to close the lifecycle
   ```

## Why this is the gate

Three layers of defense (per spec §"Gate strength"):

1. **AskUserQuestion** is an interactive UI primitive. Agent CANNOT fabricate the user's click. The transcript shows the question text and the user's literal selection.
2. **Claim file integrity**: hook reads `approvedAt`; null → block coding states. Agent setting `subStatus: implementing` without `approvedAt` is blocked.
3. **Audit trail**: every transition is a git commit on the worktree branch. Any tampering is permanently logged.

This is **strong**, not bulletproof. Bulletproof would require cryptographic signing (overkill for v0.5).

## Idempotency

Re-running after approval (`subStatus: implementing` already set):
- Print current approval metadata (who, when).
- No-op. Do not re-trigger AskUserQuestion (would be confusing).
