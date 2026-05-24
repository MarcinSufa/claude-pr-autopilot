# pr-autopilot v0.3 — Auto-Trigger Design

**Date:** 2026-05-24
**Status:** Approved for implementation (design gate passed; pre-spec review folded in)
**Author:** Marcin Sufa + Claude
**Branch:** `feature/v0.3-auto-trigger`
**Builds on:** v0.2 two-mode rotation (merged, tag `v0.2.0`)

## Why this exists

After v0.2, starting the loop is still manual: the user runs `/loop /pr-autopilot:step <PR#>` (or relies on Claude to). v0.3 makes it **auto-start in-session**: when Claude creates a PR in an allowed repo, a plugin-shipped hook nudges Claude to begin the autopilot loop on that PR — no manual invocation.

## Feasibility constraints (these shaped the design — non-obvious, verified against Claude Code's hook model)

1. **No hook receives tool *output*.** PostToolUse and Stop hooks see the command/`tool_input` and `cwd`, but NOT stdout/result. So a hook **cannot** read the PR number from `gh pr create`'s output. (This invalidates the older DESIGN/SHIP-INTEGRATION assumption of "scan Bash output for the PR URL".)
2. **No hook can force autonomous action.** Hooks only inject `additionalContext` text that Claude *may* act on; they cannot call `ScheduleWakeup`, run a slash command, or start the loop themselves. **Auto-trigger is therefore a reliable nudge, not a hard guarantee.**
3. **The model already has the PR number.** Claude just ran `gh pr create`; the number is in its context. So the hook doesn't need the output — it only needs to fire at the right moment and tell Claude to act. Claude resolves the number itself.
4. **`if` matcher enables precise firing.** A PostToolUse hook with `if: "Bash(gh pr create)"` (Claude Code ≥ v2.1.85) spawns *only* when that command runs — no per-turn overhead.
5. **`ScheduleWakeup` is model-initiated only.** No scheduled hook event exists; the loop's existing ScheduleWakeup-based polling is unchanged.

## Architecture

A **plugin-shipped `PostToolUse` hook**, matcher `"Bash"`, `if: "Bash(gh pr create)"`, runs a gate script. The script checks four gates (is-pr-create, draft, allowlist, paused); if all pass, it emits `additionalContext` nudging Claude to start the in-session autopilot loop on the PR it just created. Claude supplies the PR number (`gh pr view --json number -q .number`). The loop itself (Mode X / Mode Y via existing `derive_mode`) is unchanged.

```
Claude runs `gh pr create …`
  → PostToolUse hook fires (only because if:Bash(gh pr create) matched)
  → gate script reads tool_input.command + cwd from stdin JSON
     GATE 0 (is-pr-create): command matches `gh pr create`  → no → exit 0  (correctness floor for CC < v2.1.85)
     GATE 1 (draft):    command contains `--draft`/`-d`      → exit 0, no nudge
     GATE 2 (allowlist): owner/repo (from git remote at cwd) in ~/.pr-autopilot/allowed-repos? → no → exit 0
     GATE 3 (paused):    ~/.pr-autopilot/paused exists        → exit 0
     all pass → emit additionalContext nudge
  → next turn: Claude resolves PR# and calls
     ScheduleWakeup(delaySeconds=30, prompt="/loop /pr-autopilot:step <N>", reason="autopilot auto-start")
  → existing loop runs (Mode X or Y), with all v0.2 safety stops
```

## Components

