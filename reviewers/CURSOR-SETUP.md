# Cursor reviewer setup (one-time, per repo)

The `cursor` reviewer adapter is the default and recommended primary reviewer for `/pr-autopilot`. It uses Cursor's GitHub App to auto-review every push.

## Plan requirements (v0.5.1)

There are **two distinct Cursor integration paths** — both require Cursor Pro for reliable operation, but for different reasons:

| Path | Cursor plan | API key | Used by | Reason for plan req |
|---|---|---|---|---|
| **PR review via Background Agent** (this doc, the v0.1+ flow) | **Pro required for reliable Background Agent PR review** | none | `/pr-autopilot:step` loop in `skills/step/` | Background Agent rate limits + Free tier quotas make PR-review-on-every-push unreliable; see "Requirements" section below |
| **Pre-PR `cursor-cloud-agent` (composer-2.5 spec review)** | **Pro / Business required** | `CURSOR_API_KEY` | `/pr-autopilot:review-spec` in `skills/review-spec/` | Cloud Agent API is locked to Pro (HTTP 403 `plan_required` on Free) |

If you're on Cursor Free:
- The Background Agent PR-review path may work but is rate-limited / unreliable for production PR loops.
- The `cursor-cloud-agent` dispatch in `/pr-autopilot:review-spec` returns HTTP 403 `plan_required`. v0.5.1's `hooks/cursor-cloud-agent-probe.sh` pre-flight catches this and gracefully skips the channel — `/review-spec` continues with the 2 free Claude subagents + the manual Composer 2.5 paste-back prompt. No action needed beyond noting the `ℹ️ Cursor Cloud Agent skipped` message.

To enable the API path: upgrade at https://cursor.com/settings/billing, then set `CURSOR_API_KEY` in `~/.claude/settings.json` `env` block (or via `setx` / your shell profile). Restart Claude Code to propagate. EVAL scenario 50 validates the Free→graceful-skip path; EVAL scenario 43 validates the Pro→full-dispatch path.

## Requirements

- **Cursor Pro plan** ($20/mo) — Background Agents are not available on the free plan
- **Cursor GitHub App installed** on the GitHub org or specific repo(s) you want autopilot to operate on
- **Background Agent enabled** for PR reviews in Cursor settings

## One-time setup steps

### 1. Install the Cursor GitHub App

Go to https://cursor.com/settings/integrations and click **Install GitHub App**. Authorize access to either:

- All repositories in your account/org (simpler), or
- Selected repositories only (recommended — start with one repo, expand)

### 2. Enable Background Agent PR reviews

In Cursor: Settings → Background Agents → toggle "Auto-review pull requests" → ON.

### 3. Add the score-emission rule (CRITICAL)

The `pr-autopilot` skill parses a `Score: N/5` line from Cursor's review body to know when to stop. By default Cursor's reviews don't emit this line — you must instruct the Background Agent to do so.

In Cursor: Settings → Background Agents → Agent Rules → **paste this rule**:

```
When reviewing a pull request, ALWAYS end every review with a final line in this exact format:

Score: N/5

Where N is:
- 1 if the PR has major correctness, security, or design issues
- 2 if multiple non-trivial issues need fixing
- 3 if a few clear improvements would be valuable
- 4 if the PR is close to mergeable with minor nits
- 5 if the PR is ready to merge as-is

Do NOT omit this line. Do NOT change the format. The line must be the LAST line of the review.
```

### 4. Choose the underlying model (optional)

The Cursor Background Agent runs whichever model you select in Cursor's settings. Recommended for code review:

- **Composer 2.5** (default, recommended) — Cursor's own model, strong on code review tasks
- **GPT-5.5** — alternative; similar quality
- **Codex** — same model family as standalone Codex CLI but no separate sub required
- **Claude** — uses your Claude Code sub via Cursor

The `pr-autopilot` skill is model-agnostic. Whichever model you pick, the skill just sees a review from `cursor[bot]` with a `Score: N/5` line.

## Verification

Open a PR in an enrolled repo. Within ~1-5 minutes, Cursor should:

1. Post a review (visible at the top of the PR's "Files changed" tab)
2. Include the `Score: N/5` line at the bottom of the review body
3. Use the login `cursor[bot]` (verify with `gh pr view <PR#> --json reviews --jq '.reviews[].author.login'`)

If any of those don't match: see EVAL Step 0 in [`../EVAL.md`](../EVAL.md) for diagnostic steps. Update `reviewers.cursor.login` and/or `reviewers.cursor.scoreRegex` in `~/.claude/settings.json` to match what Cursor actually produces.

## ⚠ Laptop must stay awake during loops

The `/pr-autopilot` loop runs in your local Claude Code window via `/loop` dynamic mode. If your laptop sleeps, the loop pauses (and may abandon mid-iteration). For long-running PR loops:

- Disable sleep on AC power
- Or run with `caffeinate -d` (macOS) / `Don't Sleep` utility (Windows) / `systemd-inhibit` (Linux)

## ⚠ 7-day expiry

Claude Code dynamic scheduled tasks expire after 7 days (per Claude Code's scheduled-tasks documentation). With 90s polling, that's ~6,720 ticks — far beyond any reasonable PR review cycle. But if a PR sits in pushback purgatory for over a week, manually re-invoke `/loop /pr-autopilot:step <PR#>`.

## Cost

Cursor Pro absorbs all Background Agent runs within plan limits (currently ~500 fast requests/mo, unlimited slow). One PR cycle typically uses 3-5 fast requests. At 10 PRs/week, you're well within budget.
