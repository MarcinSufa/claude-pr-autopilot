# EVAL.md — test scenarios for /pr-autopilot

This file is the verification spec. Each scenario describes a setup, the expected behavior, and (after running) the actual observed outcome. The "Results" section at the bottom is updated as scenarios are run on real PRs.

## Phase 1 gating

Before bumping from **v0.1.0** (pre-release) to **v1.0.0** (stable manual API), the following MUST pass on a real `exo-vault` PR:

- ✅ EVAL Step 0 — Reviewer login discovery
- ✅ Scenario 1 — Happy path
- ✅ Scenario 4 — CI breaks mid-loop
- ✅ Scenario 8 — Local pre-commit fails
- ✅ Scenario 11 — Score 5/5 but 1 unresolved thread
- ✅ Scenario 17 — Reviewer-mode alt: Copilot each-iter (no Cursor)

Scenarios 2, 3, 5, 6, 7, 9, 10, 12, 13, 14, 15, 16, 18, 19, 20a, 20b, 21 are spec'd but NOT GATED in v0.1.0.

---

## Step 0 — Prerequisites + Reviewer login discovery (MUST RUN FIRST)

### Step 0.A — Verify prerequisites

Surfaced by v0.1.0 dry-run test (2026-05-23) — all CLIs must be on PATH:

```bash
gh --version && jq --version && git --version && gh auth status
```

Expected: all four succeed. If `jq` is missing on Windows: `winget install jqlang.jq` and restart shell. If `gh` is unauthenticated: `gh auth login`. See README → Prerequisites for full install table.

### Step 0.B — Reviewer login discovery

The spec defaults `reviewers.cursor.login` to `cursor[bot]` and `reviewers.copilot.login` to `copilot-pull-request-reviewer[bot]`, but the actual GitHub App login strings must be verified against a real PR with both reviewers enrolled. Composer flagged exact-match brittleness for Cursor in v3; same risk exists for Copilot per Composer v6.

```bash
# On a real PR where BOTH Cursor and Copilot have already reviewed:
gh pr view <PR#> --json reviews --jq '.reviews[].author.login' | sort -u
```

**Expected outcomes:**

- For Cursor: if `cursor[bot]` appears → defaults correct. Else (e.g. `cursor`, `cursor-app[bot]`, `cursor-review[bot]`) → update `reviewers.cursor.login` in config AND spec defaults.
- For Copilot: if `copilot-pull-request-reviewer[bot]` appears → defaults correct. Else (e.g. `copilot[bot]`, `github-copilot[bot]`) → update `reviewers.copilot.login` in config AND spec defaults.
- If multiple prefixed logins appear for either: **pick the one that posts the recognized signal (score line for Cursor, review threads for Copilot) and commit only that exact login**. The algorithm uses exact-match throughout (steps 6–8); we do not add `startswith` fallback in v0.1.0.

**Gate:** Phase 1 implementation does not start until step 0 has been run for BOTH default reviewers (Cursor and Copilot) and the verified logins committed to the spec defaults.

---

## Scenarios

