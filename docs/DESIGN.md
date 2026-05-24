# `/pr-autopilot` — Automated PR Review Loop Skill

> **PARTIALLY SUPERSEDED:** Mode Y / rotation behavior is now specified in
> `docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md`.
> Sections here on auto-trigger and auto-merge remain canonical until the
> v0.3 / v0.4 specs land.

**Date:** 2026-05-23 (revised eight times — three Composer 2.5 review rounds, v4 rename + packaging, v4-final CLEARED, v5 multi-reviewer matrix, v6 stack alignment, v6-final CONDITIONAL CLEAR resolved: 8 blockers + 6 nits baked in — non-goals/Phase 1 scope/loop outcome/state-file counter/EVAL 2/ScheduleWakeup reason/Actors table/STOP pseudocode aligned with multi-reviewer reality; new config→algorithm derivation table; EVAL step 0 expanded to both Cursor and Copilot; scenario 21 covers leftover-Copilot edge case)
**Status:** ✅ **CLEARED by Composer v6-final review** (9.5/10 design, 9.5/10 spec consistency, 9/10 Phase 1 shippability). Ready for Phase 1 implementation.
**Type:** New Claude Code plugin, distributed as the standalone repo `claude-pr-autopilot` (installed via `/plugin marketplace add MarcinSufa/claude-pr-autopilot`)
**Distribution:** See "Distribution & Packaging" section below — repo mirrors the [`claude-watch-video`](https://github.com/MarcinSufa/claude-watch-video) layout (plugin.json + marketplace.json + SKILL.md at root + CI smoketest)

## Summary

A Claude Code plugin (`pr-autopilot`, distributed as the `claude-pr-autopilot` repo) that closes the loop between PR review and Claude-driven fixes via a pluggable reviewer-adapter framework. **Phase 1 (this spec):** user invokes `/loop /pr-autopilot:step <PR#>` manually after `/ship`. Each tick fetches the latest reviews from all enabled per-iteration reviewers (default: Cursor's GitHub App; Copilot as final-pass), applies fixes or pushes back on disagreements, commits, pushes, and waits for the next round. Exits when ALL enabled per-iteration reviewers report success AND any final-pass reviewers agree, with ten safety stops along the way (caps on fix iterations, poll ticks, no-progress stall, plus config-validation/CI/branch/lint/PR-state guards). **v0.1.0 scope:** multi-reviewer adapter framework, with only two configurations gated by EVAL — default (Cursor + Copilot-final) and one alt (Copilot each-iter, scenario 17). Codex CLI and `claudeSelf` adapters are spec'd but experimental. **Phase 2:** add a Stop hook in `~/.claude/settings.json` that auto-invokes the loop after `/ship` completes — only after Phase 1 passes the gating EVAL scenarios.

Runs on the user's existing Claude Code subscription and Cursor subscription. **No Anthropic API key required. No GitHub Action required. No webhook server required.**

## Distribution & Packaging

Mirror the `claude-watch-video` repo layout: standalone GitHub repo, Claude Code marketplace plugin, semver in plugin.json, CI smoketest, MIT license.

### Repo

- **Name:** `claude-pr-autopilot`
- **Owner:** `MarcinSufa`
- **URL:** `https://github.com/MarcinSufa/claude-pr-autopilot`
- **License:** MIT (same as claude-watch-video)
- **Starting version:** `0.1.0` — honest pre-release signal. Bump to `1.0.0` only after Phase 1 EVAL gating scenarios (1, 4, 8, 11, **17**) pass on a real exo-vault PR. Scenario 17 (Copilot each-iter alt config) was added in v5 as a gate to prove the multi-reviewer adapter abstraction works end-to-end.

### Layout

```
claude-pr-autopilot/
├── .claude-plugin/
│   ├── plugin.json              ← name, version (semver), author, homepage, repo, license, skills path
│   └── marketplace.json         ← marketplace metadata with single plugin entry
├── .github/
│   └── workflows/
│       └── smoketest.yml        ← schema validation + markdownlint (ubuntu-latest only for v0.1.0; expand later)
├── .gitignore                   ← copied from claude-watch-video; tailored to skill artifacts (.pr-autopilot/, credentials)
├── LICENSE                      ← MIT
├── README.md                    ← marketing + walkthrough + badges (mirrors claude-watch-video style)
├── ROADMAP.md                   ← leverage-ranked future improvements (Phase 2, multi-PR mode, cloud routine, etc.)
├── SKILL.md                     ← the skill entry: /pr-autopilot:step <PR#>, callable by /loop dynamic mode
├── PUSHBACK.md                  ← reviewer-comment judgment rubric (shared across reviewers)
├── REVIEW-TRIAGE-COPY.md        ← copy + parameterization of gstack/review/greptile-triage.md (now multi-login dispatching)
├── reviewers/                   ← per-reviewer adapters and setup docs (v5 multi-reviewer)
│   ├── CURSOR-SETUP.md          ← one-time Cursor agent rule + laptop-awake + 7-day expiry callouts
│   ├── COPILOT-SETUP.md         ← `@copilot review` trigger contract, per-iter vs final-only mode
│   ├── CODEX-SETUP.md           ← `codex review --diff` invocation, postCommentsToPR option
│   └── CLAUDE-SELF-SETUP.md     ← explains SELF-REVIEW-RUBRIC.md authoring and final-pass semantics
├── SELF-REVIEW-RUBRIC.md        ← default rubric for `claudeSelf` reviewer (user-editable per repo)
├── EVAL.md                      ← test scenarios 1-21 + pre-flight step 0
├── SHIP-INTEGRATION.md          ← PHASE 2 PLACEHOLDER: Stop hook JSON for ~/.claude/settings.json (added in v0.2+, empty stub in v0.1.0)
└── docs/
    ├── DESIGN.md                ← this spec, migrated; single source of truth for architecture
    ├── marketplace-submission.md ← drafted later; matches watch-video's submission format
    └── examples/                ← real-PR walkthrough(s) once we have one
```

### `plugin.json` template

```json
{
  "name": "pr-autopilot",
  "version": "0.1.0",
  "description": "Automated PR review loop: Cursor reviews, Claude fixes, iterate until merge-ready. Open PR, walk away, come back when it's 5/5.",
  "author": {
    "name": "Marcin Sufa",
    "email": "sufa.marcin@gmail.com"
  },
  "homepage": "https://github.com/MarcinSufa/claude-pr-autopilot",
  "repository": "https://github.com/MarcinSufa/claude-pr-autopilot",
  "license": "MIT",
  "keywords": [
    "github",
    "pull-request",
    "code-review",
    "cursor",
    "automation",
    "claude-code",
    "loop"
  ]
}
```

### `marketplace.json` template

```json
{
  "name": "claude-pr-autopilot",
  "metadata": {
    "description": "Automated PR review loop. Cursor reviews, Claude fixes, iterate until merge-ready."
  },
  "owner": {
    "name": "Marcin Sufa",
    "email": "sufa.marcin@gmail.com"
  },
  "plugins": [
    {
      "name": "pr-autopilot",
      "description": "Open a PR, run /loop /pr-autopilot:step <PR#>, walk away. Cursor reviews, Claude reads the review and either fixes or pushes back with reasoning, pushes, waits for Cursor to re-review. Exits when Cursor scores 5/5 (with 10 independent safety stops). Optionally pings @copilot for a final sanity check.",
      "author": {"name": "Marcin Sufa"},
      "source": "./",
      "category": "productivity",
      "homepage": "https://github.com/MarcinSufa/claude-pr-autopilot"
    }
  ]
}
```

### Install command

```bash
/plugin marketplace add MarcinSufa/claude-pr-autopilot
/plugin install pr-autopilot@claude-pr-autopilot
```

After install, files land at `~/.claude/plugins/marketplaces/claude-pr-autopilot/plugins/pr-autopilot/`. The slash command `/pr-autopilot:step <PR#>` becomes available in any Claude Code session.

### Versioning policy

- **0.1.0** — Phase 1 v1: manual `/loop /pr-autopilot:step <PR#>` after `/ship`. EVAL gating scenarios (1, 4, 8, 11, 17) not yet run on real PR.
- **0.2.0 – 0.x.0** — bug fixes from real-PR runs; cursor login string verified and committed; minor algorithm refinements.
- **1.0.0** — Phase 1 gating scenarios (1, 4, 8, 11) verified passing on real exo-vault PR. Stable manual API.
- **1.1.0+** — Phase 2: Stop hook auto-chain in `~/.claude/settings.json` after `/ship`.
- **2.0.0** — breaking changes (e.g., multi-PR mode reshaping the CLI, cloud routine variant, reviewer-plugin abstraction).

Tag releases in git: `v0.1.0`, `v0.2.0`, etc. CHANGELOG.md updated per release (no separate file in v0.1.0 — start one once we have a second version).

### CI smoketest

`/.github/workflows/smoketest.yml` runs on push to `main` and on every PR. Two jobs:

**Job 1: schema validation** (always runs)
- Validate `plugin.json` against [Anthropic plugin schema](https://docs.claude.com/en/docs/claude-code/plugins) (or basic JSON schema if no official one exists)
- Validate `marketplace.json` structure
- Validate `SKILL.md` YAML frontmatter (`name`, `description` present)
- Cheap: ~5s, no dependencies beyond `python -c "import json"` or `jq`

**Job 2: markdown lint** (always runs)
- `markdownlint-cli` on all `*.md` files
- Catches broken links, dead anchors, formatting drift
- ~10s, runs on ubuntu-latest only (no OS-specific markdown concerns)

**Matrix:** ubuntu-latest only for v0.1.0. Add windows-latest at v0.5+ if we ship anything OS-specific (e.g., a setup script).

**Explicitly NOT in CI v0.1.0:** jq snippet validity check (defer to v0.5+ if we hit a typo), end-to-end dry run against synthetic PR (defer to v1.0).

Total CI time: under 30s. Matches claude-watch-video's "start cheap, expand on signal" philosophy.

### Spec location: this document migrates

This spec lives at `c:\Users\sufam\IdeaProjects\agent test\exo-vault\docs\superpowers\specs\2026-05-23-grep-loop-skill-design.md` during the design phase. When the standalone repo is created, **the spec is copied to `claude-pr-autopilot/docs/DESIGN.md` as the single source of truth**. The ExoVault copy is reduced to a one-line stub:

```markdown
# Migrated to standalone repo

Design now lives at: https://github.com/MarcinSufa/claude-pr-autopilot/blob/main/docs/DESIGN.md

This stub preserved for git-blame continuity with the original brainstorming session.
```

The filename `2026-05-23-grep-loop-skill-design.md` is preserved despite the rename (git history continuity beats filename accuracy).

## Runtime & target platform

- **Skill runtime:** Claude Code (running as the VSCode extension on Windows 11). Plugin files land under `~/.claude/plugins/marketplaces/claude-pr-autopilot/plugins/pr-autopilot/` after `/plugin install`. Hooks live in `~/.claude/settings.json`.
- **Shell:** Bash via Claude Code's Bash tool (not PowerShell). All commands in this spec assume Bash. The Windows native shell is PowerShell, but the Bash tool is available; the spec deliberately targets Bash to keep parsing portable.
- **Required CLI tools (must be on PATH):** `gh` (with auth), `jq`, `git`. No `grep -oP` (GNU Perl regex); all regex done in `jq`.
- **Not in scope:** Cursor IDE's own `/loop` (which uses `AGENT_LOOP_TICK_*` sentinels and `.cursor/hooks.json`) — different product, different runtime. Cursor's role here is **strictly the reviewer side** via its GitHub App, not the runtime for any part of this skill.

## Goals

- **Zero-touch fix loop (Phase 2)**: Claude creates PR → loop runs unattended → user notified when PR hits 5/5
- **Portable across repos**: works in `exo-vault`, `concretego-web`, `sysdyne-ui`, `git-timesheet`, or any GitHub repo with `gh` CLI access
- **Safe by default**: respects branch protection rules, refuses to push on red CI, caps at 5 fix iterations and 10 poll ticks, runs full pre-commit suite before every push
- **Independent review**: enabled reviewers (Cursor by default; optionally Copilot / Codex / Claude-self) review; Claude fixes — no self-grading on the primary loop (claudeSelf is final-pass only by design)
- **Token-budget friendly**: runs on existing subscriptions, no per-token API spend
- **Reuse, don't reinvent**: wraps the existing `gstack/review/greptile-triage.md` pattern; doesn't duplicate its classification, reply, suppression, or escalation logic

## Non-goals (v1)

- Multi-PR mode (`/pr-autopilot` with no arg, iterating across all open PRs)
- Per-repo `loop-rules.md` config file (defer until `PUSHBACK.md` proves insufficient)
- Cloud / scheduled-routine variant (laptop must be on while loop runs — bold callout in `CURSOR-SETUP.md`)
- Greptile / CodeRabbit as primary reviewers (not in v0.1.0 — would need new adapters; Cursor / Copilot / Codex / claudeSelf adapters ARE supported via the multi-reviewer framework added in v5)
- Automatic merge after 5/5 — user always eyeballs and clicks merge
- Reviewing reviewers other than those listed in the per-reviewer config block (`reviewers.cursor.login`, `reviewers.copilot.login`, etc.)

## Phase 1 / Phase 2 plan

| Phase | Scope | Gate to next phase |
|---|---|---|
| **Phase 1** | `skills/step/SKILL.md` (the `/pr-autopilot:step` skill) + `PUSHBACK.md` + `REVIEW-TRIAGE-COPY.md` (multi-login) + `reviewers/CURSOR-SETUP.md` + `reviewers/COPILOT-SETUP.md` + multi-reviewer config schema + `EVAL.md` (scenarios 1, 4, 8, 11, 17 gated; 18, 19, 20a, 20b spec'd not gated). **Manual invocation only**: user types `/loop /pr-autopilot:step <PR#>` after `/ship`. Stubs (empty in v0.1.0): `reviewers/CODEX-SETUP.md`, `reviewers/CLAUDE-SELF-SETUP.md`, `SELF-REVIEW-RUBRIC.md`, `SHIP-INTEGRATION.md`. | EVAL scenarios 1, 4, 8, 11, **17** pass on a real exo-vault PR. Confirm actual Cursor and Copilot GitHub App logins via EVAL step 0 and update config defaults. |
| **Phase 2** | Add Stop hook in `~/.claude/settings.json` that detects `gh pr create` in recent tool calls, extracts PR#, and auto-invokes `/loop /pr-autopilot:step <PR#>`. Per-session disable via `PR_AUTOPILOT_DISABLE=1`. | N/A — production. |

Composer's gate rationale (adopted): **the Stop hook is the highest-risk integration (unattended commits firing without user present); prove the core judgment loop works first.**

## Actors and responsibilities

| Actor | Responsibility | Where it runs |
|---|---|---|
| `/ship` (existing gstack skill) | Tests pass → bump VERSION → commit → push → create PR | User's Claude Code window |
| User (Phase 1) or Stop hook (Phase 2) | Invoke `/loop /pr-autopilot:step <PR#>` after `/ship` | User's Claude Code window |
| `/loop` (existing Claude Code skill, **dynamic mode**) | Run `/pr-autopilot:step <PR#>`; when inner calls `ScheduleWakeup`, fire again at the scheduled time; when inner omits the call, exit | Claude Code harness |
| `/pr-autopilot:step <PR#>` (NEW skill) | One iteration: fetch review → triage via shared pattern → fix/push-back → commit → push → either call `ScheduleWakeup(90s, …)` to continue or omit to STOP | User's Claude Code window |
| **Shared `review-triage` pattern** | Reviewer-agnostic fetch/classify/reply/suppress/escalate. **Wraps `c:/Users/sufam/.claude/skills/gstack/review/greptile-triage.md`**; `/pr-autopilot:step` invokes it with multi-login dispatch (one or more reviewer logins from per-iter reviewers) + per-reviewer score parser. | Subroutine of `/pr-autopilot:step` |
| State file at `~/.pr-autopilot/<owner>-<repo>-<pr>.json` | Persists fix-iteration count, poll-tick count, stall-tick count, last-handled-headOid, last-seen-review-id, history of pushback replies | Local FS |
| **Reviewer adapters (v5)** | Pluggable backends each with the 5-op contract (`trigger`, `fetchOutcome`, `isSuccess`, `postPushback`, `description`). Dispatched per `config.reviewers` entry: `cursor` (GH App), `copilot` (GH App with @copilot trigger), `codex` (local CLI), `claudeSelf` (internal). See "Reviewer adapters" section. | Subroutines of `/pr-autopilot:step` |
| Cursor GitHub App | Auto-review every push on enrolled repos; emit `Score: N/5` line per `reviewers/CURSOR-SETUP.md` instructions. Underlying model is Cursor config (Composer 2.5 / GPT-5.5 / Codex / Claude). | Cursor cloud infra |
| GitHub Copilot (review service) | Review on demand when a PR comment mentions `@copilot please review`. Posts line-level threads + summary. Mode (each-iter / final-only / off) per config. | GitHub-side, free with Copilot seat |
| `gh` + `jq` CLIs | All GitHub I/O and JSON parsing | Subprocesses of `/pr-autopilot:step` |
| `PushNotification` tool (Claude Code built-in) | Desktop notification when loop terminates with success or PAUSE | Claude Code harness |

## Reviewer adapters (multi-reviewer model, v5)

The skill supports **four reviewer backends**, each pluggable independently. Configuration is in `prAutopilot.reviewers` (see Configuration section). Each reviewer participates in zero or more of: per-iteration loop reviewing, final-pass sanity check.

### Reviewer contract

Every reviewer adapter exposes the same five operations (callable by the algorithm):

1. **`trigger(prNumber)`** — if needed, kick the reviewer into action. (Cursor auto-triggers on push, so no-op. Copilot needs `gh pr comment ${prNumber} --body "@copilot please review"`. Codex needs `codex review --diff origin/main..HEAD`. Claude-self needs nothing — runs inline.)
2. **`fetchOutcome(prNumber, sinceCommit)`** — return `{ hasReviewed: bool, openThreads: [...], score: 1-5 | "pass" | "fail" | null, raw: ... }`. Idempotent — safe to call repeatedly without re-triggering.
3. **`isSuccess(outcome)`** — return bool. Definition varies: `cursor` → `score==5 && openThreads==0`; `copilot` → `openThreads==0`; `codex` → `score=="pass"`; `claudeSelf` → `score==5`.
4. **`postPushback(threadId, reason)`** — for reviewers that have PR threads (cursor, copilot). No-op for codex/claudeSelf which don't post.
5. **`description()`** — human-readable name for log lines.

### Per-reviewer notes

#### `cursor` — primary loop reviewer, GH App
- Trigger: auto on push if Cursor GitHub App enrolled (see `reviewers/CURSOR-SETUP.md`)
- Score: parse `Score: N/5` from review body. Setup doc instructs Cursor agent to emit this line.
- **Underlying model is a Cursor config, not a `pr-autopilot` config.** In Cursor's Background Agent rules, you pick which model reviews: Composer 2.5 (default and recommended for review tasks), GPT-5.5, **Codex (via Cursor)**, or Claude. All produce the same `Score: N/5` line per the setup doc. The `pr-autopilot` skill is model-agnostic — it just sees a review from `cursor[bot]` regardless of which underlying model Cursor used.
- Setup doc: `reviewers/CURSOR-SETUP.md` (includes model-choice guidance)
- Cost: Cursor Pro ($20/mo) for Background Agents — applies per-PR within plan limits regardless of model choice

#### `copilot` — primary or final, GH App
- Trigger (each-iter): `gh pr comment ${prNumber} --body "@copilot please review"` after every push
- Trigger (final-only): single comment at end with merge-readiness context
- Score: no native 1-5. STOP signal = "all Copilot-authored review threads resolved." Optionally can ask Copilot in the trigger comment to emit a score line; not relied on in v0.1.0.
- Setup doc: `COPILOT-SETUP.md` (new in v5)
- Cost: Copilot seat — within Pro+ quota of ~1500 premium requests/mo. Each-iter mode burns ~5 per PR; final-only burns 1.

#### `codex` (standalone CLI) — primary or final, local invocation
- **Two ways to use Codex with this skill:**
  1. **Codex via Cursor** (recommended path): just pick Codex as the model in your Cursor Background Agent rules — handled by the `cursor` adapter, no separate adapter, no extra sub beyond Cursor Pro.
  2. **Codex via standalone CLI** (this adapter): for users with a Codex Pro CLI subscription who want Codex to run independently of Cursor (e.g., as a second opinion alongside Cursor reviews).
- Trigger (standalone CLI mode): `codex review --diff origin/${pr.baseRefName}..HEAD --format json` (or whatever flags map to the `/codex` skill's review mode)
- Score: pass/fail gate from Codex's stdout. Optionally parse 1-5 if Codex's review prompt asks for it (extend in v0.2+).
- `postCommentsToPR`: if `true`, the skill posts a `## Codex review (iteration N)` PR comment with findings (collaborators see it); if `false`, processed internally only.
- Setup doc: `reviewers/CODEX-SETUP.md`
- Cost (standalone CLI mode): Codex Pro CLI sub (~$100/mo). Each-iter mode burns ~5 Codex turns per PR. **Off by default** in v0.1.0 — most users get better value picking Codex as the Cursor Background Agent model and saving the extra sub.

#### `claudeSelf` — final-pass only, internal
- Trigger: Claude reads `pr.headRefOid` diff vs `pr.baseRefName`, evaluates against `SELF-REVIEW-RUBRIC.md`, emits 1-5 score and list of "would-fix" items
- **Why final-only?** Claude grading Claude's own fixes converges immediately (we already think it's correct, that's why we wrote it). The value of `claudeSelf` is a final disciplined pass against a rubric you control, not loop iteration. If used per-iter, it always returns success → defeats the loop.
- Score: 1-5 from rubric; STOP signal = `score == 5`
- Setup doc: `CLAUDE-SELF-SETUP.md` (new in v5) — mostly explains `SELF-REVIEW-RUBRIC.md` authoring
- Cost: Claude Code sub absorbs (~1 extra turn per PR, only at the end)

### Combined STOP rule

```
PER_ITER_REVIEWERS = [r for r in {cursor, copilot, codex} if r.enabledForEachIter]
FINAL_PASS_REVIEWERS = [r for r in {claudeSelf, copilot, codex} if r.enabledForFinal]

# All per-iter reviewers happy AND no leftover unresolved threads we haven't already pushed back on
# (the second clause matches Algorithm step 9's `unresolved_not_ours.length == 0` precondition)
success_this_tick = (
    ALL(r.isSuccess(r.fetchOutcome()) for r in PER_ITER_REVIEWERS)
    AND unresolved_not_ours.length == 0
)

if success_this_tick:
    for r in FINAL_PASS_REVIEWERS:
        outcome = r.trigger(); outcome = r.fetchOutcome()
        if NOT r.isSuccess(outcome):
            return PAUSE("final-pass reviewer ${r.description} disagreed: ${outcome.summary}")
    PushNotification("PR ready — all reviewers green")
    return SUCCESS_STOP
```

If a final-pass reviewer disagrees with the per-iteration consensus, we PAUSE (don't ABORT) so the user can decide: re-run with the final-pass reviewer added to per-iter, or merge anyway, or address manually.

### Validation: must have at least one per-iter reviewer

Config validation at skill start:
```
if NOT any(r.enabledForEachIter for r in {cursor, copilot, codex}):
    return ABORT("config error: at least one reviewer must be enabled for per-iteration; nothing would drive the loop")
```

`claudeSelf` cannot satisfy this (it's final-only by design).

### v0.1.0 reviewer-mode gating

Only **two** reviewer configs are gated for v0.1.0 release (per the Phase 1 EVAL):

1. **Default config** (Cursor primary + Copilot final-only) — must pass EVAL scenarios 1, 4, 8, 11
2. **One alternative config** (e.g., Copilot each-iter only, no Cursor) — must pass EVAL scenario 17 (new)

Other combinations (Codex primary, Cursor+Copilot dual per-iter, Claude-self final) are spec'd as supported but not gated until v0.2+. Documented as "experimental" in `README.md`.

## Loop integration contract (Composer's P0 #1)

`/loop` is used in **dynamic mode** — no interval argument. The inner skill (`/pr-autopilot:step`) drives the schedule:

```
User (or Stop hook): /loop /pr-autopilot:step 123

→ Claude Code harness invokes /pr-autopilot:step 123
→ Skill runs one iteration
→ At end of iteration, skill either:
    (a) calls ScheduleWakeup(delaySeconds=90, prompt="/loop /pr-autopilot:step 123",
                             reason="polling for reviewer re-review")
        → harness wakes the skill 90s later; loop continues
    (b) does NOT call ScheduleWakeup
        → loop terminates cleanly; harness surfaces the final message
```

**This replaces** the earlier `CONTINUE | STOP | ABORT | PAUSE` return-string concept. The contract uses primitives that already exist in the Claude Code tool registry — `ScheduleWakeup` is documented and supported in `/loop` dynamic mode. The skill body still tracks four logical outcomes internally (continue / success-stop / abort / pause), but the externalization to `/loop` is purely "call ScheduleWakeup or don't."

**7-day expiry footnote (`CURSOR-SETUP.md`):** Claude Code dynamic scheduled tasks expire after 7 days per the scheduled-tasks docs. With a 90s poll interval, a single `/loop /pr-autopilot:step <PR#>` invocation can theoretically tick ~6,720 times before hitting that ceiling — far beyond any reasonable PR review cycle. But document the ceiling so nobody expects an infinite babysit on a long-stalled PR, and recommend manually re-invoking if a PR sits in pushback purgatory for over a week.

Outcome → action mapping:

| Outcome | What skill does | What `/loop` sees |
|---|---|---|
| Iteration did work or is waiting; check again | Print iteration summary; **call ScheduleWakeup(90s)** | Loop continues |
| Success: all per-iter reviewers report success (e.g., Cursor score=5, Copilot 0 unresolved threads, Codex pass) AND all final-pass reviewers agree (see Algorithm steps 9a/9b) | Print success summary listing each reviewer's verdict; call `PushNotification`; **do not call ScheduleWakeup** | Loop terminates |
| Abort: refusing to proceed (red CI, dev/master target, local verify failed) | Print abort reason; call `PushNotification` with error tone; **do not call ScheduleWakeup** | Loop terminates |
| Pause: ambiguous (architectural disagreement, 50+ threads) | Print pause reason; call `PushNotification`; **do not call ScheduleWakeup** | Loop terminates; user resumes manually |

## State file format

Path: `~/.pr-autopilot/<owner>-<repo>-<pr>.json` (e.g. `~/.pr-autopilot/sufam-exo-vault-123.json`)

```json
{
  "prNumber": 123,
  "repo": "sufam/exo-vault",
  "headRef": "feature/pr-autopilot",
  "fixIterations": 2,
  "pollTicksWithoutReview": 0,
  "ticksWithoutProgress": 0,
  "lastHandledHeadOid": "abc1234",
  "lastSeenReviewId": "PRR_kwDOABC",
  "pushbackReplies": [
    {"threadId": "PRRT_kwDOXYZ", "iteration": 1, "reason": "nit: style preference not in linter rules"}
  ],
  "createdAt": "2026-05-23T10:15:00Z",
  "updatedAt": "2026-05-23T10:18:30Z"
}
```

**Counter semantics:**

- `pollTicksWithoutReview` — incremented when NO per-iteration reviewer has reviewed yet on the PR. Cap: 10 (~15 min) → ABORT "check setup docs for each enabled reviewer (Cursor/Copilot/Codex)."
- `fixIterations` — incremented each time we push a commit. Cap: 5 → ABORT "manual review required."
- `ticksWithoutProgress` — incremented when `lastSeenReviewId` is unchanged from prior iteration AND triage produced zero edits and zero pushbacks. Cap: 6 (~9 min) → PAUSE "loop is spinning without progress; manual intervention needed." Reset to 0 whenever any of: new review appears, edits applied, or pushback posted.

**Why a file, not `git log` grep:**

- Rebase / squash destroys git history but preserves the file
- Branch rename / force-push survives
- Distinguishes our `chore(pr-autopilot)` commits from any human-authored ones with the same prefix
- Allows separate counters for fix-iterations vs poll-ticks-without-review (Composer's P1 #3)
- Allows tracking of pushback replies so we don't accidentally re-engage on a thread we already resolved

State file is read at start of each iteration, written at end. Truncate / delete when PR is closed or merged.

## End-to-end flow

```
User: "implement feature X"
   │
   ▼
Claude works on the task (TDD per CLAUDE.md)
   │
   ▼
User or Claude invokes /ship
   │
   ▼
/ship: tests → VERSION bump → commit → push → gh pr create → PR #123
   │
   ▼
   PHASE 1: User types  /loop /pr-autopilot:step 123
   PHASE 2: Stop hook auto-invokes the same command
   │
   ▼
   Tick 1 (T+0s):
     /pr-autopilot:step 123
     → load state file (none yet — create it)
     → gh pr view 123 → no cursor[bot] review yet
     → pollTicksWithoutReview = 1
     → ScheduleWakeup(90s, ...)  →  loop continues
   Tick 2 (T+90s):
     → Cursor review present: "Score: 2/5", 4 unresolved threads
     → fetch threads, dispatch to shared review-triage pattern with reviewerLogins=["cursor[bot]"] (default config; would include "copilot-pull-request-reviewer[bot]" if copilot.mode==each-iter)
       → 3 actionable: edits applied
       → 1 disagree: Tier 1 pushback reply posted, thread resolved, recorded in state file
     → run preCommitProfiles for repo (named profile if matched, else lockfile-detected default)
     → git commit -m "chore(pr-autopilot): iteration 1 (3 fixes, 1 pushback)"
     → git push origin feature/pr-autopilot
     → fixIterations = 1, lastHandledHeadOid updated
     → ScheduleWakeup(90s, ...)  →  loop continues
   Tick 3 (T+180s):
     → Cursor re-reviewed: "Score: 4/5", 1 unresolved
     → fix → commit → push → fixIterations = 2 → ScheduleWakeup
   Tick 4 (T+270s):
     → Cursor re-reviewed: "Score: 5/5", 0 unresolved
     → SUCCESS:
       → if config.reviewers.copilot.mode == "final-only": gh pr comment 123 --body "@copilot please review this PR — Cursor scored it 5/5"
       → PushNotification: "PR #123 ready for merge (Cursor 5/5, Copilot sanity check requested)"
       → do NOT call ScheduleWakeup
     → /loop terminates
   │
   ▼
User returns → reads PR → merges manually
```

## Algorithm: single iteration of `/pr-autopilot:step <PR#>`

```
function prAutopilotStep(prNumber):
  # 0. Load state
  state = readStateFile(`~/.pr-autopilot/<owner>-<repo>-${prNumber}.json`) or createNew(prNumber)

  # 1. Fetch PR state
  pr = gh pr view ${prNumber} --json headRefName,baseRefName,headRefOid,number,state,reviews,statusCheckRollup

  # 2. PR lifecycle guard
  if pr.state in {CLOSED, MERGED}:
    deleteStateFile()
    return SUCCESS_STOP("PR ${pr.state}; loop done")

  # 3. Branch protection guard
  if pr.headRefName in {dev, master, main}:
    return ABORT("refusing to operate on direct dev/master/main PR")

  # 4. Fix-iteration cap (from state file, NOT git log)
  if state.fixIterations >= 5:
    return ABORT("5 fix-iteration cap reached; manual review required")

  # 5. CI health check (Composer P1 #6)
  required_checks = pr.statusCheckRollup | filter where isRequired
  any_failed = required_checks | any where conclusion == "FAILURE"
  any_pending = required_checks | any where state in {QUEUED, IN_PROGRESS, PENDING}

  if any_failed AND pr.headRefOid == state.lastHandledHeadOid:
    # `lastHandledHeadOid` was set to HEAD in step 11 of the PREVIOUS iteration
    # right after we pushed. If current headRefOid still matches, this means
    # no human or other agent pushed in the meantime — the failed CI is from OUR push.
    # Don't compound a known-bad state.
    return ABORT("CI failed on our last push; investigate before continuing")

  if any_pending:
    # CONTINUE — wait for CI to settle before next iteration
    saveState()
    ScheduleWakeup(90s, ...)
    return  # waiting for CI

  # 5.5 Trigger non-auto reviewers for this iteration (v5 multi-reviewer)
  # Cursor auto-triggers on push. Copilot/Codex need explicit invocation per iter.
  per_iter_reviewers = config.reviewers | filter where enabledForEachIter == true
  for r in per_iter_reviewers:
    if r.requiresTrigger:
      r.trigger(prNumber)  # e.g., gh pr comment "@copilot please review" or `codex review --diff ...`

  # 6. Fetch outcomes from all per-iteration reviewers (v5 multi-reviewer)
  # Each adapter returns {hasReviewed, openThreads, score, raw}
  outcomes = {r.name: r.fetchOutcome(prNumber, state.lastHandledHeadOid) for r in per_iter_reviewers}

  # Aggregate unresolved threads from all reviewers that post threads (cursor, copilot)
  # for downstream triage. Codex/claudeSelf don't post threads; their outcomes feed STOP logic only.
  threads_raw = gh api graphql -f query='
    query($n:Int!, $r:String!, $o:String!) {
      repository(owner:$o, name:$r) {
        pullRequest(number:$n) {
          reviewThreads(first:50) {
            totalCount
            nodes {
              id isResolved
              comments(first:5) {
                nodes { databaseId body path line author { login } }
              }
            }
          }
        }
      }
    }' \
    -F n=${prNumber} -F r=${repo} -F o=${owner}

  total = threads_raw | jq '.data.repository.pullRequest.reviewThreads.totalCount'
  if total >= 50:
    return PAUSE("≥50 review threads; likely truncation, pagination required (defer to v2)")

  # Build list of GitHub-side reviewer logins to include (cursor, copilot — codex/claudeSelf don't post threads)
  github_reviewer_logins = [r.login for r in per_iter_reviewers if r.postsThreads]

  threads = threads_raw | jq '
    .data.repository.pullRequest.reviewThreads.nodes
    | map(select(
        .isResolved == false
        and (.comments.nodes[0].author.login as $a | $logins | index($a))
      ))' --argjson logins "${github_reviewer_logins}"

  # 7. Per-reviewer success check (v5 — each reviewer's adapter decides isSuccess)
  # Already in `outcomes` dict from step 6. Just reference outcomes[r.name] below.

  # 8. Poll-tick counter (Composer P1 #3, generalized to multi-reviewer v5)
  # "No review yet" means: NO per-iter reviewer has reviewed at all
  any_reviewer_has_reviewed = any(outcomes[r.name].hasReviewed for r in per_iter_reviewers)
  if NOT any_reviewer_has_reviewed:
    state.pollTicksWithoutReview++
    if state.pollTicksWithoutReview >= 10:
      return ABORT("10 poll-tick cap (15 min) reached without any per-iter reviewer reviewing; check setup docs for each enabled reviewer")
    saveState()
    ScheduleWakeup(90s, ...)
    return  # waiting for first review
  else:
    state.pollTicksWithoutReview = 0

  # 9. Success path (v5 multi-reviewer: ALL per-iter reviewers must report success)
  pushback_thread_ids = state.pushbackReplies | jq 'map(.threadId)'
  unresolved_not_ours = threads | filter where (.id NOT IN pushback_thread_ids)

  all_per_iter_happy = all(r.adapter.isSuccess(outcomes[r.name]) for r in per_iter_reviewers)

  if all_per_iter_happy AND unresolved_not_ours.length == 0:
    # 9a. Run final-pass reviewers (claudeSelf, copilot-final, codex-final) before truly stopping
    final_pass_reviewers = config.reviewers | filter where enabledForFinal == true
    for r in final_pass_reviewers:
      r.trigger(prNumber)
      final_outcome = r.fetchOutcome(prNumber, state.lastHandledHeadOid)
      if NOT r.adapter.isSuccess(final_outcome):
        PushNotification(title="PR #${prNumber} needs final-pass attention",
                         message="${r.description}: ${final_outcome.summary}")
        return PAUSE("final-pass reviewer ${r.description} disagreed with per-iter consensus")

    # 9b. All clear
    PushNotification(title="PR #${prNumber} ready",
                     message="All reviewers green: ${enabled_reviewer_summary}")
    deleteStateFile()
    return SUCCESS_STOP("ready for merge")

  # Some per-iter reviewer is not happy yet — fall through to triage + fix
  # (e.g., Cursor scored 5 but Copilot has 2 open threads; or Cursor scored 4)
  pass  # fall through to step 10

  # 10. Triage via shared review-triage pattern (v5: dispatches across reviewer logins)
  triage_result = invokeReviewTriage(
    threads = unresolved_not_ours,
    reviewerLogins = github_reviewer_logins,  # list, dispatched per-thread by .comments.nodes[0].author.login
    pushbackRubric = read("PUSHBACK.md"),
    mode = "unattended"  # no AskUserQuestion per comment
  )

  for outcome in triage_result:
    if outcome.action == "ASK_USER":
      return PAUSE("ambiguous review thread on ${outcome.path}:${outcome.line}; user input needed")

  # 11. Local verification (Composer code-quality: full pre-commit per CLAUDE.md)
  if triage_result.editsApplied > 0:
    cmds = detectPreCommitSuite()
    # exo-vault: ["pnpm run build", "cd mcp-server && pnpm run build" if mcp-server touched,
    #             "pnpm run lint", "pnpm test", "pnpm exec tsc --noEmit"]
    # other repos: read CLAUDE.md if present, else fall back to ["<pm> typecheck", "<pm> lint", "<pm> test"]
    # <pm> auto-detected from lockfile: pnpm-lock.yaml → pnpm, package-lock.json → npm, yarn.lock → yarn
    for cmd in cmds:
      run cmd
      if exit != 0:
        return ABORT("pre-commit check failed: ${cmd} — not pushing broken code")

    git add -A
    git commit -m "chore(pr-autopilot): iteration ${state.fixIterations + 1} (${triage_result.editsApplied} fixes, ${triage_result.pushbacks} pushbacks)"
    git push origin ${pr.headRefName}

    state.fixIterations++
    state.lastHandledHeadOid = (git rev-parse HEAD)
    state.ticksWithoutProgress = 0
    appendPushbackReplies(state, triage_result)
    # Note: lastSeenReviewId is updated unconditionally below in step 11.5,
    # not here — pushback-only iterations must also advance it (Composer v2-final #3)
    saveState()

  # 11.5 No-progress stall guard (Composer v2 #1, refined v2-final)
  current_review_id = pr.reviews | jq 'last.id // null'
  did_anything = (triage_result.editsApplied > 0) OR (triage_result.pushbacks > 0)

  # Stall counter compares CURRENT review against the one we saw last iteration.
  # Compute before updating lastSeenReviewId so first-tick-after-review doesn't
  # falsely count as "unchanged" (edge case Composer flagged).
  review_unchanged = (current_review_id != null AND current_review_id == state.lastSeenReviewId)

  if NOT did_anything AND review_unchanged:
    state.ticksWithoutProgress++
    if state.ticksWithoutProgress >= 6:
      saveState()
      return PAUSE("loop spinning ≥6 ticks (~9 min) with no new review and no actions taken; manual intervention needed")
  else:
    state.ticksWithoutProgress = 0

  # Update lastSeenReviewId AFTER stall check, so the next iteration knows
  # what "unchanged" means relative to this tick. Applies to all paths:
  # edits, pushbacks, or pure-poll ticks where a review existed.
  if current_review_id != null:
    state.lastSeenReviewId = current_review_id

  saveState()

  # 12. Continue: wait for next reviewer round
  ScheduleWakeup(delaySeconds=90, prompt="/loop /pr-autopilot:step ${prNumber}",
                  reason="waiting for reviewer re-review after push")
  return  # loop continues
```

## Stop conditions (all enforced in algorithm)

| Condition | Step | Outcome |
|---|---|---|
| Config: no per-iter reviewer enabled | pre-flight | ABORT |
| PR closed or merged | 2 | SUCCESS_STOP |
| PR targets dev/master/main directly | 3 | ABORT |
| 5 fix-iteration cap | 4 | ABORT |
| CI failed on our last push | 5 | ABORT |
| 10 poll-ticks without any per-iter reviewer reviewing | 8 | ABORT |
| All per-iter reviewers report success AND all final-pass reviewers agree | 9b | SUCCESS_STOP |
| All per-iter reviewers report success BUT a final-pass reviewer disagrees | 9a | PAUSE |
| ≥50 review threads (likely truncation) | 6 | PAUSE |
| Triage flagged ASK_USER | 10 | PAUSE |
| Local pre-commit suite failed | 11 | ABORT |
| 6 ticks with same review and zero actions (stall) | 11.5 | PAUSE |

CI **pending** is explicitly CONTINUE, not ABORT (Composer P1 #6).

## Reuse strategy: wrap, don't duplicate

Composer's P2 #7 is stronger than they realized. `c:/Users/sufam/.claude/skills/gstack/review/greptile-triage.md` has:

- **Parallel API fetch** (line-level + top-level comments) with graceful skip on auth/404
- **Per-project suppressions** with structured history file (gstack stores at `~/.gstack/projects/<slug>/greptile-history.md`; our copy writes to `~/.pr-autopilot/history/<slug>.md` to keep the plugin self-contained — no hidden gstack dependency)
- **4-tier classification** (VALID, ALREADY-FIXED, FALSE-POSITIVE, SUPPRESSED)
- **Reply API correctness** (different endpoints for line-level vs top-level)
- **Tier 1 / Tier 2 reply templates** with concrete-evidence requirements
- **Escalation detection** (Tier 2 only fires after prior GStack reply on same thread)
- **Severity re-ranking** suggestions for misclassified categories
- **Per-project + global history writes** for retro analysis

**`/pr-autopilot` should not duplicate any of this.** Strategy (decided: copy approach for Phase 1):

1. **Copy `gstack/review/greptile-triage.md` to `~/.claude/plugins/marketplaces/claude-pr-autopilot/plugins/pr-autopilot/REVIEW-TRIAGE-COPY.md`** with three parameterizations:
   - Reviewer login becomes a **list** of variables (e.g. `["cursor[bot]"]` for default config, `["cursor[bot]", "copilot-pull-request-reviewer[bot]"]` when copilot.mode=each-iter) instead of hardcoded `greptile-apps[bot]`. Algorithm step 10 passes `reviewerLogins=github_reviewer_logins` (plural); the triage routine dispatches per-thread based on `.comments.nodes[0].author.login` matching any login in the list.
   - Mode flag `unattended: true` — skip any classification path that would `AskUserQuestion` per comment; route to PAUSE instead.
   - History file path: `~/.pr-autopilot/history/<slug>.md` (decoupled from gstack — see Composer v4-final #5).
2. **Reviewer-specific bits stay in per-adapter implementations**: score-line parsing (cursor), `@copilot review` trigger (copilot), `codex review --diff` invocation (codex), rubric grading (claudeSelf). Iteration cap, state file, ScheduleWakeup, push logic stay in `SKILL.md`.
3. **`gstack/review/greptile-triage.md` is not modified.** Gstack keeps its own copy, we keep ours. Two copies will diverge over time — accepted trade-off for not needing to fork or upstream-PR gstack.
4. **Phase 2 follow-up (deferred):** revisit upstreaming a shared `review-triage` core to gstack if the pattern proves stable.

## File layout

```
~/.claude/plugins/marketplaces/claude-pr-autopilot/plugins/pr-autopilot/
├── SKILL.md                    Entry: "/pr-autopilot:step <PR#>" (single iteration, called by /loop dynamic mode)
├── PUSHBACK.md                 Judgment rubric (shared across reviewers)
├── REVIEW-TRIAGE-COPY.md       Multi-login dispatching fetch/classify/reply pattern (copied from gstack greptile-triage)
├── SELF-REVIEW-RUBRIC.md       Default rubric for the `claudeSelf` reviewer
├── reviewers/                  Per-reviewer adapters (v5)
│   ├── CURSOR-SETUP.md
│   ├── COPILOT-SETUP.md
│   ├── CODEX-SETUP.md
│   └── CLAUDE-SELF-SETUP.md
├── SHIP-INTEGRATION.md         PHASE 2 PLACEHOLDER: Stop hook JSON (empty stub in v0.1.0)
└── EVAL.md                     Test scenarios 1-21 + pre-flight step 0 (see Verification)

~/.pr-autopilot/                State files keyed <owner>-<repo>-<pr>.json + history/<slug>.md
```

`/update-config` skill is invoked (Phase 2 only) to wire the Stop hook into `~/.claude/settings.json`.

## Configuration

Defaults in `~/.claude/settings.json` under `prAutopilot`:

```json
{
  "prAutopilot": {
    "pollIntervalSeconds": 90,
    "fixIterationCap": 5,
    "pollTickCap": 10,
    "stallTickCap": 6,
    "reviewers": {
      "cursor":     { "enabled": true,  "login": "cursor[bot]", "scoreRegex": "(?i)score:\\s*([1-5])" },
      "copilot":    { "mode": "final-only", "login": "copilot-pull-request-reviewer[bot]" },
      "codex":      { "mode": "off", "postCommentsToPR": false },
      "claudeSelf": { "enabled": false, "rubricFile": "SELF-REVIEW-RUBRIC.md" }
    },
    "preCommitProfiles": {
      "exo-vault": [
        {"cmd": "pnpm run build"},
        {"cmd": "cd mcp-server && pnpm run build",
         "if": "git diff --name-only HEAD~1 HEAD | grep -q '^mcp-server/'"},
        {"cmd": "pnpm run lint"},
        {"cmd": "pnpm test"},
        {"cmd": "pnpm exec tsc --noEmit"}
      ],
      "default-pnpm": [{"cmd": "pnpm run typecheck"}, {"cmd": "pnpm run lint"}, {"cmd": "pnpm test"}],
      "default-npm":  [{"cmd": "npm run typecheck"},  {"cmd": "npm run lint"},  {"cmd": "npm test"}],
      "default-yarn": [{"cmd": "yarn typecheck"},     {"cmd": "yarn lint"},     {"cmd": "yarn test"}]
    }
  }
}
```

### Config → algorithm derivation (Composer v6 blocker #3)

The user-facing config schema uses `enabled` / `mode` per reviewer. The algorithm references derived booleans (`enabledForEachIter`, `enabledForFinal`, `requiresTrigger`, `postsThreads`). The derivation is fixed per-reviewer:

| Config field | `enabledForEachIter` | `enabledForFinal` | `requiresTrigger` | `postsThreads` | Score signal |
|---|---|---|---|---|---|
| `cursor.enabled=true` | ✅ | ❌ | ❌ (auto on push) | ✅ (review threads) | `Score: N/5` regex |
| `cursor.enabled=false` | ❌ | ❌ | — | — | — |
| `copilot.mode=each-iter` | ✅ | ❌ | ✅ (`gh pr comment "@copilot review"`) | ✅ | "0 unresolved threads" |
| `copilot.mode=final-only` | ❌ | ✅ | ✅ (same trigger, one-shot at end) | ✅ | "0 unresolved threads" |
| `copilot.mode=off` | ❌ | ❌ | — | — | — |
| `codex.mode=each-iter` | ✅ | ❌ | ✅ (`codex review --diff …`) | ❌ (internal, optional PR comment if `postCommentsToPR=true`) | pass/fail gate |
| `codex.mode=final-only` | ❌ | ✅ | ✅ (same CLI, one-shot at end) | ❌ | pass/fail gate |
| `codex.mode=off` | ❌ | ❌ | — | — | — |
| `claudeSelf.enabled=true` | ❌ (always final-only — Claude grading Claude converges instantly, can't drive loop) | ✅ | ❌ (internal) | ❌ | 1-5 vs `SELF-REVIEW-RUBRIC.md` |
| `claudeSelf.enabled=false` | ❌ | ❌ | — | — | — |

**Algorithm uses these derived booleans throughout:**
- Step 5.5 iterates over `per_iter_reviewers = filter where enabledForEachIter`; calls `r.trigger()` if `requiresTrigger`
- Step 6 builds `github_reviewer_logins = [r.login for r in per_iter_reviewers if r.postsThreads]` for GraphQL thread fetch
- Step 9 success rule: `all(r.isSuccess(outcomes[r.name]) for r in per_iter_reviewers)`
- Step 9a runs `final_pass_reviewers = filter where enabledForFinal`

**Implementers MUST use this derivation, not invent their own.** Adding a new reviewer means adding a row to this table (and a per-adapter implementation), not changing the algorithm.

### Pre-commit profile selection (v1, hardcoded — Composer v2 #4)

1. If the repo basename (from `gh repo view --json name --jq '.name'`, **not** owner-prefixed `nameWithOwner`) matches a named profile key (e.g. `exo-vault`), use it.
2. Otherwise, detect package manager from lockfile (`pnpm-lock.yaml` → `default-pnpm`, `package-lock.json` → `default-npm`, `yarn.lock` → `default-yarn`).
3. If no lockfile, skip local verification with a warning (don't ABORT — let CI catch it).

**Conditional steps:** Each entry is `{cmd, if?}`. If `if` is present, run it as a shell test; only execute `cmd` if exit code is 0. The exo-vault profile uses this for the conditional mcp-server build (only runs when the most recent commit touched `mcp-server/`). If `if` is absent, always run.

**Phase 2 enhancement (deferred):** parse target repo's `CLAUDE.md` for a "Pre-Commit Verification" section and use those commands. Not in v1 because CLAUDE.md prose formatting varies and parsing is brittle.

Per-repo overrides via `.pr-autopilot.json` in repo root: Phase 2, not v1.

## Safety alignment with project conventions

Mapped to `c:\Users\sufam\.claude\CLAUDE.md` (global) and `c:\Users\sufam\IdeaProjects\agent test\exo-vault\CLAUDE.md` (project):

| Rule | Enforcement |
|---|---|
| "Never commit/push unless explicitly asked" | Phase 1: user types `/loop /pr-autopilot:step <PR#>` — that IS the explicit ask. Phase 2: `/ship` is the explicit ask; Stop hook is its known downstream behavior, documented and disable-able via `PR_AUTOPILOT_DISABLE=1`. |
| "Always verify current branch before changes" | Algorithm step 1 reads `headRefName`; step 3 aborts on dev/master/main |
| "Feature → dev → master, never direct to master" | Step 3 ABORT |
| "Pre-commit verification mandatory: build, mcp-build (if touched), lint, test, tsc --noEmit" | Step 11 runs the named `exo-vault` profile from `preCommitProfiles` — exactly the 5 commands above. Not just typecheck+lint. |
| "Confirm before risky actions" | Each iteration that intends to push prints the plan (comment list, per-thread judgment, files to edit) before applying; user can Esc/Ctrl-C between ticks |
| "Don't disturb other branches via stash+checkout" | Skill never checks out, stashes, or touches branches other than the PR's head branch |
| "Use pnpm, not npm/yarn/npx in monorepo" | `exo-vault` profile uses `pnpm`; for other repos, lockfile auto-detection picks the right manager |

## Verification (EVAL.md scenarios)

### Step 0 — Reviewer login discovery (MUST RUN FIRST, before any scenario)

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

### Scenarios

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

**Phase 1 gating scenarios (must pass on a real exo-vault PR before Phase 2):** 1, 4, 8, 11, **17** (multi-reviewer abstraction proof). Plus EVAL step 0 (login discovery) before any scenario.

**Spec'd-but-not-gated for v0.1.0:** scenarios 18, 19, 20. Documented and runnable; failure doesn't block v0.1.0 release.

Coverage analysis (v5/v6): 21 test cases (1-19 + 20a + 20b) across 20 numbered scenarios + 1 pre-flight step. 5 gating (1, 4, 8, 11, 17). Multi-reviewer combinations not enumerated exhaustively — gating one alt config (#17) proves the adapter abstraction; remaining combos validated empirically as users adopt them.

## Open questions / future work (out of scope for v1)

- **v0.2+ Cursor-native runtime adapter (Path C)**: spec v0.1.0 targets Claude Code as runtime (uses `/loop` dynamic mode + `ScheduleWakeup` + plugin install path under `~/.claude/plugins/marketplaces/claude-pr-autopilot/plugins/pr-autopilot/`). The user's daily-driver IDE is Cursor. Port the loop layer to Cursor's primitives (`AGENT_LOOP_TICK_*` sentinels, `.cursor/hooks.json`, Background Agent triggers) as v0.2 so the skill runs natively where the user works. Algorithm doesn't change — only the loop driver and config locations. Until then: user opens Claude Code specifically to invoke `/pr-autopilot`.
- **Upstream review-triage core to gstack**: copy-and-modify in Phase 1, evaluate upstreaming after stability
- **Cloud-routine variant**: lift `/pr-autopilot:step` into a `/schedule` routine so it survives laptop sleep
- **Multi-PR mode**: `/pr-autopilot` with no arg iterates over all open PRs
- **Per-repo `loop-rules.md`**: autoresearch-pattern config for repo-specific priorities
- **Webhook PUSH model**: replace polling with smee.io tunnel + local listener
- **GraphQL pagination beyond 50 threads**: currently PAUSE; could paginate
- **Other reviewers as primary**: Greptile, CodeRabbit, dedicated Copilot-as-primary. Reviewer identity already in config; score-line parser is the main work
- **Bidirectional pushback record**: feed our pushback history back to Cursor's prompt so it learns

## Cost analysis (rough)

| Item | Per-PR cost | Notes |
|---|---|---|
| Cursor review (auto on push) | ~$0 incremental | Cursor sub absorbs |
| Claude `/pr-autopilot:step` iterations | ~3-5 turns × $0.05-0.15 = $0.15-0.75 | Claude Code sub absorbs |
| Cursor re-reviews per iteration | ~$0 incremental | Cursor sub absorbs |
| Final Copilot review | ~$0 incremental | Copilot seat absorbs (final-only mode: 1 request/PR) |
| **(Alt config) Copilot each-iter mode** | ~5 premium requests/PR | Copilot Pro+ ~1500 premium-req/mo quota → ~300 each-iter PRs/mo before cap; tighter on Business. Stay on final-only unless you have a reason. |
| `gh` + `jq` calls | $0 | Free |
| **Total per PR** | **~$0.15-0.75 of Claude Code sub usage** | All other costs subscription-included |

Compared to alternatives:
- All-Anthropic-API path: ~$0.30-1.50/PR
- Cursor Cloud Agent end-to-end: ~$0.50-2.00/PR (API-priced)
- All-Copilot: ~$0/PR within seat quota

## Revisions from v1 (Composer 2.5 first review)

| Composer item | Disposition | Section changed |
|---|---|---|
| P0 #1 `/loop` STOP contract | Accepted; cleaner mechanism using ScheduleWakeup omission | Loop integration contract (new) |
| P0 #2 Platform target ambiguous | Pushed back; spec is Claude Code-only by design | Runtime & target platform (new) |
| P1 #3 Two "5" counters | Accepted; separate counter in state file | State file format, Algorithm step 8 |
| P1 #4 git log iteration counting | Accepted; state file replaces git log grep | State file format, Algorithm step 4 |
| P1 #5 Success gate precedence | Accepted; explicit if/elif precedence | Algorithm step 9 |
| P1 #6 CI pending behavior | Accepted; CONTINUE on pending, ABORT only on failure | Algorithm step 5 |
| P2 #7 Reuse gstack greptile-triage | Accepted; wrap don't duplicate | Reuse strategy (new) |
| Code: Windows portability | Accepted; jq throughout, no grep -oP | Algorithm steps 6, 7, 8 |
| Code: localVerify mismatch | Accepted; full pre-commit suite (later superseded by hardcoded `preCommitProfiles` table per v2-second-review #4) | Algorithm step 11, Configuration |
| Code: PushNotification undefined | Pushed back; real Claude Code tool | Loop integration contract, Algorithm step 9 |
| Code: Copilot trigger string | Accepted; unified | Algorithm step 9, End-to-end flow |
| Code: GraphQL 50-thread cap | Accepted; PAUSE on ≥50 | Algorithm step 6 |
| Tests: 8/16 EVAL coverage | Accepted; added scenarios 11-15 | Verification |
| Process: Phase 1/2 split | Accepted | Phase 1 / Phase 2 plan (new), File layout |
| `update-config` couldn't be found | Pushed back; real skill, only used in Phase 2 | File layout |

## Revisions from v2 (Composer 2.5 second review)

| Composer v2 item | Disposition | Section changed |
|---|---|---|
| #1 No-progress stall (infinite poll) | Accepted; new `ticksWithoutProgress` counter + cap 6 + EVAL 16 | State file format, Algorithm step 11.5 (new), Stop conditions, Verification |
| #2 `pushbackReplies` filter expression underspecified | Accepted; clarified to `state.pushbackReplies | map(.threadId)`; added belt-and-suspenders note re: `isResolved` | Algorithm step 9 |
| #3 Reviewer login: exact match brittle | Accepted; added explicit EVAL step 0 with `gh pr view --jq` discovery command. Multi-login case: pick the one posting score line, commit exact value to config (no `startswith` in algorithm — Composer v4-final #7) | Verification (EVAL step 0, new) |
| #4 `preCommitSource: claude-md` parsing fragile | Accepted; replaced with hardcoded `preCommitProfiles` table (named `exo-vault` profile + lockfile-detected defaults); CLAUDE.md parsing moved to Phase 2 | Configuration |
| #5 Rename inconsistency (REVIEW-TRIAGE-COPY.md vs SHARED.md) | Accepted; unified on `REVIEW-TRIAGE-COPY.md` throughout | Reuse strategy |
| #6 Step 9 fallthrough docs (score=5 with open threads) | Accepted via #1 — `ticksWithoutProgress` now bounds the spin if triage produces nothing actionable | Algorithm step 11.5 |
| #7 `update-config` Phase 2 hook JSON inline | Accepted as Phase 2 deliverable requirement | (no v2 spec change; documented as Phase 2 acceptance criterion in this revisions table) |
| #8 `statusCheckRollup` schema verification | Accepted; verification side-task added to EVAL scenario 4 | Verification scenario 4 |

## Revisions from v3 (Composer 2.5 final review — CLEARED)

| Composer final-review nit | Disposition | Section changed |
|---|---|---|
| #1 File layout says "scenarios 1-15" | Accepted; updated to "1-16 + pre-flight step 0" | File layout |
| #2 Summary says "six safety stops" but table has ten | Accepted; updated to "ten safety stops" with parenthetical breakdown | Summary |
| #3 `lastSeenReviewId` not updated on pushback-only iterations | Accepted; moved update to end of step 11.5 so it runs unconditionally when a review exists, regardless of edit/pushback outcome | Algorithm steps 11 and 11.5 |
| #4 `if-touched mcp-server/` needs executable definition | Accepted; pre-commit profile entries changed from strings to `{cmd, if?}` objects with executable `if` shell test | Configuration |
| #5 `/loop` 7-day expiry callout | Accepted; added explicit footnote in Loop integration contract referencing the scheduled-tasks docs ceiling | Loop integration contract |
| #6 v1 revisions table mentions stale CLAUDE.md parsing | Accepted; annotated as superseded by v2-second-review #4 | Revisions from v1 |
| Algorithm edge case: first-tick-after-review false-positive stall | Accepted; stall check now uses `review_unchanged` computed *before* `lastSeenReviewId` is updated, plus null-guard on `current_review_id` | Algorithm step 11.5 |

## Revisions from v4 (rename + standalone-repo packaging, 2026-05-23)

| Change | Disposition | Section changed |
|---|---|---|
| Rename `/grep-loop` → `/pr-autopilot` | User decision (outcome-first marketing) | Title, Summary, Algorithm, References, all references throughout |
| Slash command: `/grep-loop-step` → `/pr-autopilot:step` | Implied by rename | All algorithm and flow sections |
| State file path: `~/.gstack/grep-loop/` → `~/.pr-autopilot/` | Decouple from gstack; cleaner user-home convention | State file format, Algorithm step 0 |
| Commit prefix: `chore(grep-loop):` → `chore(pr-autopilot):` | Match new name | Algorithm step 11, End-to-end flow |
| Env var: `GREP_LOOP_DISABLE` → `PR_AUTOPILOT_DISABLE` | Match new name | Phase 1/2 plan, Safety alignment |
| Config key: `grepLoop` → `prAutopilot` | Match new name | Configuration |
| Per-repo override: `.grep-loop.json` → `.pr-autopilot.json` | Match new name | Configuration |
| Skill path: `~/.claude/skills/grep-loop/` → plugin install path under `~/.claude/plugins/marketplaces/claude-pr-autopilot/plugins/pr-autopilot/` | Standalone repo distribution | File layout |
| New: **Distribution & Packaging section** | User asked to mirror claude-watch-video setup | Distribution & Packaging (new section after Summary) |
| New: plugin.json + marketplace.json templates | Required for marketplace install | Distribution & Packaging |
| New: install command | Marketplace UX | Distribution & Packaging |
| New: versioning policy (0.1.0 start, semver milestones) | User picked 0.1.0 honest pre-release | Distribution & Packaging |
| New: CI smoketest scope (schema validation + markdownlint) | User-confirmed v0.1.0 scope | Distribution & Packaging |
| New: spec migration to `docs/DESIGN.md` in new repo | Single source of truth ships with code | Distribution & Packaging |

## Revisions from v4-final (Composer v4 review — CLEARED with 7 consistency nits)

| Composer v4 nit | Disposition | Section changed |
|---|---|---|
| #1 Stale `~/.claude/skills/` reference in Runtime section | Accepted; updated to plugin install path | Runtime & target platform |
| #2 Algorithm pseudocode still named `grepLoopStep` | Accepted; renamed to `prAutopilotStep` | Algorithm |
| #3 SHIP-INTEGRATION.md missing from Distribution layout | Accepted; added as Phase 2 placeholder in the tree | Distribution & Packaging layout |
| #4 CI matrix mismatch (line says ubuntu/windows, body says ubuntu-only) | Accepted; aligned to "ubuntu-latest only for v0.1.0" in both places | Distribution & Packaging layout + CI section |
| #5 Suppression history path inherited from gstack | Accepted; our copy writes to `~/.pr-autopilot/history/<slug>.md` to keep plugin self-contained | Reuse strategy |
| #6 End-to-end flow says "CLAUDE.md pre-commit suite" | Accepted; updated to "preCommitProfiles for repo" | End-to-end flow |
| #7 EVAL step 0 fallback `startswith("cursor")` vs algorithm exact match | Accepted; Composer's option 1 — step 0 picks one login, writes exact value to config; algorithm stays exact-match throughout | Verification (EVAL step 0) |

## Revisions from v5 (multi-reviewer matrix — user feature add)

| Change | Disposition | Section changed |
|---|---|---|
| Add **multi-reviewer model**: cursor + copilot + codex + claudeSelf | User feature request — full matrix in v0.1.0 (with v0.1.0 gating limited to 2 configs to keep eval scope manageable) | New "Reviewer adapters" section |
| Reviewer adapter contract (5 ops: trigger, fetchOutcome, isSuccess, postPushback, description) | Generalize the old Cursor-only logic into a pluggable interface | New "Reviewer adapters" section |
| `cursor` — primary loop reviewer, GH App, native `Score: N/5` | Carried forward from v4 (default config) | Reviewer adapters |
| `copilot` — primary or final, GH App, no native score (use "0 unresolved" or prompt-for-score), trigger via `@copilot please review` comment | New v5 — was final-only-passive before | Reviewer adapters, Configuration |
| `codex` — primary or final, local CLI `codex review --diff …`, pass/fail gate, optional `postCommentsToPR` to mirror findings on the PR | New v5 — user added in feedback round | Reviewer adapters, Configuration |
| `claudeSelf` — final-pass only, internal, rubric-driven via `SELF-REVIEW-RUBRIC.md` (because self-grading-self converges instantly and can't drive a loop) | New v5 | Reviewer adapters, Configuration |
| **Combined STOP rule**: all per-iter reviewers must report success; then final-pass reviewers run once; PAUSE if any final-pass disagrees | Was single-reviewer `score==5 AND threads==0`; now multi-reviewer aggregate | Algorithm step 9 |
| **Config validation**: ABORT if no per-iter reviewer enabled | New v5 — prevents loop-with-no-driver | Stop conditions table (pre-flight) |
| Configuration: replaced `reviewerLogin` / `copilotFinalPass` / `scoreRegex` with full `reviewers: {cursor, copilot, codex, claudeSelf}` object | v5 schema | Configuration |
| File layout: per-reviewer setup docs under `reviewers/` subdir (`CURSOR-SETUP.md`, `COPILOT-SETUP.md`, `CODEX-SETUP.md`, `CLAUDE-SELF-SETUP.md`); new `SELF-REVIEW-RUBRIC.md` at root | Reviewer abstraction needs per-reviewer setup | Distribution & Packaging layout, File layout |
| EVAL: added scenarios 17 (Copilot-each-iter alt config — Phase 1 GATING), 18 (final-pass disagreement), 19 (config error), 20 (Codex primary, spec'd not gated) | Each reviewer mode needs at least one scenario | Verification |
| Phase 1 EVAL gating expanded from 4 scenarios to 5 (added #17 to prove reviewer-adapter abstraction) | Without #17, multi-reviewer code paths are entirely untested before release | Verification |
| Self-review nit: `preCommitProfiles` matches `gh repo view --json name --jq '.name'` (basename, not nameWithOwner) | Caught in v5 self-review pass | Configuration |
| Self-review nit: clarified `lastHandledHeadOid` semantics in CI guard (set in step 11 of prior iteration, matches if no human pushed in between) | Caught in v5 self-review pass | Algorithm step 5 |

## Revisions from v6 (stack alignment with user's actual subscriptions)

User stack as of 2026-05-23: Claude Max $200/mo ✅, GitHub Copilot ✅, Cursor free (Pro $20/mo recommended add), no Codex subscription. v5 was over-engineered for a stack the user doesn't have.

| Change | Disposition | Section changed |
|---|---|---|
| **Cursor adapter** clarified to support **any underlying model** (Composer 2.5 / GPT-5.5 / Codex / Claude — Cursor config, not ours) | User clarified Codex-in-Cursor is just a model choice for Cursor Background Agent, not a separate sub | Reviewer adapters → `cursor` section |
| **Codex standalone CLI adapter** kept for users with Codex Pro CLI sub, but **off by default** with explicit note that "Codex via Cursor" is the recommended path for most users | User wanted BOTH paths supported: "codex alone or codex in cursor" | Reviewer adapters → `codex` section, Configuration defaults |
| EVAL scenario 20 split into 20a (Codex via Cursor — transparent to skill, no new code path) and 20b (Codex standalone CLI — spec'd not gated) | Reflects the two paths | Verification |
| **Open question added: v0.2+ Cursor-native runtime adapter (Path C)** — v0.1.0 ships in Claude Code; user opens Claude Code specifically for `/pr-autopilot` even though daily driver is Cursor. v0.2 ports loop layer to Cursor primitives (`.cursor/hooks.json`, `AGENT_LOOP_TICK_*`, Background Agent triggers). Algorithm unchanged; only loop driver and config locations swap. | Acknowledges runtime mismatch with user's IDE; defers Cursor port to v0.2 to keep v0.1.0 shippable | Open questions |
| Cost rec: **Cursor Pro ($20/mo)** is the only recommended sub add for v0.1.0; Codex Pro CLI explicitly NOT recommended (rate limits on Plus, marginal benefit over Composer 2.5 on Pro) | User considering subs; honest recommendation given quality vs cost | (recommendation surfaces in `reviewers/CURSOR-SETUP.md`, not the spec body) |
| Default reviewer config remains: cursor primary (Composer 2.5 via Cursor Pro) + copilot final-only + claudeSelf off + codex off | Matches user's actual stack | Configuration |

## Revisions from v6-final (Composer v6 review — CONDITIONAL CLEAR resolved)

Composer's v6 review surfaced 8 internal-consistency blockers + 6 minor nits where v4-era prose hadn't been updated when v5/v6 added the multi-reviewer matrix. All baked in below — no design changes, just consistency cleanup so implementers don't guess.

| Composer v6 blocker / nit | Disposition | Section changed |
|---|---|---|
| **Blocker #1** Non-goals contradicted v5 ("Reviewers other than Cursor as primary" listed as non-goal) | Accepted; rewrote to "Greptile/CodeRabbit not in v0.1.0; Cursor/Copilot/Codex/claudeSelf supported via adapters" | Non-goals |
| **Blocker #2** Phase 1 scope table stale (only listed CURSOR-SETUP.md) | Accepted; expanded to reflect reviewers/ subdir, multi-reviewer config, scenario 17 gate, v0.1.0 stubs | Phase 1/2 plan |
| **Blocker #3** Config JSON didn't map to algorithm-internal derived booleans | **Accepted (highest-impact fix);** added explicit "Config → algorithm derivation" table mapping every config field to `enabledForEachIter` / `enabledForFinal` / `requiresTrigger` / `postsThreads` / score signal | Configuration (new sub-section) |
| **Blocker #4** State file counter doc said `reviewerLogin` (Cursor-only) | Accepted; updated to "no per-iter reviewer has reviewed yet" | State file format |
| **Blocker #5** Loop outcome table success row was Cursor-only ("score=5 + threads cleared") | Accepted; aligned with multi-reviewer step 9/9a/9b | Loop integration contract |
| **Blocker #6** REVIEW-TRIAGE-COPY described single login | Accepted; updated to list-of-logins + dispatch-per-thread by `.comments.nodes[0].author.login` | Reuse strategy |
| **Blocker #7** EVAL scenario 2 message stale | Accepted; matched algorithm step 8 abort text | Verification |
| **Blocker #8** Step 12 ScheduleWakeup reason said "Cursor" | Accepted; generalized to "reviewer" | Algorithm step 12 |
| Nit #1 Actors table missing reviewer-adapters row | Accepted; added "Reviewer adapters (v5)" row | Actors and responsibilities |
| Nit #2 EVAL 17 needs Copilot login discovery | Accepted; EVAL step 0 now covers BOTH default reviewers (Cursor + Copilot) | Verification step 0 |
| Nit #3 Combined STOP pseudocode missing `unresolved_not_ours.length == 0` | Accepted; added the precondition | Reviewer adapters → Combined STOP rule |
| Nit #4 Cost table missing Copilot each-iter footnote | Accepted; added row for alt-config scenario 17 cost | Cost analysis |
| Nit #5 Plugin install path verification | Deferred to first-install verification step in implementation order | (no spec change) |
| Nit #6 Scenario count 20 vs 21 actual test cases (20a/20b) | Accepted; updated coverage analysis to "21 test cases across 20 numbered scenarios + 1 pre-flight step" | Verification |
| Algorithm sanity edge case: per-iter consensus + leftover Copilot threads from mode change | Accepted; added EVAL scenario 21 documenting the case and user remediation | Verification |

## References

- Original inspiration: Mickey's `/grep-loop` pattern (Greptile-driven) — name evolved to `/pr-autopilot` to reflect outcome focus
- Architectural pattern: `karpathy/autoresearch` (single rule file + iterative agent + objective stop metric)
- gstack `/ship` skill: triggers the loop
- **gstack `/review/greptile-triage.md`**: the mature triage logic this skill wraps rather than duplicates
- Claude Code `/loop` dynamic mode + `ScheduleWakeup` tool: provide the iteration runtime
- Claude Code `PushNotification` tool: terminal notification
- Claude Code `/update-config` skill: wires the Phase 2 Stop hook
- Project rules: `c:\Users\sufam\.claude\CLAUDE.md` (global) and `c:\Users\sufam\IdeaProjects\agent test\exo-vault\CLAUDE.md` (project)
- Composer 2.5 engineering review (2026-05-23): drove the v2 revisions tabulated above