1. **`hooks/hooks.json`** (plugin-shipped, loads when plugin enabled):
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "if": "Bash(gh pr create)",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pr-autopilot-trigger.sh", "timeout": 15 }
        ]
      }
    ]
  }
}
```
(If `${CLAUDE_PLUGIN_ROOT}` is not the correct plugin-path variable for hook commands, the implementation plan resolves the actual variable/relative-path convention; the hook command MUST resolve from the installed plugin location, not a hardcoded path.)

2. **`hooks/pr-autopilot-trigger.sh`** — POSIX shell + `jq` (already a required dep). Reads stdin JSON, runs the 4 gates, emits the nudge or exits 0 silently. Never blocks Claude.

3. **`~/.pr-autopilot/allowed-repos`** — newline-delimited `owner/repo` allowlist. Absent or empty ⇒ trigger off everywhere (opt-in).

4. **`~/.pr-autopilot/paused`** — sentinel; present ⇒ suppress all triggers.

5. **Slash commands:**
   - `/pr-autopilot:allow [owner/repo]` — append to allowlist (idempotent). With no arg, adds the current repo (from git remote). Validates existence via `gh repo view <owner/repo>`; refuses if not found.
   - `/pr-autopilot:pause` — `touch ~/.pr-autopilot/paused`.
   - `/pr-autopilot:resume` — `rm -f ~/.pr-autopilot/paused`.

No `/pr-autopilot:install` — the plugin ships the hook; enabling the plugin + one `/allow` is the whole setup.

## The nudge (exact content + extraction + idempotency contract)

When all gates pass, the gate script emits:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "pr-autopilot auto-trigger: you just created a PR in <owner/repo> (an allowed repo). When you finish your current task (e.g. /ship), start the autopilot loop on it: (1) resolve the PR number with `gh pr view --json number -q .number` on the current branch; (2) if ~/.pr-autopilot/<owner>-<repo>-<N>.json already exists, a loop is already running for it — do NOT start a second one; (3) otherwise call ScheduleWakeup(delaySeconds=30, prompt='/loop /pr-autopilot:step <N>', reason='autopilot auto-start'). Do not begin unrelated work to start this loop."
  }
}
```

