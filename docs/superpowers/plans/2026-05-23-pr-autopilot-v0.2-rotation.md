# pr-autopilot v0.2 Two-Mode Rotation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `pr-autopilot` support both rotation modes — Mode X (external agent reviews, Claude fixes) and Mode Y (Copilot SWE Agent fixes, Claude reviews against PUSHBACK.md) — as first-class, with a mode-aware pre-flight that no longer rejects Mode Y configs.

**Architecture:** This is a Claude Code marketplace plugin. The "code" is a set of markdown runbooks that Claude executes: `skills/step/SKILL.md` (the algorithm), `PUSHBACK.md` (review rubric), `REVIEW-TRIAGE-COPY.md` (triage dispatch). There is no compiled code and no test runner. Verification is (a) grep assertions on the markdown, (b) the Pre-merge verification matrix V1-V6 from the spec, and (c) real-PR integration tests on `MarcinSufa/exo-vault`.

**Tech Stack:** Markdown runbooks; `gh` CLI; `jq`; `git`; Claude Code `/loop` + `ScheduleWakeup`. Windows + Git Bash environment.

**Source of truth:** `docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md` (committed at `a3942e2`). Where a task says "transcribe from spec §X", copy that section verbatim and adapt only the heading style to match the target file. Do not paraphrase algorithm logic.

**Working branch:** `feature/v0.2-rotation` (already checked out; spec already committed there).

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `skills/step/SKILL.md` | Algorithm runbook: pre-flight, mode derivation, Mode X (existing) + Mode Y (new), state schema | 1, 2, 3, 4 |
| `REVIEW-TRIAGE-COPY.md` | Triage dispatch — add Mode Y commit-review section | 5 |
| `PUSHBACK.md` | Review rubric — add Mode Y commit-hunk examples + behavior-change PAUSE rule | 6 |
| `EVAL.md` | Test scenarios — rename 17→17Y, add 22/23/24, mark v0.2 follow-up resolved | 7 |
| `ROADMAP.md` | Re-version v0.2 = rotation, move Cursor port | 8 |
| `SHIP-INTEGRATION.md` | Re-version Stop-hook plan v0.2 → v0.3 | 8 |
| `reviewers/COPILOT-SETUP.md` | Fix `@copilot` mention semantics | 8 |
| `README.md` | Add Mode X/Y overview | 8 |
| `docs/DESIGN.md` | Add partial-supersession stub at top | 8 |
| `.claude-plugin/plugin.json` | Version bump 0.1.0 → 0.2.0 | 9 |

**Task ordering rationale:** SKILL.md changes first (1→4) because everything dispatches on `derive_mode` and the state schema. Doc reconciliation (5-8) depends on the final algorithm wording. Version bump (9) last. Verification matrix (10) and real-PR tests (11) gate the merge.

---

### Task 1: Mode derivation + mode-aware pre-flight in SKILL.md

**Files:**
- Modify: `skills/step/SKILL.md` — replace the pre-flight block (`SKILL.md:71-77`), add a new `derive_mode` section before it

- [ ] **Step 1: Read the current pre-flight block to confirm exact text**

Run: `grep -n "no per-iter reviewer enabled" skills/step/SKILL.md`
Expected: one hit around line 75 inside the `## Pre-flight: config validation` block.

- [ ] **Step 2: Add the `## Mode derivation` section**

Insert a new section immediately before `## Pre-flight: config validation`. Transcribe from spec §"Mode derivation rules" — the `primaryFixer` table, the `primaryFixer="claude"` + `copilotSwe.mode="each-iter"` ABORT rule, and the 4 `auto` resolution rules. Add this concrete `derive_mode` pseudocode block (this is the canonical implementation; the spec describes it prose-first):

