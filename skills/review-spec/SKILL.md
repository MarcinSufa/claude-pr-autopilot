---
name: review-spec
description: Dispatch the pre-PR adapter layer against the current assignment's spec markdown file. Runs 2 Claude subagents (code-reviewer + adversarial self-review) always; runs Codex CLI + Cursor Cloud Agent if env keys set; prints copy-paste prompt for optional Composer 2.5 manual paste-back. Aggregates findings → claim file `review_history` + ExoVault mirror. Flips sub-status to `spec_review_complete` (0 P0) or `spec_revising` (≥1 P0). Use when - "review my spec", "check the spec before approving", "run findings on the design doc".
---

# /pr-autopilot:review-spec

Pre-PR adapter dispatch on a markdown spec file. Idempotent and re-runnable.

Full algorithm + adapter inventory + cursor-cloud poll contract: `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5-pre-pr-lifecycle-design.md` (v2.2 §Pre-PR Adapter Layer + §`/review-spec`).

## Pre-flight

- Inside a worktree with `.claude/assignment-claims/<id>.json` present.
- `subStatus` is `spec_drafting`, `spec_revising`, or `spec_review_complete` (re-run after manual paste).
- Spec file exists at `claimFile.specFile` or auto-detect newest `specs/*-<id>.md`.

## Steps

1. **Read claim file**. Update `subStatus: spec_review_requested`. Commit:
   ```bash
   git add .claude/assignment-claims/<id>.json
   git commit -m "chore(pr-autopilot): review-spec start for <id> (iter <n+1>)"
   ```

2. **Dispatch sync adapters in parallel** (single Agent-tool-message with multiple invocations):

   **Always (FREE):**
   - **claude-code-reviewer-subagent**: `Agent({ subagent_type: 'feature-dev:code-reviewer', description: 'Pre-PR spec review', prompt: <see template below> })`
   - **claude-self-review** (hostile, FREE): `Agent({ subagent_type: 'general-purpose', description: 'Adversarial spec review', prompt: <hostile template> })`

   **Opt-in PAID (if env set):**
   - **codex-exec** if `OPENAI_API_KEY` set OR `which codex` succeeds:
     ```bash
     codex exec --json --sandbox read-only --ask-for-approval never \
       --output-last-message "/tmp/codex-review-<id>-iter<n>.md" \
       "$(cat <prompt-template-with-spec-path>)"
     ```
   - **cursor-cloud-agent** if `CURSOR_API_KEY` set:
     ```bash
     RUN=$(curl -sX POST https://api.cursor.com/v1/agents \
       -H "Authorization: Bearer $CURSOR_API_KEY" \
       -H "Content-Type: application/json" \
       -d "{\"prompt\":{\"text\":\"<prompt+spec>\"},\"repos\":[{\"url\":\"<repo-url>\"}],\"model\":{\"id\":\"composer-2.5\"},\"autoCreatePR\":false}")
     # Poll run.id every 5s up to 120s
     ```
     If timeout → record `{kind: "cursor-cloud-agent", status: "pending", runId: "<id>", timeoutAt: "<iso>"}` in `reviewers[]`. Re-run `/review-spec` folds in pending result idempotently.

3. **Composer 2.5 manual prompt** (always — FREE fallback for Cursor Free users):

   Print to chat:
   ```
   🔵 OPTIONAL: open Cursor Composer 2.5 (Cmd+I) and paste this prompt:

   Review spec at `<path>` for: internal contradictions, missing edge cases / failure modes,
   scope creep vs declared scope_in/scope_out, alignment with CLAUDE.md + DESIGN.md, test coverage gaps.
   Return findings as P0/P1/P2 with confidence ratings (5/10–10/10).

   Then paste Composer's reply back into this chat. Re-run /pr-autopilot:review-spec to fold it in.
   (Advisory only — does NOT block spec_review_complete transition.)
   ```

4. **Aggregate findings** from all sync adapters that completed. Increment `reviewIteration`. Append entries to `reviewers[]` in claim file:
   ```json
   {
     "kind": "claude-code-reviewer-subagent" | "claude-self-review" | "codex-exec" | "cursor-cloud-agent" | "composer-2.5-manual",
     "status": "complete" | "pending" | "timeout",
     "iteration": <n>,
     "findings": { "p0": N, "p1": M, "p2": K, "details": "..." },
     "completedAt": "<iso>"
   }
   ```

5. **Composer manual paste handling (P1-4 fix):** if conversation context contains pasted reply since last `/review-spec`, parse it, dedup by body hash (do not duplicate entries), append as `composer-2.5-manual`. Advisory only — re-aggregation may flip state if new P0.

6. **Decision based on aggregated P0 count:**
   - **0 P0** → `subStatus: spec_review_complete`. Echo:
     ```
     ✅ Spec review complete (iter <n>). Findings: <N> P1, <K> P2 (no P0).
     📋 Reviewers: <list>
     
     Marcin: when ready, run /pr-autopilot:approve-spec.
     (Optional: paste Composer 2.5 findings + re-run /review-spec for additional perspective.)
     ```
   - **≥1 P0** → `subStatus: spec_revising`. Echo aggregated P0 list grouped by reviewer:
     ```
     ⚠️ Spec revision needed (iter <n>). <N> P0 findings:
     
     [P0 from codex-exec, confidence 8/10] <title> — <body>
     ...
     
     Agent: address findings, re-run /pr-autopilot:review-spec.
     ```

7. **Commit claim file update:**
   ```bash
   git add .claude/assignment-claims/<id>.json
   git commit -m "chore(pr-autopilot): review-spec iter <n> for <id> — <N> P0, <M> P1"
   ```

## Adapter prompts (PUSHBACK.md rubric)

**claude-code-reviewer-subagent:**
```
Review the spec at <path> for engineering rigor:
- internal contradictions
- missing edge cases / failure modes
- scope creep vs scope_in/scope_out
- alignment with CLAUDE.md + DESIGN.md (read both first)
- test coverage gaps
- security/correctness for any code paths described

Return P0/P1/P2 findings with confidence ratings (5/10-10/10) per PUSHBACK.md rubric.
Format: structured markdown table or per-finding section.
```

**claude-self-review (hostile):**
```
You are a HOSTILE reviewer reading the spec at <path>. Find WEAKNESSES:
- what is underspecified / hand-wavy
- what assumptions might be wrong
- what edge cases / error paths / race conditions are missed
- what scope creep is hidden in scope_in
- what tests would actually catch the failures the author hand-waved

Be ruthless. Do NOT be polite. Tighten the spec by finding weaknesses,
not by validating the author's choices.

Return P0/P1 ONLY (no P2 noise) with confidence ratings.
```

## Idempotency

- Re-running `/review-spec` after `spec_review_complete` is safe — it re-dispatches reviewers and may flip back to `spec_revising` if new P0 appear.
- Pending Cursor Cloud Agent runs get re-polled on re-run.
- Manual Composer paste dedup'd by body hash.
