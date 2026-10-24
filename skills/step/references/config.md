# Reviewer and mode configuration notes

Moved from `skills/step/SKILL.md`. Read this when choosing or explaining reviewer config, or when a pre-flight config-error ABORT needs explaining to the user.

## Copilot products

**⚠ Important: Copilot has TWO products** — `copilot` (Copilot Code Review) and `copilotSwe` (Copilot SWE Agent). They are DIFFERENT:
- **Code Review** posts structured line-level threads. Triggered by adding `Copilot` via the requested-reviewers API (the `@copilot` mention does NOT trigger this). May require specific repo setup (rulesets or manual reviewer add) and a paid Copilot tier with Code Review enabled.
- **SWE Agent** posts conversational top-level comments. Triggered by `@copilot please review` mention. Works out-of-box on most repos with Copilot installed. Applies line-level fixes by pushing commits (verified on exo-vault PR #128 — 7 fixes + a test file). Posts a conversational top-level comment alongside the commits.
Per real-world testing (2026-05-23), SWE Agent fires more reliably on private repos. Code Review may need additional setup most users don't have. Default to `copilotSwe` if Code Review doesn't respond within 10 poll-ticks.

**SWE Agent serves two distinct roles, selected by `copilotSwe.mode`:**
- **`each-iter` — fixer (Mode Y).** The mention asks Copilot to review *and fix*; it pushes commits, Claude reviews them. Copilot drives the change.
- **`review-score` — scoring reviewer (Mode X).** The mention asks Copilot to **review only (no code changes)** and end with `Readiness: X/5`; the loop parses that score with `copilotSwe.scoreRegex` and gates on `== 5`, exactly like `cursor`. **Claude is the fixer.** Use this when you have a Copilot seat but no Cursor Pro and want a Cursor-style 1–5 gate. (`final-only` is a one-shot conversational sanity check, judged by Claude.)

## Mode derivation rules (prose)

`derive_mode()` in SKILL.md §"Mode derivation" is the executable form of these rules.

**`primaryFixer="claude"` + `copilotSwe.mode="each-iter"` rule:** ABORT with message — "primaryFixer=claude conflicts with copilotSwe.mode=each-iter. Either set copilotSwe.mode=off (or final-only) or change primaryFixer to copilotSwe or auto." Same reasoning as `auto` case 3 below: silently ignoring a reviewer config wastes user's paid quota.

**`auto` resolution rules** (first match wins):

1. If `copilotSwe.mode == "each-iter"` AND `cursor.enabled == false` AND `copilot.mode != "each-iter"` AND `codex.mode != "each-iter"` → **Mode Y**
2. Else if any of {`cursor.enabled`, `copilot.mode == "each-iter"`, `codex.mode == "each-iter"`, `copilotSwe.mode == "review-score"`} AND `copilotSwe.mode != "each-iter"` → **Mode X** (`review-score` makes SWE Agent a per-iter *reviewer*; Claude fixes)
3. Else if BOTH a per-iter reviewer AND `copilotSwe.mode == "each-iter"` are enabled → **ABORT** with message: "ambiguous fixer config. Set `primaryFixer` to 'claude' or 'copilotSwe' explicitly to resolve."
4. Else (no per-iter anything) → **ABORT** with message: "no per-iter reviewer or fixer enabled; nothing would drive the loop"

## Per-repo pre-commit profile example

**Per-repo pre-commit profile (optional):** `preCommitProfiles` keys are repo basenames (falls back to `default-<package-manager>` from the lockfile, see step 11). Example for a pnpm monorepo named `my-app`; each entry may carry an `if` shell condition:

```json
"preCommitProfiles": {
  "my-app": [
    {"cmd": "pnpm run build"},
    {"cmd": "cd server && pnpm run build", "if": "git diff --name-only HEAD~1 HEAD | grep -q '^server/'"},
    {"cmd": "pnpm run lint"},
    {"cmd": "pnpm test"}
  ]
}
```

## Pre-flight config errors

The full form of SKILL.md §"Pre-flight: config validation", with the exact message for each case. `derive_mode()` is in SKILL.md §"Mode derivation".

```python
# Detect mode (derive_mode() is in SKILL.md §"Mode derivation")
mode = derive_mode(config)

if mode == ABORT_CONFIG:
  # Two ABORT_CONFIG sub-cases — distinguish by primaryFixer setting:
  if config.primaryFixer == "claude":
    # claude + copilotSwe.mode=each-iter conflict
    push_notification(
      "config error",
      "primaryFixer=claude conflicts with copilotSwe.mode=each-iter. Either set copilotSwe.mode=off (or final-only) or change primaryFixer to copilotSwe or auto."
    )
  else:
    # auto with both swe_each and any_xreviewer set — ambiguous
    push_notification(
      "config error",
      "ambiguous fixer config. Set primaryFixer to 'claude' or 'copilotSwe' explicitly to resolve."
    )
  return  # terminate

if mode == ABORT_NO_DRIVER:
  push_notification("config error", "no per-iter reviewer or fixer enabled; nothing would drive the loop")
  return  # terminate

# reachable when primaryFixer=claude is forced with no per-iter reviewer enabled
if mode == "X":
  if not any(getattr(r, "enabledForEachIter", False)
             for r in [config.reviewers.cursor,
                       config.reviewers.copilot,
                       config.reviewers.codex,
                       config.reviewers.copilotSwe]):  # copilotSwe counts only in review-score mode
    push_notification(
      "config error",
      "Mode X requires at least one per-iter reviewer in {cursor, copilot, codex, copilotSwe(review-score)}"
    )
    return  # terminate

if mode == "Y":
  if config.reviewers.copilotSwe.mode != "each-iter":
    push_notification("config error", "Mode Y requires copilotSwe.mode=each-iter")
    return  # terminate
```
