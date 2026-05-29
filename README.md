# claude-pr-autopilot

> **Open a PR, walk away, come back when it's merge-ready.**

[![smoketest](https://github.com/MarcinSufa/claude-pr-autopilot/actions/workflows/smoketest.yml/badge.svg)](https://github.com/MarcinSufa/claude-pr-autopilot/actions/workflows/smoketest.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-purple.svg)](https://docs.claude.com/en/docs/claude-code/plugins)
[![Status: v0.4.0 (pre-1.0)](https://img.shields.io/badge/status-v0.4.0%20pre--1.0-blue.svg)](docs/DESIGN.md)

A Claude Code marketplace plugin that closes the PR review→fix loop. Cursor reviews your PR (or Copilot / Codex / Claude-self — configurable), Claude reads each review and either fixes the issue or pushes back with reasoning, then pushes the fix and waits for the next round. Stops when all enabled reviewers report success — or hits one of ten independent safety guards.

## Install

### Prerequisites (one-time)

Required CLIs on your PATH — the skill's pre-flight ABORTs cleanly if any are missing:

| Tool | Windows | macOS | Linux (apt) |
|---|---|---|---|
| `gh` | `winget install GitHub.cli` | `brew install gh` | `sudo apt install gh` |
| `jq` | `winget install jqlang.jq` | `brew install jq` | `sudo apt install jq` |
| `git` | (usually pre-installed) | (usually pre-installed) | (usually pre-installed) |

After install, restart your shell so the binaries are on PATH. Then run `gh auth login` if you haven't already.

### Install the plugin

```bash
/plugin marketplace add MarcinSufa/claude-pr-autopilot
/plugin install pr-autopilot@claude-pr-autopilot
```

## Usage (Phase 1)

After creating a PR (via `/ship` or `gh pr create`):

```
/loop /pr-autopilot:step <PR_NUMBER>
```

The loop runs unattended until success or a safety guard fires. See [`skills/step/SKILL.md`](skills/step/SKILL.md) for the full algorithm and [`docs/DESIGN.md`](docs/DESIGN.md) for the architecture spec (8 review rounds; CLEARED by Composer 2.5).

### Two rotation modes

- **Mode X** — an external reviewer (Cursor / Copilot Code Review / Codex) reviews;
  Claude applies the fixes. Use when you want human-style review of Claude's work.
- **Mode Y** — Copilot SWE Agent applies the fixes and pushes commits; Claude reviews
  those commits against PUSHBACK.md and approves or flags behavior changes. Use when
  you have Copilot SWE Agent and want it to do the fixing.

Set `prAutopilot.primaryFixer` to `auto` (default), `claude` (force X), or
`copilotSwe` (force Y).

**No Cursor Pro?** Set `copilotSwe.mode: "review-score"` — the Copilot SWE Agent reviews
**review-only** and emits a `Readiness: X/5` verdict the loop gates on (just like Cursor's
`Score: N/5`), with Claude as the fixer. A Cursor-style 1–5 gate using only your Copilot
seat. See [`reviewers/COPILOT-SETUP.md`](reviewers/COPILOT-SETUP.md).

### Auto-trigger (v0.3, beta)

Enable the plugin, then `/pr-autopilot:allow <owner/repo>` (or no arg for the current repo).
After that, creating a PR there (e.g. via `/ship`) auto-starts autopilot — no manual
`/pr-autopilot:step`. Draft PRs are skipped. Pause anytime with `/pr-autopilot:pause`
(re-enable `/pr-autopilot:resume`).

It's a **best-effort in-session nudge** (Claude Code hooks can't force actions), and **beta
until the live exo-vault dogfood (EVAL scenario 28) confirms the full auto-chain**. If the
nudge is ever missed, the manual `/pr-autopilot:step <PR#>` path still works.

### Auto-merge (v0.4, beta)

`/pr-autopilot:automerge <owner/repo>` (or no arg for the current repo) opts a repo into **safe
auto-merge**: when the loop reaches SUCCESS on a PR targeting `dev`, autopilot queues a squash
merge instead of just notifying. It is **dev-only, CI-gated, and never merges to
`master`/`main`/`production`** (production promotion stays manual via `/land-and-deploy`).
Default (repo not opted in) = OFF, behavior identical to v0.3.

- **Separate allowlist.** Auto-merge uses `~/.pr-autopilot/automerge-repos`, distinct from v0.3's
  `allowed-repos`. **Full hands-off needs BOTH:** `/pr-autopilot:allow <repo>` (auto-start the loop)
  AND `/pr-autopilot:automerge <repo>` (auto-merge at the end).
- **Queued ≠ merged.** `gh pr merge --auto` *queues*; GitHub completes the merge asynchronously once
  required checks and branch protection clear. Autopilot reports "queued", keeps polling, and notifies
  again on the actual merge. If a repo doesn't have GitHub auto-merge enabled, it falls back to a direct
  squash (safe — CI + reviewers are already green).
- **Laptop must stay awake.** Like the v0.3 loop, merge-wait ticks use `ScheduleWakeup`, so the machine
  must stay on until the queued merge completes.
- **Shared kill switch.** `/pr-autopilot:pause` suppresses auto-merge too; `/pr-autopilot:resume` restores.

**Beta until the live exo-vault dogfood** (queue → merge → cleanup on a real dev-targeted PR) flips it to GA.

## Code knowledge graph awareness (v0.5.3+)

If your repo has a graphify-built knowledge graph at `graphify-out/graph.json`, pr-autopilot's dispatched `/review-spec` subagents (claude-code-reviewer + claude-self-review) AND the in-loop `/step` triage will prefer querying the graph (`graphify explain "<symbol>"`) over grep'ing source files for symbol-lookup questions. Estimated token reduction is significant but **not yet measured** — see EVAL scenarios 52* for the validation plan.

**Mode Y limitation:** Copilot SWE Agent's prompt is GitHub-controlled — v0.5.3 does NOT augment SWE Agent's context. **Workaround:** add a graphify hint to your repo's `AGENTS.md` or `CLAUDE.md` — Copilot coding agent reads these as custom instructions ([documented since 2025-08-28](https://github.blog/changelog/2025-08-28-copilot-coding-agent-now-supports-agents-md-custom-instructions/)).

**Config (`~/.claude/settings.json` → `prAutopilot.graphify`):**

```json
"graphify": {
  "advisory": "auto",   // "auto" (default) | "always" | "off"
  "promptHint": true    // disable to keep detection but skip instruction injection
}
```

- `advisory=auto` — check for `graphify-out/graph.json`. Present → silent pass + hint injection. Absent → one-time INFO per repo. Continue normally.
- `advisory=always` — PAUSE if graph missing. Use when graphify is mandatory for your team.
- `advisory=off` — skip the check entirely.

**Sharing the graph across teammates:** `graphify-out/graph.json` is portable (relative paths only) but per-machine by default. Three approaches, ordered by simplicity:

1. **Commit to repo + git merge driver** — simplest for small teams. `graphify-out/graph.json` is committed; `.gitattributes` registers graphify's `merge-driver` for conflict resolution. **Auto-refresh hook is not prescribed in v0.5.3.** Any hook that mutates the working tree from a post-commit hook (`git add` + `git commit --amend`) risks recursion: `--no-verify` does NOT skip post-commit hooks. For now: refresh manually with `graphify update .` when you want a fresh graph; v0.5.4 will ship a tested hook pattern.
2. **CI artifact + GitHub Release** — works at any team size. GH Action runs `graphify extract . --backend deepseek` on main merges, uploads as a release artifact. Teammates download via `gh release download`. ~3-5h CI setup.
3. **ExoVault or other vault** — long-term architectural option. Net-new vault feature; multi-day build.

v0.5.3 doesn't prescribe an approach — pick what fits your team. Pre-flight `state.graphifyAvailable` detection works regardless of source.

**Worktree timing note:** if you use `/pr-autopilot:assign` to create branch worktrees, the worktree is based on the commit `origin/main` was at when assign ran. If you committed `graphify-out/graph.json` AFTER that commit, the worktree won't see it — pre-flight will report "no graph" even though main has one. Fix: `git -C <worktree-path> pull origin main` to sync.

## Status

**v0.4.0 — safe auto-merge (pre-1.0).** Mode X + Mode Y rotation (v0.2), in-session auto-trigger (v0.3, beta), and opt-in dev-only auto-merge (v0.4, beta) shipped. The eight EVAL gating scenarios (1, 4, 8, 11, 17Y, 22, 23, 24) are not yet verified on a fresh live PR; **v1.0.0** is the stability gate that requires them.

## Setup

One-time setup per reviewer you want to enable. See `reviewers/`:

- [`reviewers/CURSOR-SETUP.md`](reviewers/CURSOR-SETUP.md) — default; requires Cursor Pro $20/mo for Background Agents
- [`reviewers/COPILOT-SETUP.md`](reviewers/COPILOT-SETUP.md) — final-pass by default; uses your existing Copilot seat
- `reviewers/CODEX-SETUP.md` — experimental (Codex Pro CLI sub required); stub in v0.1.0
- `reviewers/CLAUDE-SELF-SETUP.md` — experimental (uses Claude Code sub); stub in v0.1.0

## License

MIT. See [LICENSE](LICENSE).
