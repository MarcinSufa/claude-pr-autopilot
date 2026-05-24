# pr-autopilot v0.3 Auto-Trigger — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Claude creates a PR in an allowed repo, a plugin-shipped PostToolUse hook nudges Claude to auto-start the in-session autopilot loop on it.

**Architecture:** A `PostToolUse` hook (`if: "Bash(gh pr create)"`) runs a POSIX gate script. The script applies 4 gates (is-pr-create / draft / allowlist / paused) and, if all pass, emits an `additionalContext` nudge. Claude resolves the PR number itself and calls `ScheduleWakeup` to start the existing loop. Hooks cannot read tool output or force actions — this is a best-effort in-session nudge with manual `/pr-autopilot:step` as the fallback.

**Tech Stack:** POSIX shell + `jq` (gate script, real + testable code); `bash` test harness; Claude Code plugin hooks (`hooks/hooks.json`); `gh`/`git`. Windows + Git Bash target.

**Source of truth:** `docs/superpowers/specs/2026-05-24-pr-autopilot-v0.3-auto-trigger-design.md` (committed `44c0f1c`). Working branch: `feature/v0.3-auto-trigger` (checked out; spec already committed there).

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `hooks/pr-autopilot-trigger.sh` | The gate script — the only real logic. 4 gates + nudge emission + exit-0-on-error. Testable via `PR_AUTOPILOT_HOME` override. | 1 |
| `hooks/tests/test-trigger.sh` | Bash test harness — pipes synthetic hook JSON, asserts stdout. Covers W1–W5. | 1 |
| `hooks/hooks.json` | Wires PostToolUse `if:Bash(gh pr create)` → the gate script. | 2 |
| `skills/allow/SKILL.md` | `/pr-autopilot:allow [owner/repo]` — validate + append to allowlist. | 3 |
| `skills/pause/SKILL.md`, `skills/resume/SKILL.md` | `/pr-autopilot:pause` / `:resume` — touch/rm the sentinel. | 4 |
| `skills/step/SKILL.md` | Record `autoTriggered`/`triggerSource` on nudge-originated start (state-init addition only). | 5 |
| `SHIP-INTEGRATION.md`, `ROADMAP.md`, `README.md`, `docs/DESIGN.md`, v0.2 spec | Reconciliation per spec appendix. | 6 |
| `EVAL.md` | Scenarios 25–30 + update scenario 14. | 7 |
| `.claude-plugin/plugin.json` | Bump 0.3.0 + register new commands. | 8 |

