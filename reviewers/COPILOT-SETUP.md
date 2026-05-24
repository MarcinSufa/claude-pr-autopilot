# Copilot reviewer setup

The `copilot` reviewer adapter has three modes:

- `final-only` (default) — Copilot reviews once at the end as a sanity check after the primary reviewer signals success
- `each-iter` — Copilot reviews every push, driving the loop alongside (or instead of) Cursor
- `off` — Copilot not involved

## Requirements

- **GitHub Copilot seat** (Pro, Pro+, Business, or Enterprise) — any tier with Code Review enabled
- **Copilot Code Review enabled on the repo** (org admin or repo admin can toggle in repo settings → Code & automation → Copilot)

## One-time setup

### 1. Enable Copilot Code Review on the repo

Go to your repo on GitHub → Settings → Copilot → **Enable Copilot for pull requests** → ON.

That's it. No agent rules needed — Copilot Code Review is built into GitHub.

### 2. Verify the trigger mechanism

Copilot **Code Review** is triggered by the requested-reviewers API, NOT by an
`@copilot` mention:

```bash
gh api repos/{owner}/{repo}/pulls/<PR#>/requested_reviewers -X POST -f 'reviewers[]=Copilot'
```

⚠ The `@copilot please review` mention triggers the **SWE Agent** (a different
product — reviewer + fixer). See `skills/step/SKILL.md` "Copilot has TWO products".

The `pr-autopilot` skill triggers Copilot Code Review via the requested-reviewers API:

- **`final-only` mode**: skill adds Copilot as a reviewer once, after all per-iter reviewers report success
- **`each-iter` mode**: skill re-requests Copilot review after every push

### 3. Verify the bot login

```bash
gh pr view <PR#> --json reviews --jq '.reviews[].author.login' | grep -i copilot
```

Expected: `copilot-pull-request-reviewer[bot]` (as of 2026-05). If different, update `reviewers.copilot.login` in `~/.claude/settings.json`.

## How `final-only` mode works

After all per-iter reviewers (e.g., Cursor) report success and zero unresolved threads remain, the skill:

1. Requests Copilot as a reviewer via the API: `gh api repos/{owner}/{repo}/pulls/<PR#>/requested_reviewers -X POST -f 'reviewers[]=Copilot'`
2. Waits up to 5 minutes (or `pollInterval * 4`) for Copilot to post its review
3. Fetches Copilot's review threads
4. If 0 unresolved threads → SUCCESS_STOP
5. If unresolved threads → PAUSE "final-pass reviewer copilot disagreed"

## How `each-iter` mode works

Each iteration after our push, before the next ScheduleWakeup tick:

1. Requests Copilot as a reviewer via the API: `gh api repos/{owner}/{repo}/pulls/<PR#>/requested_reviewers -X POST -f 'reviewers[]=Copilot'`
2. On the NEXT tick, fetches Copilot's review threads (alongside other per-iter reviewers' threads)
3. All per-iter reviewers must report success for STOP

Note: `copilot` posts review **THREADS** (Code Review). `copilotSwe` (Mode Y) posts top-level **comments + commits** as fixer — a distinct product and flow.

Cost: ~5 Copilot premium requests per PR (one per iter). Copilot Pro+ has ~1500 premium-req/mo quota → ~300 each-iter PRs/mo before cap. Stay on `final-only` unless you have specific reason for each-iter rigor.

## STOP signal

Copilot has no native 1-5 score. The skill uses **"zero unresolved review threads authored by `copilot-pull-request-reviewer[bot]`"** as the success signal. If Copilot leaves open threads, the loop continues; if the threads we resolved come back, the stall guard (step 11.5) catches the ping-pong.

## ⚠ Each-iter mode rate-limit risk

Copilot Pro (cheaper tier, $10/mo) does NOT include Coding Agent and has TIGHTER review quotas than Pro+. If on Copilot Pro:

- Each-iter mode may hit quota mid-loop → reviews stop appearing → skill aborts at poll-tick cap (10 ticks ~= 15 min)
- Stick with `final-only` mode on Pro

## ⚠ Different from Copilot Coding Agent

This adapter (`copilot`) uses Copilot **Code Review** (reviewer only). To use Copilot **SWE Agent** as the FIXER, configure the `copilotSwe` reviewer with `mode: each-iter` and set `primaryFixer: copilotSwe` (or `auto`) — that is **Mode Y**, shipped in v0.2. See `skills/step/SKILL.md` 'Algorithm: Mode Y'.