```
function derive_mode(config):
  pf = config.prAutopilot.primaryFixer  # default "auto"
  swe_each = config.reviewers.copilotSwe.mode == "each-iter"
  any_xreviewer = config.reviewers.cursor.enabled
                  or config.reviewers.copilot.mode == "each-iter"
                  or config.reviewers.codex.mode == "each-iter"

  if pf == "claude":
    if swe_each: return ABORT_CONFIG  # conflict — see message in pre-flight
    return "X"
  if pf == "copilotSwe":
    return "Y"  # pre-flight validates copilotSwe.mode == each-iter
  # pf == "auto"
  if swe_each and not any_xreviewer: return "Y"
  if any_xreviewer and not swe_each: return "X"
  if any_xreviewer and swe_each:     return ABORT_CONFIG  # ambiguous
  return ABORT_NO_DRIVER
```

- [ ] **Step 3: Replace the pre-flight block with the mode-aware version**

Replace `SKILL.md:71-77` content. Transcribe the replacement from spec §"Pre-flight fix" (the `mode = derive_mode(config)` block with the ABORT_CONFIG, Mode X, and Mode Y branches). Add the two ABORT message strings:
- ambiguous: `"ambiguous fixer config. Set primaryFixer to 'claude' or 'copilotSwe' explicitly to resolve."`
- claude+swe conflict: `"primaryFixer=claude conflicts with copilotSwe.mode=each-iter. Either set copilotSwe.mode=off (or final-only) or change primaryFixer to copilotSwe or auto."`

- [ ] **Step 4: Verify the pre-flight no longer hard-excludes copilotSwe**

Run: `grep -n "for r in {cursor, copilot, codex}" skills/step/SKILL.md`
Expected: NO hits (the old hard-coded set is gone; Mode X branch uses the list but only when `mode == "X"`).

Run: `grep -n "derive_mode" skills/step/SKILL.md`
Expected: at least 2 hits (definition + use in pre-flight).

- [ ] **Step 5: Commit**

```bash
git add skills/step/SKILL.md
git commit -m "feat(skill): mode-aware pre-flight + derive_mode (Mode Y no longer aborts)"
```

---

### Task 2: State schema v2 + mode-drift guard in SKILL.md

**Files:**
- Modify: `skills/step/SKILL.md` — replace the state schema block (`SKILL.md:120-136`), add migration note

- [ ] **Step 1: Read the current state schema block**

Run: `grep -n '"pushbackReplies"' skills/step/SKILL.md`
Expected: one hit in the `### 0.5 Load state` state-schema JSON (~line 132).

- [ ] **Step 2: Replace the state schema JSON**

Replace the state-schema JSON block with the v2 schema. Transcribe from spec §"State schema (resolves Blocker 4 ...)" — the full JSON with `stateSchemaVersion: 2`, `resolvedMode`, `threadPushbacks`, `commitPushbacks`, `handledOids`, `handledCommentIds`, `lastTriggerAt`, `pollTicksWithoutActivity`, `reviewIteration`.

- [ ] **Step 3: Add the migration + key-rename note**

Below the JSON, add the "Key changes from v0.1 state" bullets from spec §"State schema" (the `stateSchemaVersion`, `resolvedMode`, `pushbackReplies → threadPushbacks/commitPushbacks` split, and the backwards-compat paragraph). State the migration decision explicitly: **v1 state files (no `stateSchemaVersion`) → treat as Mode X; if current derived mode is Y, ABORT with "delete the stale state file to start fresh in Mode Y".**

- [ ] **Step 4: Verify**

Run: `grep -n '"stateSchemaVersion": 2' skills/step/SKILL.md`
Expected: 1 hit.
Run: `grep -nc '"threadPushbacks"\|"commitPushbacks"' skills/step/SKILL.md`
Expected: both keys present (≥2 total hits).

- [ ] **Step 5: Commit**

```bash
git add skills/step/SKILL.md
git commit -m "feat(skill): state schema v2 — resolvedMode + split thread/commit pushbacks"
```

---

### Task 3: Mode Y algorithm (Y.0-Y.11) in SKILL.md

**Files:**
- Modify: `skills/step/SKILL.md` — add a new `## Algorithm: Mode Y — prAutopilotStepModeY(prNumber)` section after the existing Mode X algorithm; add a dispatch line at the top of `## Algorithm: prAutopilotStep(prNumber)`

- [ ] **Step 1: Add the mode dispatch at the algorithm entry**

At the start of `### 1. Fetch PR state` (or immediately after pre-flight), add:

