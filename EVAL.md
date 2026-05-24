# EVAL.md — test scenarios for /pr-autopilot

This file is the verification spec. Each scenario describes a setup, the expected behavior, and (after running) the actual observed outcome. The "Results" section at the bottom is updated as scenarios are run on real PRs.

## Phase 1 gating

Before bumping from **v0.1.0** (pre-release) to **v1.0.0** (stable manual API), the following MUST pass on a real `exo-vault` PR:

- ✅ EVAL Step 0 — Reviewer login discovery
- ✅ Scenario 1 — Happy path
- ✅ Scenario 4 — CI breaks mid-loop
- ✅ Scenario 8 — Local pre-commit fails
- ✅ Scenario 11 — Score 5/5 but 1 unresolved thread
- ✅ Scenario 17Y — Mode Y happy path: Copilot SWE Agent each-iter, no Cursor

Scenarios 2, 3, 5, 6, 7, 9, 10, 12, 13, 14, 15, 16, 18, 19, 20a, 20b, 21 are spec'd but NOT GATED in v0.1.0. Scenarios 22, 23, 24 are v0.2 additions gated for v1.0.0.

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
| 17Y | **Mode Y happy path: Copilot SWE Agent each-iter, no Cursor** (Phase 1 gate for multi-reviewer) | Config: `cursor.enabled=false, copilot.mode=each-iter`. Open PR. | Tick 1: skill posts `@copilot please review`; tick 2: Copilot posts 3 line comments; triage applies 2, pushes back on 1; push; tick 3: `@copilot review` re-posted; Copilot returns 0 open threads → SUCCESS_STOP. Validates reviewer-adapter abstraction. |
| 18 | **Reviewer-mode: final-pass disagreement** | Per-iter Cursor scores 5/5. Final-pass `claudeSelf` reads the diff against `SELF-REVIEW-RUBRIC.md` and finds an unaddressed concern. | PAUSE "final-pass reviewer claudeSelf disagreed with per-iter consensus" + PushNotification. User decides next move. |
| 19 | **Config error: no per-iter reviewer enabled** | Config has all per-iter reviewers off (only `claudeSelf` as final-only enabled). | ABORT immediately at config validation: "at least one reviewer must be enabled for per-iteration; nothing would drive the loop" |
| 20a | **Codex via Cursor as the model** (default v0.1.0 path) | `cursor.enabled=true` + user has configured Cursor Background Agent to use Codex as the underlying model (Cursor's settings, not ours) | Skill sees reviews from `cursor[bot]` with `Score: N/5`; behavior identical to scenario 1. **No new code path** — proves the model choice is transparent to `pr-autopilot`. |
| 20b | **Codex standalone CLI, postCommentsToPR=true** (spec'd, not gated v0.1.0) | `cursor.enabled=false, codex.mode=each-iter, codex.postCommentsToPR=true`. Requires Codex Pro CLI sub. Open PR. | Skill runs `codex review --diff origin/main..HEAD` each iter; posts Codex's findings as `## Codex review (iteration N)` PR comment; processes findings internally; pass gate → SUCCESS_STOP. Gated in v0.2+. |
| 21 | **Per-iter consensus achieved but leftover Copilot threads from earlier each-iter experiment** (Composer v6 algorithm sanity edge case) | User flipped `copilot.mode` from `each-iter` to `off` mid-PR. Cursor scores 5/5 this tick. But unresolved Copilot threads from before the flip still exist on the PR. | Step 9 `unresolved_not_ours.length == 0` precondition is FALSE (Copilot threads not in our threadPushbacks); SUCCESS_STOP blocked; loop continues to step 10 triage where it dispatches to whichever logins are currently in `github_reviewer_logins`. Copilot threads (no longer dispatched) eventually require manual resolution. **User action:** either re-enable copilot.mode=each-iter to let the loop drain them, or resolve manually. |
| 22 | **Mode Y refusal handling** | SWE Agent posts "I cannot help with this" | ABORT cleanly; informative push notification; state file deleted |
| 23 | **Mode Y ambiguous config ABORT** | `cursor.enabled=true` + `copilotSwe.mode=each-iter` + `primaryFixer=auto` | ABORT at pre-flight asking user to set primaryFixer explicitly |
| 24 | **Mode Y PAUSE on behavior change** | PR hunk changes user-visible behavior (e.g. comparison operator on a cutoff) | PAUSE at Y.10; state file KEPT; user notified |

25 test cases (1-19 + 20a + 20b + 21 + 22 + 23 + 24) across 23 numbered scenarios + 1 pre-flight step. 8 gating (1, 4, 8, 11, 17Y, 22, 23, 24).

---

## Results (updated as gating scenarios run on real PRs)

### Step 0 results

- **Date run:** 2026-05-23
- **PR used:** MarcinSufa/exo-vault#127
- **Cursor login observed:** N/A (not enrolled on this repo; user hadn't subscribed to Cursor Pro)
- **Copilot login observed:** `copilot-swe-agent` (NOT `copilot-pull-request-reviewer[bot]`)
- **Critical finding:** `@copilot please review` mention triggers Copilot SWE Agent, not Copilot Code Review. They are different products. Copilot Code Review did NOT fire on this private repo even when requested via the `requested_reviewers` API.
- **Action taken:** Patched SKILL.md to clarify the trigger distinction (`gh api requested_reviewers` for Code Review, `@copilot` mention for SWE Agent). Added new `copilotSwe` reviewer adapter to spec + config schema. Updated test user's `~/.claude/settings.json` to use `copilotSwe` with `mode: each-iter`.

### Scenario 1 — Happy path (PARTIAL — immediate-approval variant)

- **Date run:** 2026-05-23
- **PR used:** MarcinSufa/exo-vault#127 (fixture: `src/_pr-autopilot-test.ts` with 7 deliberate code smells)
- **Iterations to SUCCESS:** 1 (immediate)
- **Wall-clock time:** ~3 min (mostly Copilot's response latency)
- **Outcome:** PARTIAL PASS — algorithm reached SUCCESS_STOP cleanly on first iteration, but did NOT exercise the fix-and-push cycle.
- **Why partial:** PR body explicitly stated "deliberate smells for the EVAL scenario." Copilot SWE Agent read the body context and correctly classified the smells as "intentional artifacts" → gave immediate approval verdict → algorithm short-circuited to SUCCESS_STOP without applying any fixes.
- **Algorithm coverage validated:** pre-flight (0.1–0.4), step 1 fetch, step 2 lifecycle, step 3 branch guard, step 4 iter cap, step 5 CI green, step 5.5 trigger (skipped — already triggered), step 6 fetch outcome, step 8 poll-tick reset, step 9 success aggregate, step 9b final-pass (skipped — none enabled), step 9c SUCCESS_STOP (no ScheduleWakeup → loop terminates cleanly).
- **NOT validated this run:** step 10 triage, step 11 pre-commit + push, step 11.5 stall guard, multi-iteration ScheduleWakeup → CONTINUE cycle.
- **Follow-up needed:** repeat scenario with a PR whose body does NOT mention "intentional" so SWE Agent flags the smells as real issues. That exercises the fix-and-push cycle.

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

### Scenario 17Y — Mode Y happy path: Copilot SWE Agent each-iter, no Cursor

- **Date run:** 2026-05-23
- **PR used:** MarcinSufa/exo-vault#128 (closed; fix-cycle test)
- **Outcome:** VARIANT PASS — validated a Mode Y rotation pattern (SWE Agent fixer + Claude reviewer) instead of the originally-specified pattern (reviewer + Claude fixer). See "v0.1.0 testing outcomes — design tension discovered" below.

## v0.1.0 testing outcomes — design tension discovered

The empirical real-PR test (PRs #127 + #128 on MarcinSufa/exo-vault) surfaced an architectural insight the original spec didn't account for. **Copilot has two products** that look similar but behave very differently:

| | Copilot Code Review | Copilot SWE Agent (Coding Agent) |
|---|---|---|
| Trigger | `gh api requested_reviewers -f 'reviewers[]=Copilot'` | `@copilot please review` mention |
| Role | Reviewer only — posts threaded comments | **Reviewer AND fixer** — applies fixes + pushes commits + adds tests |
| Output | Line-level threads + summary | Top-level conversational comment + committed code changes |
| Marcin's setup status (2026-05-23) | Configured but did not fire on private repo (rulesets/tier setup unclear) | Worked reliably, both runs |

**The design tension:** v0.1.0 spec assumed two roles (reviewer + Claude as fixer). But SWE Agent **collapses both roles** — it does the fixer's job itself. When using SWE Agent, Claude's "fix" role in the loop is redundant.

User-proposed resolution (2026-05-23, validated empirically): **two-role rotation modes** where each party validates the other:

- **Mode X — Claude fixes, Copilot/Cursor reviews** (original spec): Claude as primary fixer, reviewer comments validate Claude's work. Loop until reviewer approves.
- **Mode Y — SWE Agent fixes, Claude reviews**: SWE Agent as primary fixer, Claude reads SWE Agent's commits against `PUSHBACK.md` and either approves or flags behavior-changing concerns. Loop until Claude is satisfied OR PAUSES for human input on PAUSE-rule violations.

PR #128 walkthrough validated Mode Y end-to-end:
1. PR opened with neutral description (no "intentional test fixture" framing)
2. `@copilot please review` posted as comment → SWE Agent woke up
3. SWE Agent identified 7 code smells, applied all 7 fixes, added a 6-test test file, pushed as commit `cbbddd20`
4. Claude (acting as the reviewer half of Mode Y) read SWE Agent's diff, applied `PUSHBACK.md` rubric per change:
   - 7 of 8 changes APPROVED (renames, typo fix, magic number extraction, boolean simplification, return-type annotations, added tests)
   - 1 change FLAGGED for PAUSE: `age > 18` → `age >= 18` is a behavior change SWE Agent applied unilaterally; per PUSHBACK rule "behavior changes need human confirmation"
5. Claude posted structured review comment on PR (visible at PR #128 comment 4526042632) with verdict
6. User decides on the flagged item — Mode Y exits to PAUSE per design

**v0.2 RESOLVED (this branch):** SKILL.md now first-classes both rotation modes — see docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md.

### Scenario 21 (added during test) — Copilot Code Review trigger via wrong mechanism

- **Date run:** 2026-05-23
- **Setup:** PR #127, attempted to trigger Copilot Code Review via `@copilot please review` comment
- **Outcome:** TRIGGER WRONG — `@copilot` mention fires SWE Agent, not Code Review. `requested_reviewers` API is the correct trigger. **Patched in commit c682890** (added `copilotSwe` adapter + clarified `copilot` adapter trigger doc).

---

## Sign-off

When all 8 gating scenarios PASS, tag `v1.0.0`:

```bash
cd "c:/Users/sufam/IdeaProjects/claude-pr-autopilot"
git tag -a v1.0.0 -m "Phase 1 EVAL gating scenarios (1, 4, 8, 11, 17Y, 22, 23, 24) verified on real exo-vault PR"
git push origin v1.0.0
```

---

## v0.2 pre-merge verification (Task 10)

Date: 2026-05-24
Branch: feature/v0.2-rotation

| Check | What | Result |
|---|---|---|
| V1 | derive_mode truth table (12 cells) | PASS |
| V2 | state schema round-trip | PASS |
| V3 | v1->v2 migration documented | PASS |
| V4 | pre-flight accepts Mode Y | PASS |
| V5 | PUSHBACK Mode Y coverage | PASS |
| V6 | SKILL.md contradictions gone | PASS |

### V1 — derive_mode truth table

Variables: `swe_each` = copilotSwe.mode=="each-iter"; `any_xreviewer` = cursor.enabled OR copilot.mode=="each-iter" OR codex.mode=="each-iter"

Reviewer combos: (a) cursor only — `any_xreviewer=true, swe_each=false`; (b) copilotSwe only — `swe_each=true, any_xreviewer=false`; (c) both cursor+swe — `any_xreviewer=true, swe_each=true`; (d) nothing — both false.

| primaryFixer | (a) cursor only | (b) swe only | (c) cursor+swe | (d) nothing |
|---|---|---|---|---|
| `claude` | X | ABORT_CONFIG (swe conflict) | ABORT_CONFIG (swe conflict) | X* |
| `copilotSwe` | Y** | Y | Y | Y** |
| `auto` | X | Y | ABORT_CONFIG (ambiguous) | ABORT_NO_DRIVER |

\* `derive_mode` returns "X" for claude+(d), but pre-flight immediately ABORTs: "Mode X requires at least one per-iter reviewer in {cursor, copilot, codex}" — no X-reviewer is enabled. End result is an ABORT, via pre-flight not derive_mode.

\*\* `derive_mode` returns "Y" for copilotSwe+{a,d}, but pre-flight immediately ABORTs: "Mode Y requires copilotSwe.mode=each-iter" — the required config is absent. End result is an ABORT, via pre-flight not derive_mode.

All 12 cells are internally consistent. The two pre-flight catches (marked * and **) are expected by design — `derive_mode` is intentionally dumb about copilotSwe+{a,d} and claude+(d); pre-flight is the enforcement layer. No logic inconsistencies or surprising cells found.

### V2 — state schema round-trip notes

All 14 expected fields present in schema. All Mode Y pseudocode field references (handledOids, handledCommentIds, lastTriggerAt, lastHandledHeadOid, pollTicksWithoutActivity, resolvedMode, commitPushbacks, reviewIteration) resolved to schema fields without gap.

### V3 — migration notes

Migration prose at SKILL.md line 243-244 is unambiguous. Set-conversion lines (`state.handledOids = set(state.handledOids)`, `state.handledCommentIds = set(state.handledCommentIds)`) present in Y.0 block.

### V4 — pre-flight trace for Mode Y config

Config: `{primaryFixer: auto, copilotSwe.mode: each-iter, cursor.enabled: false, copilot.mode: off, codex.mode: off}`
→ `swe_each=true`, `any_xreviewer=false` → auto rule 1 fires → `derive_mode` returns "Y"
→ pre-flight: `copilotSwe.mode != "each-iter"` is false → no ABORT → proceeds to Mode Y body. Correct.

### V5 — PUSHBACK coverage notes

grep count = 17. Every rule heading carries either `(Mode X & Y)`, `(Mode X only — review threads)`, or a `**Mode Y example:**` inline. The "Behavior change without intent signal → PAUSE (Mode Y)" rule is present (PUSHBACK.md lines 46-55). Full coverage confirmed.

### V6 — SKILL.md contradictions

`grep -nE "Cannot do line-level fixes|please review this PR — primary reviewers scored"` returned no output. No legacy contradiction text present.