- **PR# extraction (canonical):** `gh pr view --json number -q .number` on the current branch. Fallback: `gh pr list --head "$(git branch --show-current)" --json number -q '.[0].number'`.
- **Idempotency / concurrent-PR guard:** keyed on the per-PR state file `~/.pr-autopilot/<owner>-<repo>-<pr>.json` (the loop's existing state path). If it exists, the loop is already tracking that PR — the nudge instructs Claude not to double-start. Two different PRs ⇒ two different state files ⇒ allowed independently (re-trigger on the second PR is fine).
- **Timing:** the nudge says "when you finish your current task" because `gh pr create` is typically `/ship`'s last step; this lets `/ship` finish cleanly before the loop starts. ScheduleWakeup is non-blocking regardless.

## Gate semantics (precise)

| Gate | Check | Pass-through (no nudge) when |
|---|---|---|
| **0 — is-pr-create (MANDATORY)** | `tool_input.command` matches `(^\|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]\|$)` | does NOT match → skip. **Required even with `if`** so the hook is correct on Claude Code < v2.1.85 (no `if` support → matcher fires on every Bash call; Gate 0 filters). |
| 1 — draft | `tool_input.command` matches `(^\|[[:space:]])(--draft\|-d)([[:space:]=]\|$)` (covers `--draft`, `--draft=true`, `-d`) | matches → skip (drafts are WIP; reviewers cost quota) |
| 2 — allowlist | `owner/repo` from `git -C "$cwd" remote get-url origin` (parse github URL; **origin only** — non-origin remotes won't match, noted in script comments), **case-insensitive match** against `~/.pr-autopilot/allowed-repos` (both the parsed `owner/repo` and each allowlist line are lowercased before comparing) after **line hygiene**: trim leading/trailing whitespace, skip blank lines, ignore lines without a `/` | not found / no remote / file absent → skip |
| 3 — paused | existence of `~/.pr-autopilot/paused` | exists → skip |

All gates are skip-silent (exit 0, no stdout). Only when ALL gates pass does the script emit the nudge. **Gate 0 runs first** (cheapest, and the correctness floor for older Claude Code).

## Error handling

| Condition | Behavior |
|---|---|
| `cwd` has no git remote / not a github URL | exit 0, no nudge (log line) |
| `jq` missing or stdin unparseable | exit 0, no nudge (log line) — never block Claude |
| any internal script error | `exit 0` always (a hook error must never break the user's Bash flow); append to `~/.pr-autopilot/hook.log` |
| allowlist file missing | treated as empty ⇒ no nudge |
| Claude doesn't act on the nudge | no harm; manual `/pr-autopilot:step <N>` remains the fallback (documented) |

## State file additions (loop state, set when auto-started)

```json
{
  "...existing v0.2 v2 schema...": "...",
  "autoTriggered": true,
  "triggerSource": "posttooluse-hook"
}
```
Informational only (telemetry / debugging which loops were auto- vs manually started). Does not change loop logic. **Set by the loop** (first tick of `skills/step/SKILL.md` when the start was nudge-originated) — NOT by the gate script (the gate script only emits the nudge; it doesn't write loop state). The implementation plan adds a small step to SKILL.md state-init to record this when invoked via the auto-trigger prompt.

## Windows / Git-Bash portability

- Gate script is POSIX `.sh`, invoked via Git Bash. No `npx` in the hot path ⇒ no `cmd /c` wrapper needed.
- Guard against `.bashrc`/`.bash_profile` `echo` statements corrupting stdout JSON (run non-interactively; the script writes ONLY the JSON nudge to stdout and nothing else on the success path).
- Use the plugin-path variable (not a hardcoded `/c/Users/...` path) so it resolves wherever the plugin is installed.
- `git remote get-url` and `gh`/`jq` are already required deps (pre-flight checks them); same toolchain.

## Reconciliation appendix — docs to update

| File | Change |
|---|---|
| `SHIP-INTEGRATION.md` | Replace the "v0.3+ planned (Stop hook)" placeholder with the actual v0.3 mechanism: PostToolUse `if:Bash(gh pr create)`, plugin-shipped, allowlist-gated. Correct the stale "scan Bash output" assumption. **Remove the `PR_AUTOPILOT_DISABLE=1` reference** — v0.3 uses the `~/.pr-autopilot/paused` sentinel + `/pause`//`/resume` instead. |
| `ROADMAP.md` | Mark v0.3 as "in progress / current". **Remove "+ Mode Y final-pass" from the v0.3 bullet** (descoped to its own later spec). Keep v0.4 (auto-merge) + v0.5 (Cursor) + v1.0.0 (stability gate) ordering. |
| `README.md` | Add an "Auto-trigger" section: enable plugin → `/pr-autopilot:allow <repo>` → autopilot starts itself on new PRs; `/pause`+`/resume`; draft PRs skipped. Note it's a **best-effort in-session nudge** and **beta until scenario 28 dogfoods on a live exo-vault PR**. |
| `EVAL.md` | Add scenarios 25–30 (below). **Update existing scenario 14** (`PR_AUTOPILOT_DISABLE=1`) → "touch `~/.pr-autopilot/paused` (or `/pause`) before/around PR creation → hook no-ops" to match the chosen kill switch. |
| `docs/DESIGN.md` | Update the auto-trigger section of the supersession stub to point here. Note any `PR_AUTOPILOT_DISABLE` mention there is superseded by the paused sentinel. |
| `.claude-plugin/plugin.json` | Bump to `0.3.0`; register the new slash commands if the plugin manifest lists commands. |
| `docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md` | One line: the v0.2 version-plan table (which listed `/install` and `PR_AUTOPILOT_DISABLE`) is **historical**; this v0.3 spec is canonical for auto-trigger (plugin-shipped hook + allowlist + `paused` sentinel, no `/install`). |

## Deliverables checklist

- [ ] `hooks/hooks.json` — PostToolUse `if:Bash(gh pr create)` config
- [ ] `hooks/pr-autopilot-trigger.sh` — gate script (4 gates, exit-0-on-error, emits nudge)
- [ ] `skills/allow/SKILL.md` (or command file) — `/pr-autopilot:allow`
- [ ] `skills/pause/SKILL.md` + `skills/resume/SKILL.md` — `/pr-autopilot:pause` / `:resume`
- [ ] Loop state: set `autoTriggered` / `triggerSource` when started via nudge (small SKILL.md addition)
- [ ] Docs: SHIP-INTEGRATION, ROADMAP, README, DESIGN stub
- [ ] `EVAL.md` scenarios 25–29
- [ ] `.claude-plugin/plugin.json` → 0.3.0
- [ ] Plugin-path resolution for the hook command verified on a real `--plugin-dir` install

## EVAL scenarios (new for v0.3)

- **25 — Allowlist reject:** `gh pr create` in a repo NOT in `allowed-repos` → hook exits silently, no nudge, no loop.
- **26 — Draft skip:** `gh pr create --draft` in an allowed repo → hook detects `--draft`, no nudge.
- **27 — Paused:** `~/.pr-autopilot/paused` present, allowed non-draft PR → no nudge.
- **28 — Happy auto-chain:** allowed repo, non-draft, not paused → hook nudges → Claude resolves PR# → ScheduleWakeup starts the loop → loop runs to its normal terminal state. (The live dogfood on exo-vault.)
- **29 — Duplicate-trigger guard:** PR already has a `~/.pr-autopilot/<…>.json` state file → nudge's idempotency clause makes Claude NOT start a second loop.
- **30 — Nudge ignored (graceful no-op):** hook fires + nudges, but Claude completes `/ship` without acting on it → no error, no state-file corruption; user can still manually `/pr-autopilot:step <N>`. Confirms the best-effort nudge fails safe.
- **14 (updated) — Kill switch:** `~/.pr-autopilot/paused` present (via `/pause`) around PR creation in an allowed repo → hook no-ops (Gate 3). Replaces the old `PR_AUTOPILOT_DISABLE=1` env-var scenario.

## Verification matrix (markdown/shell, no runner)

| # | Check | How |
|---|---|---|
| W1 | Gate script: draft → no output | pipe a synthetic stdin JSON with `--draft` command → expect empty stdout, exit 0 |
| W2 | Gate script: non-allowlisted repo → no output | synthetic cwd whose remote isn't in allowlist → empty stdout |
| W3 | Gate script: paused → no output | touch paused, run → empty stdout |
| W4 | Gate script: all gates pass → emits valid JSON nudge | allowed repo + non-draft + not paused → stdout parses as JSON with `additionalContext` |
| W5 | Gate script: malformed stdin → exit 0, logs | feed garbage → exit 0, hook.log line, no stdout |
| W6 | `hooks.json` valid JSON + `if` field present | `jq empty hooks/hooks.json` + grep `if` |
| W7 | Plugin-path command resolves on `--plugin-dir` install | load plugin, run `gh pr create` on an allowed test repo, confirm hook fires |

## Open questions (narrow)

1. **Plugin-path variable for hook `command`:** confirm the exact variable (`${CLAUDE_PLUGIN_ROOT}` or equivalent) Claude Code expands in a plugin-shipped hook command. Resolve in the plan via the Claude Code hooks reference; W7 verifies on a real install.

(The earlier "`if`-field fallback" open question is now **resolved**: Gate 0 — the mandatory `gh pr create` command-substring check — makes the hook correct with or without `if`. With `if` (CC ≥ v2.1.85) the hook rarely spawns; without it the hook spawns on every Bash call but Gate 0 exits immediately for non-PR-create commands. Either way, behavior is identical.)

## Out of scope (deferred)

- Auto-merge (v0.4) — `gh pr merge --auto` to dev only, `neverMergeToBranches` guard.
- Mode Y final-pass reviewers (own later spec).
- Re-trigger reliability fix for Copilot Code Review (own later spec; tracked).
- External / headless orchestration (GitHub Action / cron launching `claude -p`) — the "true unattended, laptop-closed" path; Future. v0.3 is explicitly **in-session** nudge only.

## Release sequencing note

v0.3.0 ships to `main` when implemented + verified (W1–W7). Per the ROADMAP, v1.0.0 (stability stamp) comes *after* v0.3/v0.4, not before — so v0.3 is not gated on v1.0.0. The safe rollout: on first ship, the allowlist contains only `MarcinSufa/exo-vault`; the first real auto-chain (scenario 28) on a live exo-vault PR simultaneously dogfoods v0.3 AND advances the v1.0.0 live-loop evidence.