```
# After pre-flight resolves `mode` (Task 1) and the mode-drift guard (Task 2):
if mode == "Y":
  return prAutopilotStepModeY(prNumber)   # see "Algorithm: Mode Y" below
# else fall through to Mode X (steps 1-11.5 unchanged)
```

- [ ] **Step 2: Add the Mode Y algorithm section**

After the last Mode X step (`### 11.5`), add a new top-level section `## Algorithm: Mode Y — prAutopilotStepModeY(prNumber)`. Transcribe BOTH the "Mode Y loop overview" ASCII flow AND the full step-by-step pseudocode (Y.0 through Y.11) from spec §"Mode Y — algorithm". Copy verbatim — the pseudocode is the canonical implementation. Then transcribe the "Mode Y design notes" subsection (final-pass deferral, pushback-counter rationale, approval-prose-PAUSE, refusal/approval heuristics).

- [ ] **Step 3: Verify the Mode Y steps are all present**

Run: `grep -nE "^# Y\.[0-9]|Y\.0\.5|Y\.4\.5|Y_8_review_commits" skills/step/SKILL.md`
Expected: hits for Y.0.5, Y.1, Y.2, Y.3, Y.4, Y.4.5, Y.5, Y.6, Y.7, Y.8, Y.9, Y.10, Y.11 (the comment-style step markers from the pseudocode).

Run: `grep -n "please address the pushback items" skills/step/SKILL.md`
Expected: 1 hit (the Y.10 re-trigger — confirms anti-spam/re-trigger logic transcribed).

- [ ] **Step 4: Verify dispatch wiring**

Run: `grep -n "prAutopilotStepModeY" skills/step/SKILL.md`
Expected: ≥2 hits (dispatch call + section header).

- [ ] **Step 5: Commit**

```bash
git add skills/step/SKILL.md
git commit -m "feat(skill): add Mode Y algorithm (SWE Agent fixes, Claude reviews)"
```

---

### Task 4: Fix SKILL.md internal contradictions (L68, L309)

**Files:**
- Modify: `skills/step/SKILL.md:68` and `skills/step/SKILL.md:309` (line numbers pre-Task-1/2/3; re-locate by content)

- [ ] **Step 1: Locate the L68 contradiction**