| # | Scenario | Setup | Expected |
|---|---|---|---|
| 1 | **Happy path** (Phase 1 gate) | Open PR, Cursor reviews with 3 nits | Iter 1: 3 fixes pushed, full pre-commit suite runs green. Iter 2: Cursor scores 5/5. SUCCESS, notify, post @copilot |
| 2 | No reviewer has reviewed yet | Open PR, no enabled per-iter reviewer has posted a review | Up to 10 poll ticks (15 min), then ABORT "check setup docs for each enabled reviewer (Cursor/Copilot/Codex)" |
| 3 | Stubborn disagreement | Cursor keeps re-flagging same nit, Claude keeps pushing back | Hit 5 fix-iteration cap → ABORT "manual review required" |
| 4 | **CI breaks mid-loop** (Phase 1 gate) | Iter 1 push triggers CI failure | Iter 2 detects red CI on our headOid → ABORT. **Verification side-task:** on this real PR, run `gh pr view <PR#> --json statusCheckRollup` and confirm the field names (`isRequired`, `conclusion`, `state`) match the schema assumed in algorithm step 5. GitHub has renamed these fields before. |
| 5 | dev-targeted PR | PR targets dev or master directly | ABORT at step 3 immediately |
| 6 | Cursor score line missing | Cursor's review doesn't include `Score: N/5` | Treat as <5; continue looping until fix-iteration cap |
| 7 | PR merged externally | User merges manually mid-loop | Iter detects state=MERGED → SUCCESS_STOP; state file deleted |
| 8 | **Local pre-commit fails** (Phase 1 gate) | Claude's edit introduces lint or test failure | ABORT before push; nothing committed |
| 9 | Ambiguous architectural comment | Cursor suggests "consider refactoring X" | PAUSE; user notified, resumes manually |
| 10 | Non-pnpm repo | Run in a repo without pnpm | Lockfile auto-detect picks npm/yarn; pre-commit cmds substituted accordingly |
| 11 | **Score 5/5 but 1 unresolved thread** (Phase 1 gate, Composer-added) | Cursor scores 5/5, leaves a comment we haven't touched | CONTINUE one more iteration to address; never false-positive SUCCESS |
| 12 | CI pending on last push | After our push, required checks still queued/running | CONTINUE (wait), not ABORT |
| 13 | `/loop` STOP propagation | On SUCCESS, skill omits ScheduleWakeup | `/loop` terminates; no further ticks |
| 14 | `PR_AUTOPILOT_DISABLE=1` (Phase 2) | Set env var before `/ship` | Stop hook reads env, no-ops; user can still manually invoke |
| 15 | 50+ review threads | Open PR with massive review load | PAUSE "likely truncation"; user resumes manually after manual cleanup |
| 16 | **No-progress stall** (Composer v2 #1) | Cursor has reviewed, score is 3/5, no new comments for multiple ticks, all open threads are already-pushed-back-on (so triage does nothing) | After 6 ticks (~9 min) with `lastSeenReviewId` unchanged AND zero edits/pushbacks → PAUSE "loop spinning ≥6 ticks with no new review and no actions taken; manual intervention needed" |
| 17 | **Reviewer-mode alt: Copilot each-iter, no Cursor** (Phase 1 gate for multi-reviewer) | Config: `cursor.enabled=false, copilot.mode=each-iter`. Open PR. | Tick 1: skill posts `@copilot please review`; tick 2: Copilot posts 3 line comments; triage applies 2, pushes back on 1; push; tick 3: `@copilot review` re-posted; Copilot returns 0 open threads → SUCCESS_STOP. Validates reviewer-adapter abstraction. |
| 18 | **Reviewer-mode: final-pass disagreement** | Per-iter Cursor scores 5/5. Final-pass `claudeSelf` reads the diff against `SELF-REVIEW-RUBRIC.md` and finds an unaddressed concern. | PAUSE "final-pass reviewer claudeSelf disagreed with per-iter consensus" + PushNotification. User decides next move. |
| 19 | **Config error: no per-iter reviewer enabled** | Config has all per-iter reviewers off (only `claudeSelf` as final-only enabled). | ABORT immediately at config validation: "at least one reviewer must be enabled for per-iteration; nothing would drive the loop" |
| 20a | **Codex via Cursor as the model** (default v0.1.0 path) | `cursor.enabled=true` + user has configured Cursor Background Agent to use Codex as the underlying model (Cursor's settings, not ours) | Skill sees reviews from `cursor[bot]` with `Score: N/5`; behavior identical to scenario 1. **No new code path** — proves the model choice is transparent to `pr-autopilot`. |
| 20b | **Codex standalone CLI, postCommentsToPR=true** (spec'd, not gated v0.1.0) | `cursor.enabled=false, codex.mode=each-iter, codex.postCommentsToPR=true`. Requires Codex Pro CLI sub. Open PR. | Skill runs `codex review --diff origin/main..HEAD` each iter; posts Codex's findings as `## Codex review (iteration N)` PR comment; processes findings internally; pass gate → SUCCESS_STOP. Gated in v0.2+. |
| 21 | **Per-iter consensus achieved but leftover Copilot threads from earlier each-iter experiment** (Composer v6 algorithm sanity edge case) | User flipped `copilot.mode` from `each-iter` to `off` mid-PR. Cursor scores 5/5 this tick. But unresolved Copilot threads from before the flip still exist on the PR. | Step 9 `unresolved_not_ours.length == 0` precondition is FALSE (Copilot threads not in our pushbackReplies); SUCCESS_STOP blocked; loop continues to step 10 triage where it dispatches to whichever logins are currently in `github_reviewer_logins`. Copilot threads (no longer dispatched) eventually require manual resolution. **User action:** either re-enable copilot.mode=each-iter to let the loop drain them, or resolve manually. |

22 test cases (1-19 + 20a + 20b + 21) across 20 numbered scenarios + 1 pre-flight step. 5 gating (1, 4, 8, 11, 17).

---

## Results (updated as gating scenarios run on real PRs)

### Step 0 results

- **Date run:** _____
- **PR used:** _____
- **Cursor login observed:** _____ (matched default `cursor[bot]`? Y/N)
- **Copilot login observed:** _____ (matched default `copilot-pull-request-reviewer[bot]`? Y/N)
- **Action taken:** _____ (no change / updated SKILL.md defaults / updated plugin.json defaults)

### Scenario 1 — Happy path

- **Date run:** _____
- **PR used:** _____
- **Iterations to SUCCESS:** _____ (target: ≤ 3)
- **Wall-clock time:** _____ (target: 5-15 min)
- **Outcome:** PASS / FAIL — _____ (notes)

### Scenario 4 — CI breaks mid-loop

- **Date run:** _____
- **PR used:** _____
- **Outcome:** PASS / FAIL — _____ (notes)
- **statusCheckRollup schema verification:** confirmed isRequired / conclusion / state field names? Y/N

### Scenario 8 — Local pre-commit fails

- **Date run:** _____
- **PR used:** _____
- **Outcome:** PASS / FAIL — _____ (notes)

### Scenario 11 — Score 5/5 but 1 unresolved thread

- **Date run:** _____
- **PR used:** _____
- **Outcome:** PASS / FAIL — _____ (notes)

### Scenario 17 — Reviewer-mode alt: Copilot each-iter (no Cursor)

- **Date run:** _____
- **PR used:** _____
- **Outcome:** PASS / FAIL — _____ (notes)

---

## Sign-off

When all 5 gating scenarios PASS, tag `v1.0.0`:

```bash
cd "c:/Users/sufam/IdeaProjects/claude-pr-autopilot"
git tag -a v1.0.0 -m "Phase 1 EVAL gating scenarios (1, 4, 8, 11, 17) verified on real exo-vault PR"
git push origin v1.0.0
```
