# Roadmap

Snapshot date: 2026-05-23. Revisit after each release to re-prioritise.

## v0.1.0 (pre-release, current)

Manual `/loop /pr-autopilot:step <PR#>` after `/ship`. Default config: Cursor primary + Copilot final-only.

Phase 1 EVAL gating scenarios (1, 4, 8, 11, 17) **must pass on a real exo-vault PR before bumping to v1.0.0**.

## v1.0.0 (gated by Phase 1 EVAL)

Same scope as v0.1.0 but with all five Phase 1 gating scenarios verified on a real PR. Stable manual API.

## v1.1.0+ — Phase 2: Stop hook auto-chain

Add Stop hook in `~/.claude/settings.json` that detects when `/ship` (or any Claude turn) ends with a `gh pr create` and auto-invokes `/loop /pr-autopilot:step <PR#>`. Per-session disable via `PR_AUTOPILOT_DISABLE=1`.

Requires the manual loop (v1.0.0) to have proven stable on at least 10 real PRs first.

## v0.2 — Cursor-native runtime adapter (Path C from spec)

The user's daily-driver IDE is Cursor, but v0.1.0 ships as a Claude Code plugin (uses `/loop` dynamic mode + `ScheduleWakeup`). Port the loop layer to Cursor's primitives (`AGENT_LOOP_TICK_*` sentinels, `.cursor/hooks.json`, Background Agent triggers) so the skill runs natively where the user works. Algorithm doesn't change — only the loop driver and config locations.

## Future (no version target)

Ranked by leverage:

| # | Item | Effort | Why it matters |
|---|---|---|---|
| A | **Real-PR demo run + asciinema** embedded in README | ~30 min | Single biggest credibility move once gates pass |
| B | **Submit to Anthropic marketplace** (`docs/marketplace-submission.md` + Anthropic form) | ~1 hr | Distribution; gets the first 100 users |
| C | **Multi-PR mode** — `/pr-autopilot` with no arg iterates over all open PRs | ~4 hrs | Useful when returning from a day off with multiple PRs in flight |
| D | **Per-repo `.pr-autopilot.json` override** | ~2 hrs | Repo-specific rubric tuning (e.g., exo-vault's RLS-mandatory rule) |
| E | **Greptile / CodeRabbit adapters** | ~6 hrs each | Other reviewer ecosystems; copy-paste pattern from cursor/copilot adapters |
| F | **Cloud-routine variant via `/schedule`** | ~4 hrs | Survives laptop sleep; requires plan-tier verification |
| G | **Codex CLI adapter EVAL gating (scenario 20b)** | ~2 hrs | If user actually subscribes to Codex Pro CLI |
| H | **Webhook PUSH model** (smee.io tunnel + local listener) | ~6 hrs | Replace polling; worth it only if 90s latency becomes friction |

## Anti-roadmap (explicit "not doing this")

- **Automatic merge after 5/5** — user always eyeballs and clicks merge. Safety > speed.
- **Reviewer-less mode** — pre-flight config validator ABORTs if no per-iter reviewer enabled. Nothing would drive the loop.
- **Claude-self as primary loop reviewer** — Claude grading Claude converges in one step. Final-pass only by design.

See [`docs/DESIGN.md`](docs/DESIGN.md) for full architecture rationale.
