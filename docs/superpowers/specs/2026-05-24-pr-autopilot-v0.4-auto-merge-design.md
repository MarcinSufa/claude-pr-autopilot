# pr-autopilot v0.4 — Safe Auto-Merge Design

**Date:** 2026-05-24
**Status:** Approved for implementation (design gate passed; pre-spec review folded in)
**Author:** Marcin Sufa + Claude
**Branch:** `feature/v0.4-auto-merge`
**Builds on:** v0.3 auto-trigger (merged, tag `v0.3.0`)

## Why this exists

After v0.2 (rotation) + v0.3 (auto-trigger), the loop still **stops at "ready to merge"** and the user merges by hand. v0.4 closes that last manual step — when the loop reaches SUCCESS, it can auto-merge the PR to the integration branch (dev). It is **opt-in, dev-only, CI-gated, and never touches master/main/production.** Auto-merge is loop-*terminal*, so it works for manually-started loops too (no hard dependency on v0.3 being proven live).

## Authorization posture (collides with the user's git rules — resolved deliberately)

`CLAUDE.md`: *"never commit/push unless explicitly asked"*, *"never auto-push to master without confirmation"*, *"feature → dev → master, never commit directly to master/dev without going through the flow."*

A PR merge feature→dev **is** "going through the flow" (a reviewed PR merge, not a direct commit). v0.4's authorization model honors the rules:

- **Opt-in per repo = the standing "explicit ask"** — a repo must be in `~/.pr-autopilot/automerge-repos` (separate from the v0.3 auto-trigger allowlist). Default = not present = auto-merge OFF, behavior identical to today (notify-and-stop).
- **Hard production guard** — base in `neverMergeToBranches` (`{master, main, production}`) is *never* auto-merged. Production promotion stays manual via `/land-and-deploy`.
- **CI-green required**; **never auto-invokes `/land-and-deploy`** (notify + recommend only).

## Feasibility constraints (verified)

1. **`gh pr merge --auto` QUEUES, it does not merge instantly.** Per `gh pr merge --help`: "If required checks have not yet passed, auto-merge will be enabled; if they have passed, the PR is added to the merge queue." So the merge completes *asynchronously* after branch protection / required checks clear. The design must treat "queued" and "merged" as distinct states.
2. **`--auto` requires the repo to have auto-merge enabled.** If not enabled, `--auto` errors; fall back to a direct `gh pr merge --squash` (safe because reviewers + CI are already green at SUCCESS_STOP).
3. **Branch protection is the backstop.** Even when auto-merge is queued, GitHub will not merge if branch protection requires human review/approvals the bot can't satisfy — the merge stays pending and v0.4 reports it, never forces it.

## Architecture

At the loop's **SUCCESS_STOP** (Mode X step 9c *and* Mode Y Y.10), call a shared sub-procedure **`safeAutoMerge(prNumber, baseRef)`**. It applies gates; if all pass, it queues the merge, records `autoMergeQueued`, and lets the existing loop lifecycle (step 2: `state == MERGED` → cleanup) finish the job on a later tick. If any gate fails, it falls back to the existing notify-and-stop (unchanged default).

```
loop reaches SUCCESS_STOP (reviewers green)
  → safeAutoMerge(prNumber, baseRef):
      GATE 1 opt-in:        repo in ~/.pr-autopilot/automerge-repos (case-insensitive, v0.3 hygiene)?  no  → notify + STOP
      GATE 2 not-paused:    ~/.pr-autopilot/paused absent?                                              no  → notify + STOP
      GATE 3 base-safe:     baseRef IN allowedTargetBranches {dev} AND NOT in neverMergeToBranches?       no  → notify "base <baseRef> not an auto-merge target; run /land-and-deploy" + STOP
      GATE 4 PR-ready:      PR open AND not draft?                                                       no  → notify + STOP
      GATE 5 CI-green:      all required checks green on current headRefOid (reuse step 5 logic)?        no  → notify + STOP
      GATE 6 idempotent:    state.autoMergeQueued already true?                                          yes → skip (do NOT re-queue); go to wait
      all pass →
        try: gh pr merge <N> --auto --squash --delete-branch
        on "auto-merge not enabled" error → gh pr merge <N> --squash --delete-branch   (direct; CI+reviews already green)
        state.autoMergeQueued = true; state.autoMergeAt = now()
        notify "PR #N auto-merge queued → <baseRef> (squash). Will complete when checks/branch-protection clear. Run /land-and-deploy for <baseRef>→master + deploy."
        save state; ScheduleWakeup(pollInterval)   # keep polling; do NOT delete state yet
  → next tick: MERGE-WAIT early branch (see below) handles it — NOT a normal review tick
```