Run: `grep -n "Cannot do line-level fixes; gives prose feedback only" skills/step/SKILL.md`
Expected: 1 hit (the SWE Agent description that's wrong per PR #128).

- [ ] **Step 2: Fix the SWE Agent line-level-fix claim**

Replace `Cannot do line-level fixes; gives prose feedback only.` with:
`Applies line-level fixes by pushing commits (verified on exo-vault PR #128 — 7 fixes + a test file). Posts a conversational top-level comment alongside the commits.`

- [ ] **Step 3: Locate + fix the L309 final-pass trigger**

Run: `grep -n 'please review this PR — primary reviewers scored it ready' skills/step/SKILL.md`
Expected: 1 hit in the Mode X step-9b final-pass `copilot` case.

Replace the `gh pr comment ... "@copilot please review this PR ..."` line (which wrongly triggers SWE Agent) with the Code Review API trigger:

```bash
gh api repos/{owner}/{repo}/pulls/${prNumber}/requested_reviewers \
  -X POST -f 'reviewers[]=Copilot'
# NOTE: @copilot mention triggers SWE Agent, NOT Code Review (see §"Copilot has TWO products")
```

- [ ] **Step 4: Verify both contradictions resolved**

Run: `grep -nE "Cannot do line-level fixes|please review this PR — primary reviewers scored" skills/step/SKILL.md`
Expected: NO hits (matches verification-matrix V6).

- [ ] **Step 5: Commit**

```bash
git add skills/step/SKILL.md
git commit -m "fix(skill): correct SWE Agent fix-capability claim + final-pass Copilot trigger"
```

---

### Task 5: Mode Y triage section in REVIEW-TRIAGE-COPY.md

**Files:**
- Modify: `REVIEW-TRIAGE-COPY.md` — append a new top-level section

- [ ] **Step 1: Append the "Mode Y triage" section**

Add a new top-level section `## Mode Y triage — reviewing SWE Agent commits`. Transcribe from spec §"REVIEW-TRIAGE-COPY.md changes" — the Inputs / Per-hunk decision / Outputs / "When to skip thread fetch" bullets AND the example output comment template (the `## pr-autopilot Mode Y review — iteration {N}` markdown block).

- [ ] **Step 2: Add the skip-Mode-X-triage note**

At the top of the existing Mode X triage content, add one line: `> This section applies to **Mode X** (reviewer threads). For Mode Y (SWE Agent commits), see "Mode Y triage" below.`

- [ ] **Step 3: Verify**

Run: `grep -n "Mode Y triage — reviewing SWE Agent commits" REVIEW-TRIAGE-COPY.md`
Expected: 1 hit.
Run: `grep -n "pr-autopilot Mode Y review — iteration" REVIEW-TRIAGE-COPY.md`
Expected: 1 hit (the template).

- [ ] **Step 4: Commit**

```bash
git add REVIEW-TRIAGE-COPY.md
git commit -m "docs(triage): add Mode Y commit-review triage section"
```

---

### Task 6: PUSHBACK.md audit + Mode Y examples + behavior-change PAUSE rule

**Files:**
- Modify: `PUSHBACK.md`

- [ ] **Step 1: Read PUSHBACK.md and inventory its rules**

Run: `grep -nE "^#{1,3} |^- |^[0-9]+\." PUSHBACK.md`
Expected: a list of the existing rubric rules/headings. Note each rule's heading for Step 2.

- [ ] **Step 2: Annotate each existing rule with Mode applicability**

For every rule heading found in Step 1, add an inline tag: `**(Mode X & Y)**` if it applies to both reviewing a comment and reviewing a commit, or `**(Mode X only — review threads)**` if it's thread-specific. Judgment guide: rules about "interpreting reviewer intent" / "replying to a thread" are Mode X only; rules about "is this change correct / safe / in-scope" apply to both.

- [ ] **Step 3: Add the behavior-change PAUSE rule (Mode Y)**

Add a new rule section:

```markdown
## Behavior change without intent signal → PAUSE (Mode Y)

When reviewing a SWE Agent commit, if a hunk changes user-visible behavior
(comparison operators on eligibility/limits, default values, error vs success
paths, removed validation) AND the PR description / linked issue does not
explicitly call for that change, return **PAUSE**, not APPROVE.

Example (exo-vault PR #128): SWE Agent changed `age > 18` to `age >= 18`.
Defensible as a bug fix, but it shifts an eligibility cutoff. No issue asked
for it → PAUSE for human confirmation rather than silently approving.

Counter-example: SWE Agent renames a variable, fixes a typo, extracts a magic
number, adds a return-type annotation → APPROVE (no behavior change).
```

- [ ] **Step 4: Add a Mode Y examples block to 2-3 existing rules**

For the 2-3 rules most relevant to commit review (correctness, scope creep, missing tests), add a `**Mode Y example:**` line showing how the rule reads when the input is a commit hunk rather than a reviewer comment.

- [ ] **Step 5: Verify**

Run: `grep -n "Behavior change without intent signal" PUSHBACK.md`
Expected: 1 hit (matches verification-matrix V5 partial).
Run: `grep -nc "Mode Y" PUSHBACK.md`
Expected: ≥3 hits (the new rule + example annotations).

- [ ] **Step 6: Commit**

```bash
git add PUSHBACK.md
git commit -m "docs(pushback): audit for Mode Y + add behavior-change PAUSE rule"
```

---

### Task 7: EVAL.md — rename 17→17Y, add scenarios 22/23/24, mark follow-up resolved

**Files:**
- Modify: `EVAL.md`

- [ ] **Step 1: Mark the v0.2 follow-up resolved**

Run: `grep -n "v0.2 follow-up required" EVAL.md`
Expected: 1 hit (~line 158).

Replace that sentence with: `**v0.2 RESOLVED (this branch):** SKILL.md now first-classes both rotation modes — see docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md.`

- [ ] **Step 2: Rename Scenario 17 → 17Y in the scenario table**

In the scenarios table row for `17`, change the `#` cell to `17Y` and update the scenario name to `Mode Y happy path: Copilot SWE Agent each-iter, no Cursor`. Update the Phase 1 gating list (`EVAL.md:14`) to reference `17Y` instead of `17`.

- [ ] **Step 3: Add scenarios 22, 23, 24 to the table**

Append three rows to the scenarios table. Transcribe the descriptions from spec §"EVAL scenarios to add":
- `22 | Mode Y refusal handling | SWE Agent posts "I cannot help" | ABORT cleanly, informative notification, state file deleted`
- `23 | Mode Y ambiguous config ABORT | cursor.enabled=true + copilotSwe.mode=each-iter + primaryFixer=auto | ABORT at pre-flight asking user to set primaryFixer explicitly`
- `24 | Mode Y PAUSE on behavior change | PR hunk changes user-visible behavior (e.g. comparison operator on cutoff) | PAUSE at Y.10, state file KEPT, user notified`

- [ ] **Step 4: Update the gating sign-off section**

Run: `grep -n "When all 5 gating scenarios PASS" EVAL.md`
Expected: 1 hit (~line 170).

Replace "5 gating scenarios (1, 4, 8, 11, 17)" references with the v1.0.0 gate set from the spec: `1, 4, 8, 11, 17Y, 22, 23, 24`. Update the count text near `EVAL.md:78` accordingly.

- [ ] **Step 5: Verify**

Run: `grep -nE "17Y|Scenario 22|Scenario 23|Scenario 24| 22 \|| 23 \|| 24 \|" EVAL.md`
Expected: hits for 17Y and the three new scenarios.

- [ ] **Step 6: Commit**

```bash
git add EVAL.md
git commit -m "test(eval): rename 17->17Y, add Mode Y scenarios 22/23/24, expand v1.0.0 gate"
```

---

### Task 8: Doc reconciliation batch (ROADMAP, SHIP-INTEGRATION, COPILOT-SETUP, README, DESIGN)

**Files:**
- Modify: `ROADMAP.md`, `SHIP-INTEGRATION.md`, `reviewers/COPILOT-SETUP.md`, `README.md`, `docs/DESIGN.md`

- [ ] **Step 1: ROADMAP.md — rewrite v0.2 entry**

Replace the `## v0.2 — Cursor-native runtime adapter (Path C from spec)` heading + body with:

```markdown
## v0.2 — Two-mode rotation (current)

First-class Mode X (Claude fixes, agent reviews) AND Mode Y (Copilot SWE Agent
fixes, Claude reviews against PUSHBACK.md). Mode-aware pre-flight, primaryFixer
config. Spec: docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md.

## v0.3 — Auto-trigger
PostToolUse hook on `gh pr create` + install/allow slash commands + Mode Y final-pass.

## v0.4 — Safe auto-merge to dev
`gh pr merge --auto` to dev only (never master), guarded by neverMergeToBranches.

## v0.5 / Future — Cursor-native runtime adapter (Path C)
Port the loop layer to Cursor primitives. Algorithm unchanged; only the loop driver moves.
```

Leave the anti-roadmap section intact — auto-merge in v0.4 only targets dev with an explicit guard, so "user eyeballs production" still holds.

- [ ] **Step 2: SHIP-INTEGRATION.md — re-version v0.2 → v0.3**

Run: `grep -n "v0.2" SHIP-INTEGRATION.md`
Expected: hits at the title and the "v0.2+ planned behavior" heading.

Change `# /ship integration via Stop hook (Phase 2 — NOT IN v0.1.0)` and the "v0.2+ planned behavior (Phase 2)" heading to reference **v0.3**. Add a line: `Hook mechanism (Stop vs PostToolUse) will be decided in the v0.3 spec; the v0.2 rotation work does not add any hook.`

- [ ] **Step 3: COPILOT-SETUP.md — fix `@copilot` mention semantics**

Run: `grep -n "please review.*appears as a PR comment" reviewers/COPILOT-SETUP.md`
Expected: 1 hit (~line 24).

Replace lines 24-27 (the claim that `@copilot please review` triggers Code Review) with:

```markdown
Copilot **Code Review** is triggered by the requested-reviewers API, NOT by an
`@copilot` mention:

```bash
gh api repos/{owner}/{repo}/pulls/<PR#>/requested_reviewers -X POST -f 'reviewers[]=Copilot'
```

⚠ The `@copilot please review` mention triggers the **SWE Agent** (a different
product — reviewer + fixer). See `skills/step/SKILL.md` "Copilot has TWO products".
```

- [ ] **Step 4: README.md — add Mode X/Y overview**

Find the section describing the workflow (grep for "Mode X" or "review" near the top). Add a short subsection:

```markdown
### Two rotation modes

- **Mode X** — an external reviewer (Cursor / Copilot Code Review / Codex) reviews;
  Claude applies the fixes. Use when you want human-style review of Claude's work.
- **Mode Y** — Copilot SWE Agent applies the fixes and pushes commits; Claude reviews
  those commits against PUSHBACK.md and approves or flags behavior changes. Use when
  you have Copilot SWE Agent and want it to do the fixing.

Set `prAutopilot.primaryFixer` to `auto` (default), `claude` (force X), or
`copilotSwe` (force Y).
```

- [ ] **Step 5: DESIGN.md — add partial-supersession stub**

At the very top of `docs/DESIGN.md` (after the H1), insert:

```markdown
> **PARTIALLY SUPERSEDED:** Mode Y / rotation behavior is now specified in
> `docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md`.
> Sections here on auto-trigger and auto-merge remain canonical until the
> v0.3 / v0.4 specs land.
```

- [ ] **Step 6: Verify all five files**

Run: `grep -l "Two-mode rotation\|v0.3 — Auto-trigger" ROADMAP.md && grep -l "v0.3" SHIP-INTEGRATION.md && grep -l "requested_reviewers" reviewers/COPILOT-SETUP.md && grep -l "Two rotation modes" README.md && grep -l "PARTIALLY SUPERSEDED" docs/DESIGN.md`
Expected: all five filenames printed (each grep finds its marker).

- [ ] **Step 7: Commit**

```bash
git add ROADMAP.md SHIP-INTEGRATION.md reviewers/COPILOT-SETUP.md README.md docs/DESIGN.md
git commit -m "docs: reconcile roadmap/ship/copilot/readme/design for v0.2 rotation"
```

---

### Task 9: Version bump to 0.2.0

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Read current version**

Run: `grep -n '"version"' .claude-plugin/plugin.json`
Expected: `"version": "0.1.0"`.

- [ ] **Step 2: Bump to 0.2.0**

Change `"version": "0.1.0"` to `"version": "0.2.0"`.

- [ ] **Step 3: Verify it still parses as JSON**

Run: `jq empty .claude-plugin/plugin.json && jq -r '.version' .claude-plugin/plugin.json`
Expected: no parse error; prints `0.2.0`.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump plugin version to 0.2.0"
```

---

### Task 10: Pre-merge verification matrix (V1-V6)

No code changes — this task executes the verification matrix from the spec and records results. Each check that fails sends you back to the relevant earlier task.

- [ ] **Step 1: V6 — SKILL.md contradictions gone (cheapest, run first)**

Run: `grep -nE "Cannot do line-level fixes|please review this PR — primary reviewers scored" skills/step/SKILL.md`
Expected: NO hits. If any hit → return to Task 4.

- [ ] **Step 2: V4 — Pre-flight accepts Mode Y**

Create a scratch settings file and dry-run the derive_mode logic by reading SKILL.md's `derive_mode` against `{primaryFixer: auto, copilotSwe.mode: each-iter, cursor.enabled: false, copilot.mode: off, codex.mode: off}`. Confirm it yields `"Y"`, not ABORT.
Expected: resolved mode = Y. If ABORT → return to Task 1.

- [ ] **Step 3: V1 — derive_mode truth table**

Walk the `derive_mode` pseudocode against all 12 permutations (3 `primaryFixer` × 4 reviewer combos) listed in spec §"Pre-merge verification matrix". For each, confirm the documented expected result (X / Y / ABORT_CONFIG / ABORT_NO_DRIVER).
Expected: all 12 match. If any mismatch → return to Task 1, fix the rule, re-run.

- [ ] **Step 4: V2 + V3 — state schema round-trip + v1 migration**

V2: hand-write a v2 state JSON from the schema, confirm every field in the SKILL.md schema is present and typed.
V3: hand-write a v1 state file (no `stateSchemaVersion`), trace the Y.0.5 + migration logic, confirm it either starts fresh or upgrades in place per the documented decision (start-fresh on mode mismatch).
Expected: both behave as documented. If not → return to Task 2.

- [ ] **Step 5: V5 — PUSHBACK audit coverage**

Confirm every rule heading in PUSHBACK.md has either a Mode applicability tag or a Mode Y example.
Run: `grep -cE "Mode X & Y|Mode X only|Mode Y" PUSHBACK.md`
Expected: ≥ (number of rule headings). If short → return to Task 6.

- [ ] **Step 6: Record results + commit**

Add a `## v0.2 pre-merge verification` section to the bottom of `EVAL.md` with a V1-V6 pass/fail table and the date.

```bash
git add EVAL.md
git commit -m "test(eval): record v0.2 pre-merge verification matrix results"
```

---

### Task 11: Real-PR integration tests on exo-vault

These run the actual loop against real PRs. They gate the v1.0.0 tag (not the v0.2.0 feature release). Run after Tasks 1-10 are merged or on the feature branch with the plugin loaded via `claude --plugin-dir`.

- [ ] **Step 1: Mode X regression (Scenario 1)**

Config: `cursor.enabled=true, copilotSwe.mode=off, primaryFixer=auto`. Open an exo-vault PR with deliberate nits. Run `/loop /pr-autopilot:step <PR#>`. Confirm Mode X path runs end-to-end exactly as v0.1.0 (Claude fixes, reviewer re-scores, SUCCESS_STOP). Record in EVAL.md Scenario 1 results.
Expected: no regression. If broken → the dispatch in Task 3 Step 1 is misrouting; fix.

- [ ] **Step 2: Mode Y happy path (Scenario 17Y)**

Config: `copilotSwe.mode=each-iter, others off, primaryFixer=auto`. Open an exo-vault PR with neutral description + real smells. Run the loop. Confirm: `@copilot` posted once (not spammed), SWE Agent fixes, Claude posts structured review, all-APPROVE → SUCCESS_STOP. Record results.
Expected: matches PR #128 walkthrough. If `@copilot` spam → Task 3 Y.5 transcription error.

- [ ] **Step 3: Mode Y PAUSE (Scenario 24)**

Open an exo-vault PR where the SWE Agent fix will trip a behavior-change PAUSE (e.g., a comparison-operator change on a cutoff). Confirm autopilot PAUSEs at Y.10, posts the PAUSE notification, and KEEPS the state file. Record results.
Expected: PAUSE not SUCCESS. If it auto-approves → Task 6 PAUSE rule not wired into Task 3 Y.8 review.

- [ ] **Step 4: Scenarios 22 + 23**

- 22: configure Mode Y, open a PR SWE Agent will refuse → confirm clean ABORT + state deleted.
- 23: configure `cursor.enabled=true + copilotSwe.mode=each-iter + primaryFixer=auto` → confirm pre-flight ABORTs asking for explicit primaryFixer.
Record both in EVAL.md.

- [ ] **Step 5: Update EVAL.md gate status + commit**

Mark which of `1, 4, 8, 11, 17Y, 22, 23, 24` passed. If all pass, the v1.0.0 tag is unblocked (separate decision, not this plan).

```bash
git add EVAL.md
git commit -m "test(eval): record v0.2 real-PR integration results"
```

---

## Finishing the branch

After Tasks 1-10 pass (Task 11 may lag behind for real-PR scheduling), use `superpowers:finishing-a-development-branch` to decide merge strategy. Reminder per repo CLAUDE.md: do not push or merge without explicit user approval; `feature/v0.2-rotation` → `main` only after sign-off.

Per ExoVault memory `feedback_publish_after_tool_changes`: this branch changes SKILL.md (an executable runbook). If/when v0.2.0 is tagged and the plugin is published, users only get the rotation behavior after the publish step — merge alone does not ship it.