**Ordering:** gate script first (it's the core, everything else wires to it), then hook config, then commands, then state/docs/eval/version, then verification.

---

### Task 1: Gate script + test harness

**Files:**
- Create: `hooks/pr-autopilot-trigger.sh`
- Create: `hooks/tests/test-trigger.sh`

- [ ] **Step 1: Write the failing test harness**

Create `hooks/tests/test-trigger.sh`. It overrides `PR_AUTOPILOT_HOME` to a temp dir and builds throwaway git repos with fake origins so tests never touch real state.

```bash
#!/usr/bin/env bash
# Tests for pr-autopilot-trigger.sh. Run: bash hooks/tests/test-trigger.sh
set -u
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/pr-autopilot-trigger.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PR_AUTOPILOT_HOME="$TMP/home"
mkdir -p "$PR_AUTOPILOT_HOME"
pass=0; fail=0
check() { # name expected_substring actual
  if printf '%s' "$3" | grep -qF "$2"; then pass=$((pass+1)); echo "ok   - $1";
  else fail=$((fail+1)); echo "FAIL - $1 (wanted '$2', got '$3')"; fi
}
check_empty() { # name actual
  if [ -z "$2" ]; then pass=$((pass+1)); echo "ok   - $1";
  else fail=$((fail+1)); echo "FAIL - $1 (wanted empty, got '$2')"; fi
}
mkrepo() { # dir owner/repo  -> a git repo whose origin is that github repo
  local d="$TMP/$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" remote add origin "https://github.com/$2.git"; echo "$d"
}
payload() { # command cwd
  jq -n --arg c "$1" --arg w "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}'
}

REPO_OK="$(mkrepo allowed MarcinSufa/exo-vault)"
REPO_NO="$(mkrepo other MarcinSufa/secret-thing)"
printf 'MarcinSufa/exo-vault\n' > "$PR_AUTOPILOT_HOME/allowed-repos"

# W4: all gates pass -> nudge JSON
out="$(payload "gh pr create --fill" "$REPO_OK" | bash "$SCRIPT")"
check "W4 happy path emits nudge" '"additionalContext"' "$out"
check "W4 nudge names repo"        'MarcinSufa/exo-vault' "$out"

# Gate 0: not a pr-create command -> empty
out="$(payload "gh pr list" "$REPO_OK" | bash "$SCRIPT")"
check_empty "Gate0 non-pr-create -> empty" "$out"

# W1: draft -> empty
out="$(payload "gh pr create --draft" "$REPO_OK" | bash "$SCRIPT")"
check_empty "W1 --draft -> empty" "$out"
out="$(payload "gh pr create -d" "$REPO_OK" | bash "$SCRIPT")"
check_empty "W1 -d -> empty" "$out"

# W2: non-allowlisted repo -> empty
out="$(payload "gh pr create" "$REPO_NO" | bash "$SCRIPT")"
check_empty "W2 non-allowlisted -> empty" "$out"

# W3: paused -> empty
touch "$PR_AUTOPILOT_HOME/paused"
out="$(payload "gh pr create" "$REPO_OK" | bash "$SCRIPT")"
check_empty "W3 paused -> empty" "$out"
rm -f "$PR_AUTOPILOT_HOME/paused"

# W5: malformed stdin -> exit 0, empty stdout
out="$(printf 'not json' | bash "$SCRIPT"; echo "exit=$?")"
check "W5 malformed -> exit 0" "exit=0" "$out"

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" = "0" ]
```

- [ ] **Step 2: Run the harness to confirm it fails (script doesn't exist yet)**

Run: `bash hooks/tests/test-trigger.sh`
Expected: fails — `pr-autopilot-trigger.sh` not found / all checks FAIL.

- [ ] **Step 3: Write the gate script**

Create `hooks/pr-autopilot-trigger.sh`:

```bash
#!/usr/bin/env bash
# pr-autopilot auto-trigger gate (PostToolUse hook).
# Reads hook JSON on stdin. Emits an additionalContext nudge IFF the command is
# `gh pr create`, not a draft, the repo is allowlisted, and not paused.
# ALWAYS exits 0 — a hook error must never break the user's Bash flow.
set -u
HOME_DIR="${PR_AUTOPILOT_HOME:-$HOME/.pr-autopilot}"
mkdir -p "$HOME_DIR" 2>/dev/null || true
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$HOME_DIR/hook.log" 2>/dev/null || true; }

payload="$(cat 2>/dev/null || true)"
command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$command" ] || { log "no command; skip"; exit 0; }

# GATE 0 — must be `gh pr create` (correctness floor when `if` unavailable)
printf '%s' "$command" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || exit 0

# GATE 1 — skip drafts (--draft, --draft=true, -d)
if printf '%s' "$command" | grep -qE '(^|[[:space:]])(--draft|-d)([[:space:]=]|$)'; then
  log "draft; skip"; exit 0
fi

# GATE 3 — paused (cheap; before any git work)
[ -f "$HOME_DIR/paused" ] && { log "paused; skip"; exit 0; }

# GATE 2 — allowlist
[ -n "$cwd" ] || { log "no cwd; skip"; exit 0; }
url="$(git -C "$cwd" remote get-url origin 2>/dev/null || true)"   # origin only
[ -n "$url" ] || { log "no origin remote; skip"; exit 0; }
repo="$(printf '%s' "$url" | sed -E 's#^.*github\.com[:/]+##; s#\.git$##')"
case "$repo" in */*) : ;; *) log "cannot parse repo from $url; skip"; exit 0 ;; esac
allow="$HOME_DIR/allowed-repos"
[ -f "$allow" ] || { log "no allowlist; skip"; exit 0; }
match=0
while IFS= read -r line || [ -n "$line" ]; do
  line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"  # trim
  [ -z "$line" ] && continue                                                       # skip blank
  case "$line" in */*) : ;; *) continue ;; esac                                    # require slash
  [ "$line" = "$repo" ] && { match=1; break; }
done < "$allow"
[ "$match" = "1" ] || { log "repo $repo not allowed; skip"; exit 0; }

# All gates passed — emit nudge. Claude supplies the PR number.
statekey="$(printf '%s' "$repo" | tr '/' '-')"
nudge="pr-autopilot auto-trigger: you just created a PR in ${repo} (an allowed repo). When you finish your current task (e.g. /ship), start the autopilot loop on it: (1) resolve the PR number with \`gh pr view --json number -q .number\` on the current branch; (2) if ${HOME_DIR}/${statekey}-<N>.json already exists, a loop is already running for it — do NOT start a second; (3) otherwise call ScheduleWakeup(delaySeconds=30, prompt='/loop /pr-autopilot:step <N>', reason='autopilot auto-start'). Do not begin unrelated work to start this loop."
jq -n --arg ctx "$nudge" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
log "nudged for $repo"
exit 0
```

Make it executable: `chmod +x hooks/pr-autopilot-trigger.sh`.

- [ ] **Step 4: Run the harness to confirm it passes**

Run: `bash hooks/tests/test-trigger.sh`
Expected: all checks `ok`, final line `pass=8 fail=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add hooks/pr-autopilot-trigger.sh hooks/tests/test-trigger.sh
git commit -m "feat(hook): auto-trigger gate script + test harness (4 gates, exit-0-safe)"
```

---

### Task 2: Hook configuration

**Files:**
- Create: `hooks/hooks.json`

- [ ] **Step 1: Write hooks.json**

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

- [ ] **Step 2: Verify JSON validity + structure**

Run: `jq -e '.hooks.PostToolUse[0].hooks[0].command' hooks/hooks.json`
Expected: prints the command string (valid JSON, path present).
Run: `jq -e '.hooks.PostToolUse[0].matcher == "Bash" and (.hooks.PostToolUse[0].if // "" | test("gh pr create"))' hooks/hooks.json`
Expected: `true`.

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat(hook): wire PostToolUse if:Bash(gh pr create) to gate script"
```

---

### Task 3: `/pr-autopilot:allow` command

**Files:**
- Create: `skills/allow/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `skills/allow/SKILL.md`:

```markdown
---
name: allow
description: Add a repo to the pr-autopilot auto-trigger allowlist. Use /pr-autopilot:allow <owner/repo> (or no arg for the current repo). The auto-trigger hook only fires for allowlisted repos.
---

# /pr-autopilot:allow [owner/repo]

Adds a repository to `~/.pr-autopilot/allowed-repos` so the auto-trigger hook will nudge autopilot on PRs created there.

## Steps

1. Determine the target repo:
   - If an argument `<owner/repo>` was given, use it.
   - Else resolve the current repo: `git remote get-url origin` → parse `owner/repo` (strip `github.com[:/]` prefix and `.git` suffix). If no origin remote, STOP: "Not in a git repo with a github origin — pass an explicit owner/repo."
2. Validate it exists: `gh repo view <owner/repo> --json nameWithOwner -q .nameWithOwner`. If it fails, STOP: "Repo <owner/repo> not found or not accessible — check the name / your gh auth."
3. Ensure the file and dedupe:
   ```bash
   mkdir -p ~/.pr-autopilot
   touch ~/.pr-autopilot/allowed-repos
   grep -qxF "<owner/repo>" ~/.pr-autopilot/allowed-repos || echo "<owner/repo>" >> ~/.pr-autopilot/allowed-repos
   ```
4. Confirm to the user: "Auto-trigger enabled for <owner/repo>. New PRs there will auto-start autopilot (skip with /pr-autopilot:pause; drafts are ignored)." Show the current allowlist: `cat ~/.pr-autopilot/allowed-repos`.

Idempotent: re-running for an already-listed repo is a no-op.
```

- [ ] **Step 2: Verify frontmatter + key behavior present**

Run: `grep -nE "^name: allow|grep -qxF|gh repo view" skills/allow/SKILL.md`
Expected: hits for the name, the dedupe grep, and the validation command.

- [ ] **Step 3: Commit**

```bash
git add skills/allow/SKILL.md
git commit -m "feat(cmd): /pr-autopilot:allow — manage auto-trigger allowlist"
```

---

### Task 4: `/pr-autopilot:pause` and `:resume`

**Files:**
- Create: `skills/pause/SKILL.md`
- Create: `skills/resume/SKILL.md`

- [ ] **Step 1: Write pause skill**

Create `skills/pause/SKILL.md`:

```markdown
---
name: pause
description: Temporarily suppress pr-autopilot auto-trigger without changing the allowlist. Use /pr-autopilot:pause. Re-enable with /pr-autopilot:resume.
---

# /pr-autopilot:pause

Suppresses the auto-trigger hook globally (the allowlist is preserved).

## Steps

1. `mkdir -p ~/.pr-autopilot && touch ~/.pr-autopilot/paused`
2. Confirm: "Auto-trigger paused. PR creation will not start autopilot until /pr-autopilot:resume. (Allowlist unchanged.)"
```

- [ ] **Step 2: Write resume skill**

Create `skills/resume/SKILL.md`:

```markdown
---
name: resume
description: Re-enable pr-autopilot auto-trigger after a pause. Use /pr-autopilot:resume.
---

# /pr-autopilot:resume

Removes the pause sentinel so the auto-trigger hook fires again for allowlisted repos.

## Steps

1. `rm -f ~/.pr-autopilot/paused`
2. Confirm: "Auto-trigger resumed for allowlisted repos."
```

- [ ] **Step 3: Verify**

Run: `grep -l "paused" skills/pause/SKILL.md && grep -l "rm -f ~/.pr-autopilot/paused" skills/resume/SKILL.md`
Expected: both files print.

- [ ] **Step 4: Commit**

```bash
git add skills/pause/SKILL.md skills/resume/SKILL.md
git commit -m "feat(cmd): /pr-autopilot:pause + :resume — kill switch via sentinel"
```

---

### Task 5: Record auto-trigger provenance in loop state

**Files:**
- Modify: `skills/step/SKILL.md` (the `### 0.5 Load state` / state-init area)

- [ ] **Step 1: Locate the state-init / createNew area**

Run: `grep -n "createNew(prNumber)\|stateSchemaVersion" skills/step/SKILL.md`
Expected: the load-state block and the v2 schema.

- [ ] **Step 2: Add the provenance note**

In `### 0.5 Load state`, immediately after the `if [ -f "$STATE_FILE" ] … createNew …` line, add:

```markdown
**Auto-trigger provenance:** When this step was reached because the auto-trigger hook nudged you (the invoking prompt is `/loop /pr-autopilot:step <N>` originating from the hook's `additionalContext`, not a manual user invocation), set on the new state: `"autoTriggered": true, "triggerSource": "posttooluse-hook"`. For manual invocations, set `"autoTriggered": false`. This is informational only (telemetry / debugging) and does not change loop behavior.
```

- [ ] **Step 3: Verify**

Run: `grep -n "autoTriggered\|posttooluse-hook" skills/step/SKILL.md`
Expected: the new provenance note.

- [ ] **Step 4: Commit**

```bash
git add skills/step/SKILL.md
git commit -m "feat(skill): record autoTriggered/triggerSource provenance in loop state"
```

---

### Task 6: Docs reconciliation

**Files:**
- Modify: `SHIP-INTEGRATION.md`, `ROADMAP.md`, `README.md`, `docs/DESIGN.md`, `docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md`

- [ ] **Step 1: SHIP-INTEGRATION.md — replace the v0.3 placeholder**

Replace the "v0.3+ planned behavior" section body with the actual mechanism:

```markdown
## v0.3 behavior (auto-trigger — shipped)

A plugin-shipped `PostToolUse` hook (`if: "Bash(gh pr create)"`) runs a gate script that
nudges Claude to auto-start the loop after a PR is created in an allowlisted repo. It does
NOT scan Bash output (hooks can't see output) — Claude supplies the PR number from context.
Gates: is-pr-create / draft-skip / allowlist / paused. Kill switch: `/pr-autopilot:pause`
(touches `~/.pr-autopilot/paused`); re-enable with `/pr-autopilot:resume`. There is no
`PR_AUTOPILOT_DISABLE` env var — the paused sentinel replaces it. Spec:
`docs/superpowers/specs/2026-05-24-pr-autopilot-v0.3-auto-trigger-design.md`.
```
Remove any remaining `PR_AUTOPILOT_DISABLE=1` mention in the file.

- [ ] **Step 2: ROADMAP.md — update v0.3 entry**

Run: `grep -n "v0.3" ROADMAP.md`. Change the v0.3 entry to:
```markdown
## v0.3 — Auto-trigger (in progress)
Plugin-shipped PostToolUse hook (`if:Bash(gh pr create)`) + `/pr-autopilot:allow` allowlist + `/pause`/`/resume`. In-session best-effort nudge. (Mode Y final-pass is NOT here — deferred to its own later spec.)
```
Ensure the words "Mode Y final-pass" no longer appear in the v0.3 bullet.

- [ ] **Step 3: README.md — add Auto-trigger section**

Add after the "Two rotation modes" section:
```markdown
### Auto-trigger (v0.3, beta)

Enable the plugin, then `/pr-autopilot:allow <owner/repo>` (or no arg for the current repo).
After that, creating a PR there (e.g. via `/ship`) auto-starts autopilot — no manual
`/pr-autopilot:step`. Draft PRs are skipped. Pause anytime with `/pr-autopilot:pause`
(re-enable `/pr-autopilot:resume`).

It's a **best-effort in-session nudge** (Claude Code hooks can't force actions), and **beta
until the live exo-vault dogfood (EVAL scenario 28) confirms the full auto-chain**. If the
nudge is ever missed, the manual `/pr-autopilot:step <PR#>` path still works.
```

- [ ] **Step 4: docs/DESIGN.md — extend the supersession stub**

In the `> PARTIALLY SUPERSEDED` blockquote, add: "Auto-trigger is now specified in `docs/superpowers/specs/2026-05-24-pr-autopilot-v0.3-auto-trigger-design.md`; any `PR_AUTOPILOT_DISABLE` reference here is superseded by the `~/.pr-autopilot/paused` sentinel."

- [ ] **Step 5: v0.2 spec — historical note**

At the top of `docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md`, under the Status line, add: "> **Note:** this spec's version-plan table (which listed `/install` and `PR_AUTOPILOT_DISABLE`) is historical. The v0.3 spec is canonical for auto-trigger: plugin-shipped hook + allowlist + `paused` sentinel, no `/install`."

- [ ] **Step 6: Verify all five**

Run: `grep -rl "auto-trigger — shipped\|Auto-trigger (in progress)\|Auto-trigger (v0.3, beta)" SHIP-INTEGRATION.md ROADMAP.md README.md && grep -c "PR_AUTOPILOT_DISABLE" SHIP-INTEGRATION.md`
Expected: the three files print; `PR_AUTOPILOT_DISABLE` count in SHIP-INTEGRATION.md is `0`.

- [ ] **Step 7: Commit**

```bash
git add SHIP-INTEGRATION.md ROADMAP.md README.md docs/DESIGN.md docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md
git commit -m "docs: reconcile ship/roadmap/readme/design/v0.2 for v0.3 auto-trigger"
```

---

### Task 7: EVAL scenarios 25–30 + update 14

**Files:**
- Modify: `EVAL.md`

- [ ] **Step 1: Update scenario 14**

Run: `grep -n "PR_AUTOPILOT_DISABLE" EVAL.md`. Rewrite scenario 14's row to:
`| 14 | **Kill switch: paused sentinel** | `/pr-autopilot:pause` (touch `~/.pr-autopilot/paused`) then create a PR in an allowed repo | Gate 3 fires; hook emits no nudge; no loop starts. `/pr-autopilot:resume` restores. |`

- [ ] **Step 2: Append scenarios 25–30 to the table**

```markdown
| 25 | **Auto-trigger: allowlist reject** | `gh pr create` in a repo NOT in allowed-repos | Gate 2 fails; hook silent; no nudge, no loop |
| 26 | **Auto-trigger: draft skip** | `gh pr create --draft` (and `-d`) in an allowed repo | Gate 1 fires; no nudge |
| 27 | **Auto-trigger: paused** | `paused` sentinel present, allowed non-draft PR | Gate 3 fires; no nudge |
| 28 | **Auto-trigger: happy auto-chain** (live dogfood) | allowed repo, non-draft, not paused; run `/ship` | hook nudges → Claude resolves PR# → ScheduleWakeup starts the loop → loop runs to its normal terminal state |
| 29 | **Auto-trigger: duplicate guard** | PR already has a `~/.pr-autopilot/<repo>-<N>.json` state file | nudge's idempotency clause → Claude does NOT start a second loop |
| 30 | **Auto-trigger: nudge ignored (fail-safe)** | hook nudges but Claude finishes /ship without acting | no error, no state corruption; manual `/pr-autopilot:step <N>` still works |
```

- [ ] **Step 3: Verify**

Run: `grep -nE "\| 25 \||\| 26 \||\| 27 \||\| 28 \||\| 29 \||\| 30 \|" EVAL.md && grep -c "PR_AUTOPILOT_DISABLE" EVAL.md`
Expected: scenarios 25–30 present; `PR_AUTOPILOT_DISABLE` count `0`.

- [ ] **Step 4: Commit**

```bash
git add EVAL.md
git commit -m "test(eval): add auto-trigger scenarios 25-30, update 14 to paused sentinel"
```

---

### Task 8: Version bump + command registration

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Bump version**

Change `"version": "0.2.0"` → `"version": "0.3.0"`.

- [ ] **Step 2: Register commands if the manifest lists them**

Inspect: `jq '.' .claude-plugin/plugin.json`. If the manifest has a `commands`/`skills` array enumerating slash commands, add `allow`, `pause`, `resume`. If commands are auto-discovered from `skills/*/SKILL.md` (no explicit array), leave as-is (the new skill dirs are picked up automatically).

- [ ] **Step 3: Verify**

Run: `jq -e '.version == "0.3.0"' .claude-plugin/plugin.json`
Expected: `true`.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump plugin version to 0.3.0"
```

---

### Task 9: Verification matrix (W1–W7)

- [ ] **Step 1: W1–W5 — gate script (automated)**

Run: `bash hooks/tests/test-trigger.sh`
Expected: `pass=8 fail=0`, exit 0. (Covers W1 draft-skip, W2 allowlist-reject, W3 paused, W4 happy-path-nudge, W5 malformed-exit-0, plus Gate 0.)

- [ ] **Step 2: W6 — hooks.json valid + `if` present**

Run: `jq empty hooks/hooks.json && jq -e '.hooks.PostToolUse[0].if | test("gh pr create")' hooks/hooks.json`
Expected: no parse error; `true`.

- [ ] **Step 3: W7 — plugin-path command resolves on a real install**

Load the plugin via `claude --plugin-dir <repo>` (or the marketplace install path). In a test clone of an allowlisted repo, run a real `gh pr create` (or a draft to confirm skip). Confirm the hook fires and the gate script runs (check `~/.pr-autopilot/hook.log` for a `nudged for …` or skip line). If `${CLAUDE_PLUGIN_ROOT}` does not resolve, consult the Claude Code plugin-hooks reference for the correct path variable and update `hooks/hooks.json` (Task 2), then re-verify.

- [ ] **Step 4: Record results + commit**

Append a `## v0.3 verification (W1–W7)` section to `EVAL.md` with pass/fail + date.
```bash
git add EVAL.md
git commit -m "test(eval): record v0.3 W1-W7 verification results"
```

---

### Task 10: Live dogfood — scenario 28 (deferred; needs a live PR)

Run after Tasks 1–9 land and the plugin is installed. This is the live exo-vault auto-chain that flips v0.3 from "beta" to proven, and simultaneously advances v1.0.0 evidence.

- [ ] **Step 1:** `/pr-autopilot:allow MarcinSufa/exo-vault` (the only allowlisted repo initially).
- [ ] **Step 2:** On a real exo-vault feature branch with a small change, run `/ship` (creates a non-draft PR).
- [ ] **Step 3:** Confirm: hook nudges → Claude resolves the PR number → `ScheduleWakeup('/loop /pr-autopilot:step <N>')` fires → the loop runs (Mode X or Y per config) and reaches a terminal state. Watch `~/.pr-autopilot/hook.log` and the loop's PushNotifications.
- [ ] **Step 4:** Record scenario 28 result in `EVAL.md`; if clean, drop the "beta" qualifier in README.

---

## Finishing the branch

After Tasks 1–9 pass, use `superpowers:finishing-a-development-branch`. Per repo CLAUDE.md: don't push/merge without explicit user approval; `feature/v0.3-auto-trigger` → `main` only after sign-off. Run the secrets-scan-before-public-push sweep (it's a public repo). Tag `v0.3.0` on merge if the user approves. Task 10 (live dogfood) may trail the merge.