## Merge-wait ticks (resolves pre-review Blocker 1 — the critical loop-control gap)

Once `state.autoMergeQueued == true`, every subsequent tick must **short-circuit** — it is waiting for GitHub to complete the queued merge, NOT for reviewers. Without this, the loop would re-enter step 9a final-pass and re-trigger Copilot/Codex every poll interval. Add this as the FIRST check after `### 0.5 Load state`, positioned **before the Mode dispatch** (the `if mode == "Y": return prAutopilotStepModeY(prNumber)` block). Placement is load-bearing: `safeAutoMerge` is called from BOTH Mode X (step 9c) and Mode Y (Y.10), so a Mode Y loop can also set `autoMergeQueued=true`. If step 0.6 sat after the dispatch (Mode-X-only), a queued **Mode Y** loop would skip it and fall into Y.5/Y.6 — re-posting `@copilot please review` and mis-incrementing `pollTicksWithoutActivity` (blocker 1's bug, but for Mode Y). Running before the dispatch also pre-empts Y.2's generic MERGED cleanup so the tailored "merged → run /land-and-deploy" message wins. Hence step **0.6** runs before any review logic of either mode:

```
# step 0.6 — merge-wait short-circuit (runs before any review logic)
if state.autoMergeQueued:
  pr = gh pr view <N> --json state,isDraft,mergeStateStatus
  if pr.state == MERGED:
    delete $STATE_FILE; notify "PR #N merged to <baseRef>. Run /land-and-deploy for <baseRef>→master + deploy."; return   # SUCCESS, terminate
  if pr.state == CLOSED:
    delete $STATE_FILE; notify "PR #N closed without merge — auto-merge abandoned"; return
  if pr.mergeStateStatus == DIRTY:                                     # DIRTY = GitHub's merge-conflict state (there is no "CONFLICTING"); BLOCKED falls through to the stuck-cap
    notify "PR #N auto-merge blocked (conflicts) — resolve, then re-run /pr-autopilot:step <N>"; return   # STOP, keep state
  state.pollTicksWhileQueued += 1
  if state.pollTicksWhileQueued >= config.pollTickCap:                  # stuck (e.g. branch protection needs human review)
    notify "PR #N auto-merge still pending after <pollTickCap> ticks — check PR / branch protection"; saveState; return   # STOP, keep state
  saveState; ScheduleWakeup(pollInterval); return                       # still queued — wait, skip steps 1-11
# (else: normal loop)
```

This makes scenario 34 (idempotent) fully specified: gate 6 prevents re-queue, AND step 0.6 prevents re-running review logic.

## Components

1. **`~/.pr-autopilot/automerge-repos`** — opt-in allowlist (newline `owner/repo`, case-insensitive match + line hygiene reused verbatim from the v0.3 gate logic: trim / skip-blank / require-`/`). Absent or empty ⇒ auto-merge off everywhere.
2. **`/pr-autopilot:automerge [owner/repo]`** — validate via `gh repo view --json nameWithOwner` and append the **canonical** `nameWithOwner` (mirrors `/pr-autopilot:allow`; case-insensitive gate tolerates casing regardless). Add-only; removal is a documented manual edit (`$EDITOR ~/.pr-autopilot/automerge-repos`).
3. **`skills/step/SKILL.md`** — define `safeAutoMerge` once; call from both SUCCESS_STOP sites. Extend the step-2 lifecycle/`autoMergeQueued` handling for the queued→merged transition.
4. **`prAutopilot.autoMerge` settings block** — config (in `~/.claude/settings.json`), all with safe hardcoded defaults so it works with zero config:
```json
{
  "prAutopilot": {
    "autoMerge": {
      "allowedTargetBranches": ["dev"],
      "neverMergeToBranches": ["master", "main", "production"],
      "mergeMethod": "squash"
    }
  }
}
```
The per-repo opt-in itself stays file-based (`~/.pr-autopilot/automerge-repos`), consistent with v0.3's `allowed-repos`; this block only tunes the *target* + *method* guards. Gate 3 requires base ∈ `allowedTargetBranches` AND ∉ `neverMergeToBranches`.

**Notification discipline:** exactly ONE notification per terminal outcome. Gate-1 fail (not opted in) → today's "PR #N ready; merge manually or run /land-and-deploy" (the existing step-9b message, unchanged). Gates pass → ONLY the "auto-merge queued" message (do NOT also fire the generic "ready"). Merge-wait terminal (merged / blocked / stuck) → its own single message. No double-notifying.

## Gate semantics (precise)

| Gate | Check | On fail |
|---|---|---|
| 1 — opt-in | repo (canonical `owner/repo`) in `~/.pr-autopilot/automerge-repos`, case-insensitive | notify "ready; merge manually or run /land-and-deploy"; STOP (DEFAULT path) |
| 2 — not paused | `~/.pr-autopilot/paused` absent (shared kill switch with v0.3) | notify + STOP |
| 3 — base safe | `baseRef` ∈ `allowedTargetBranches` (default `["dev"]`) AND ∉ `neverMergeToBranches` | notify "PR targets `<baseRef>` — not an auto-merge target. Run /land-and-deploy."; STOP. (Positive allowlist + blocklist: even if someone adds `staging` to never-merge, only explicitly-allowed targets merge.) |
| 4 — PR ready | `pr.state == OPEN` AND `pr.isDraft == false` | notify + STOP |
| 5 — CI green | all required checks green on `headRefOid` (same logic as step 5) | notify "reviewers green but CI not green — not auto-merging"; STOP |
| 6 — idempotent | `state.autoMergeQueued != true` | skip re-queue; proceed to wait |

All gates must pass to queue the merge. Gates 1 (default-off) + 3 (production guard) are the safety floor.

## Mode X vs Mode Y

`safeAutoMerge` is called at **both** terminal sites with the **same gates**:

- **Mode X** — after step 9b final-pass reviewers agree (when configured) → step 9c calls `safeAutoMerge`.
- **Mode Y** — Y.10 all-APPROVE → calls `safeAutoMerge`. Mode Y has no final-pass (v0.2 decision), but the SUCCESS there means **Claude reviewed every SWE-Agent commit against `PUSHBACK.md`** — substantive validation. Same gates apply; no extra Mode-Y precondition. (If real-PR experience shows Mode Y auto-merge needs to be stricter, that's a follow-up, not v0.4.)

"No unresolved reviewer threads" is already a SUCCESS_STOP precondition in Mode X (step 9); Mode Y's success is per-hunk APPROVE. So by the time `safeAutoMerge` runs, "reviewers satisfied" already holds — v0.4 adds the *merge-safety* gates on top.

## State file additions

```json
{
  "stateSchemaVersion": 3,
  "...existing v0.2/v0.3 fields...": "...",
  "autoMergeQueued": false,
  "autoMergeAt": "<iso>",
  "pollTicksWhileQueued": 0
}
```

- **`stateSchemaVersion: 3`** — bumped from v2 (v0.2). Migration: a v2 state file loads with `autoMergeQueued: false`, `pollTicksWhileQueued: 0` (defaults); no fresh-start needed (these fields are purely additive). The v1→Mode-Y ABORT guard (from v0.3) is unaffected.
- `autoMergeQueued` — set true once `gh pr merge` is called; **gate 6** reads it to avoid re-queuing, and **step 0.6** reads it to short-circuit into the merge-wait path.
- `autoMergeAt` — timestamp the merge was queued (telemetry / debugging).
- `pollTicksWhileQueued` — **dedicated** counter incremented ONLY in the step-0.6 merge-wait branch; compared to `pollTickCap` for stuck-queue detection. NOT `pollTicksWithoutReview` / `pollTicksWithoutActivity` (those drive the review lifecycle — a different concern).
- **Cleanup timing:** state file is deleted only when step 0.6 observes `state == MERGED` (or CLOSED), NOT when the merge is queued. The key correctness point — "queued" ≠ "merged".

## Error handling

| Condition | Behavior |
|---|---|
| `--auto` not enabled on repo | fall back to direct `gh pr merge --squash --delete-branch` — **synchronous**, merges now (CI + reviews already green). On success → delete state + notify "merged" (NOT "queued", no wait); if refused → notify "blocked" + STOP |
| Merge blocked (branch protection needs human approval, conflicts, no permission) | notify "auto-merge blocked, see PR #N"; **keep** state file; STOP (do not loop forever) |
| Queue stuck (open + `autoMergeQueued` beyond `pollTickCap` ticks) | notify "auto-merge still pending after `pollTickCap` ticks — check PR #N / branch protection"; STOP, keep state |
| PR merged externally while queued | **step 0.6** (runs before Mode dispatch) sees `MERGED` → cleanup + terminate; it pre-empts step 2 in the queued case |
| Gate failure | notify + STOP, default notify-and-stop behavior; no merge attempted |

**Recovery from a kept-state STOP (blocked/stuck):** the state file is intentionally retained so nothing is lost. To recover, the user either (a) resolves the PR (e.g. fixes conflicts / gets the required human approval) and re-runs `/pr-autopilot:step <N>` — step 0.6 picks up the queued merge and finishes — or (b) deletes `~/.pr-autopilot/<owner>-<repo>-<N>.json` to abandon. A dedicated `/pr-autopilot:clear <PR#>` is out of scope for v0.4 (manual cleanup documented in README).

## Reconciliation appendix

| File | Change |
|---|---|
| `skills/step/SKILL.md` | Add **step 0.6** merge-wait short-circuit (queued→merged/blocked/stuck), **placed before the Mode dispatch block** so it guards Mode X and Mode Y alike; add `safeAutoMerge` sub-procedure; call from Mode X step 9c + Mode Y Y.10; bump state schema to v3 + new fields; add stop-conditions rows ("merge queued/waiting", "merge blocked", "merged after queue") |
| `ROADMAP.md` | Mark v0.4 "in progress / current"; keep v0.5 (Cursor) + v1.0.0 ordering; anti-roadmap stays (production merges manual) |
| `README.md` | Add "Auto-merge (v0.4, beta)" section: `/pr-autopilot:automerge <repo>` → dev-only, never master, CI-gated; **beta until real-PR dogfood**; same exo-vault-only rollout caution as v0.3. State the **dual setup** for full hands-off: a repo needs BOTH `/pr-autopilot:allow` (v0.3 auto-trigger) AND `/pr-autopilot:automerge` (v0.4 auto-merge) — they are separate allowlists. Repeat the v0.3 **laptop-awake** caveat: merge-wait ticks use `ScheduleWakeup`, so the machine must stay awake until the queued merge completes. |
| `SHIP-INTEGRATION.md` | Note the handoff: after dev auto-merge, run `/land-and-deploy` for dev→master + deploy; pr-autopilot does NOT promote to master or deploy |
| `docs/DESIGN.md` | Supersede the "user merges manually" section — point to this spec; note auto-merge is opt-in + dev-only |
| `.claude-plugin/plugin.json` | Bump to `0.4.0`; new `/pr-autopilot:automerge` auto-discovered from `skills/automerge/SKILL.md` |

## Deliverables checklist

- [x] `skills/step/SKILL.md` — `safeAutoMerge` + both call sites (9c, Y.10) + step 0.6 merge-wait (queued→merged lifecycle, before Mode dispatch) + state fields + config block + stop-conditions/error rows
- [x] `skills/automerge/SKILL.md` — `/pr-autopilot:automerge` command
- [x] `ROADMAP.md`, `README.md`, `SHIP-INTEGRATION.md`, `docs/DESIGN.md` — reconciliation
- [x] `EVAL.md` — scenarios 31–38
- [x] `.claude-plugin/plugin.json` → `0.4.0`

## EVAL scenarios (new for v0.4)

- **31 — Auto-merge off (default):** repo NOT in `automerge-repos`, loop SUCCEEDs → PushNotification + STOP, no `gh pr merge`. (Confirms zero behavior change by default.)
- **32 — Base master blocked:** opt-in repo, PR base = master, reviewers green → Gate 3 refuses; notify "run /land-and-deploy"; no merge.
- **33 — Happy queue:** opt-in repo, base = dev, non-draft, CI green → `gh pr merge --auto --squash --delete-branch` called once; notify says **queued**; `autoMergeQueued=true`; state kept.
- **34 — Idempotent:** next SUCCESS_STOP tick with `autoMergeQueued=true` → Gate 6 skips; does NOT re-call merge.
- **35 — Paused suppresses merge:** `~/.pr-autopilot/paused` present, opt-in repo, loop SUCCEEDs → Gate 2 refuses; no merge.
- **36 — Queued→merged cleanup:** after queue, a later tick (step 0.6) observes `state == MERGED` → state file deleted, notify "merged", terminate.
- **37 — Direct-merge fallback:** opt-in repo, base dev, but the repo does NOT have GitHub auto-merge enabled → `gh pr merge --auto` errors → fall back to direct `gh pr merge --squash --delete-branch` (CI + reviews already green); notify accordingly.
- **38 — Blocked-merge state cleanup:** merge-wait hits `DIRTY`/stuck → STOP keeping state; verify the documented recovery (resolve the PR, then re-run `/pr-autopilot:step <N>` OR delete `~/.pr-autopilot/<owner>-<repo>-<N>.json`) clears the zombie state.

## Verification matrix

| # | Check | How |
|---|---|---|
| M1 | `automerge-repos` matching (case-insensitive, hygiene) | reuse/adapt the v0.3 gate-script matching; unit-test the helper if extracted, else walkthrough |
| M2 | Gate table walkthrough | trace `safeAutoMerge` against scenarios 31–35; confirm each gate's STOP/notify |
| M3 | Queued→merged lifecycle | trace 33→36: queue sets `autoMergeQueued`, state kept; MERGED tick cleans up |
| M4 | `--auto` direct fallback | trace the "auto-merge not enabled" branch → direct squash |
| M5 | plugin validate --strict + markdownlint | `claude plugin validate . --strict`; CI lint |
| M6 | Real-PR dogfood (deferred) | opt-in a real dev-targeted exo-vault PR; confirm queue → merge → cleanup; confirm a master-base PR is refused |

## Out of scope (deferred)

- Master/main/production auto-merge (permanent anti-roadmap — manual via `/land-and-deploy`)
- Auto-invoking `/land-and-deploy` (notify + recommend only)
- Auto-merge without the per-repo opt-in
- Mode Y final-pass reviewers (own later spec)
- Cursor-native runtime port (v0.5 / Future)

## Release sequencing

v0.4.0 ships to `main` when implemented + verified (M1–M5). Per ROADMAP, v1.0.0 (stability stamp) comes after v0.3/v0.4. Safe rollout: `automerge-repos` starts empty (off everywhere); first opt-in is `MarcinSufa/exo-vault`, and the first real dev-targeted auto-merge (scenario 33→36) is the live dogfood that flips v0.4 beta→GA.
