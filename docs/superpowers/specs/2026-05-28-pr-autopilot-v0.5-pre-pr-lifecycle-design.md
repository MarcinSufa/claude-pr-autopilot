# `pr-autopilot v0.5` — Pre-PR Lifecycle (Assignment Claim + Spec Review)

**Date:** 2026-05-28
**Worktree:** `../claude-pr-autopilot-v0.5` on `feat/v0.5-pre-pr-lifecycle` off `origin/main@3669d9f`
**Status:** v2.2 — **APPROVED** by Marcin 2026-05-28 (via AskUserQuestion dogfooding) + Composer 2.5 v2.1 (9/10). Implementation in progress.
**Builds on:** v0.4 (`docs/superpowers/specs/2026-05-24-pr-autopilot-v0.4-auto-merge-design.md`)
**ROADMAP coordination:** this spec claims v0.5. The previously-tentative "Cursor-native runtime adapter (Path C)" moves down to v0.6 in `ROADMAP.md` — separate file edit included with this PR.

---

## Summary

`pr-autopilot v0.5` extends the post-PR review loop (v0.1–v0.4) with a complete **pre-PR lifecycle**: assignment claim, atomic worktree creation, spec drafting, pre-PR spec review, hard-gated user approval, and post-merge cleanup. After v0.5, `pr-autopilot` covers the entire dev cycle from **"I want to claim a task"** through **"PR merged + cleanup done"** — not just the PR loop.

**Naming convention (final):** the unit of work is an **assignment** (not "slice"). User-facing commands use `assign` / `unassign` / `finish`; the project's queue file is `assignments.yaml`.

**Five new skills** (`assign`, `review-spec`, `approve-spec`, `pr-opened`, `finish`) + one optional housekeeping skill (`unassign`) + two hooks (`check-origin-main.sh` SessionStart + `enforce-spec-gate.sh` PreToolUse) + templates for project onboarding. Zero changes to v0.4 skills — they continue to work unchanged.

**Shares with v0.4** the PUSHBACK.md rubric and SELF-REVIEW-RUBRIC.md — both apply to pre-PR spec findings the same way they apply to post-PR code findings. New **pre-PR adapter invocation paths** (see §Pre-PR Adapter Layer) — these are NOT the same wire calls as v0.4 post-PR adapters, even though they share the same rubric.

---

## Motivation

v0.4 closes the post-PR loop beautifully. Three pain points remain on the pre-PR side, observed empirically in a real session (2026-05-28 Asistel PR #21 + post-merge follow-up):

1. **Stale local main, wasted planning.** One agent spent ~1h drafting a greenfield spec for slices already merged to `origin/main`. The rule "verify branch before checkout -b" was applied too late — by the time you reach `checkout -b`, you've already invested an hour planning the wrong thing.
2. **No atomic claim primitive.** When two agents try to work on the same work-unit in parallel, they collide on shared files. v0.5 needs a real lock, not discipline.
3. **No enforceable "spec before code" gate.** Marcin's workflow rule #3 says "spec → review → user approval → only then tests." But there's no slash command + hook combination that makes this a HARD gate; agents skip the spec, or write but never trigger review, or call review but bypass user-approval before TDD.

v0.5 fixes all three.

---

## Goals

- **G1:** Every Claude Code session in an opt-in repo runs `git fetch origin main` + reports diff vs local `main` and assignment-base — before any planning.
- **G2:** Assignments are declared in machine-readable form (`assignments.yaml`) with hard deps, status, files-touched, and a kickoff prompt.
- **G3:** `pr-autopilot:assign <id>` atomically claims an assignment using `git worktree add -b <branch> origin/main` as the underlying lock primitive (filesystem-atomic via git refs), creates the worktree, instructs the agent to draft a spec **first** — not code.
- **G4:** `pr-autopilot:review-spec` dispatches **pre-PR adapter invocations** (different from v0.4 post-PR adapters; share rubric) against a markdown spec file. Aggregates findings; flips assignment sub-status.
- **G5:** `pr-autopilot:approve-spec` is a user-only action (uses `AskUserQuestion` interactive primitive) that **hard-gates** TDD via a PreToolUse hook (`enforce-spec-gate.sh`). Agent **cannot** write/edit outside `specs/` until claim file has `subStatus: implementing` (or `pr_*`) with non-null `approvedAt`. (v2.1: `spec_approved` was dropped as a separate state; `/approve-spec` flips directly to `implementing`.)
- **G6:** `pr-autopilot:pr-opened <PR#>` bridges to v0.4 — flips sub-status to `pr_opened`, hands off to `/loop /pr-autopilot:step <PR#>`.
- **G7:** `pr-autopilot:finish <id>` (post-merge) updates assignment claim file + ExoVault task → `merged`, stamps `assignments.yaml` with `status: merged` + merge metadata.
- **G8:** All new logic respects v0.4 pause sentinel (`~/.pr-autopilot/paused`) and opt-in allowlist (`/pr-autopilot:allow`) — **except** the SessionStart hook, which always runs (pre-PR safety net, see §Hook policy).

## Non-goals

- Replacing v0.4 `step` / `automerge` / `allow` / `pause` / `resume`. Unchanged.
- Auto-firing `assign` for ready assignments. (Hypothetical Phase 3.)
- Auto-`approve-spec` heuristics. Marcin is always the final gate.
- Replacing reviewer rubrics. `/review-spec` uses PUSHBACK.md + SELF-REVIEW-RUBRIC.md unchanged.
- True message-bus between agents (ExoVault `messages` is web-UI-only at present; v0.5 does not depend on cross-agent comm beyond the assignment claim file).

---

## State machine (v2.1 — simplified, P0-4 + P1-7 fixes)

ExoVault enum is coarse (`backlog | todo | in_progress | done | blocked`). Fine-grained `subStatus` lives in the **assignment claim file** (filesystem source of truth) AND mirrored to ExoVault task `description` markdown.

`spec_approved` as a standalone state is **dropped in v2.1** (P0-4 resolution): `/approve-spec` flips directly to `implementing`. The hook treats `implementing` (and `pr_*` states) as the "gate lifted" set. This removes the gap where `pr-opened` rejected after agent left `spec_approved` without auto-transition.

```
   todo ───/assign───► spec_drafting ───agent writes spec───► spec_review_requested
                                                                  │
   ┌──────────────────────────────────────────────────────────────┤
   │ /review-spec finds P0                                        │ /review-spec finds 0 P0
   ▼                                                              ▼
spec_revising ──agent fixes─► spec_review_requested (re-loop)  spec_review_complete
                                                                  │
                                                                  │ /approve-spec
                                                                  │ (AskUserQuestion confirm
                                                                  │  + approvedAt + approvedBy
                                                                  │  written to claim file)
                                                                  ▼
                                                            implementing  ◄── HARD GATE lifted
                                                                  │ (hook allows Write/Edit
                                                                  │  outside specs/)
                                                                  │
                                                                  │ agent TDD red→green
                                                                  │ then gh pr create
                                                                  ▼
                                                            pr_opened
                                                                  │ /pr-opened <PR#>  ─┐
                                                                  ▼                    │
                                                            pr_review_requested        │
                                                                  │                    │
                                                                  │ /step finds P0     │
                                                                  ▼                    │
                                                            pr_revising ──fix──┐       │
                                                                  ▲            │       │
                                                                  └────────────┘       │
                                                                  │ /step approves     │
                                                                  ▼                    │
                                                            merged ◄─── /finish ◄──────┘
                                                                       (PR merged on GitHub)

Blocked sub-statuses (mapped to ExoVault status='blocked'):
  awaiting_user_decision   — Marcin must resolve an open question
  awaiting_deps_merge      — another assignment must merge first
```

P1-7 fix: `spec_revising` re-loops to `spec_review_requested` (not `pr_review_requested` — that arrow in v2 diagram was a typo).
P1-2 fix: `spec_review_complete` is the exit state of `/review-spec` with 0 P0 findings.

---

## Atomic claim — git as primitive (P0-2 resolution)

**Insight:** `git worktree add -b <branch> origin/main` is **filesystem-atomic** via git's ref-creation. Two concurrent agents trying to claim the same assignment race on branch creation; exactly one wins, the other gets `fatal: a branch named '<branch>' already exists`.

This eliminates the need for ExoVault CAS/version fields, polling, or re-read protocols. ExoVault remains an **observable mirror**, not the critical path.

### Claim file (source of runtime truth)

After winning the branch-creation race, the assigning agent commits to its new branch:

```
.claude/assignment-claims/<id>.json
```

Schema:

```json
{
  "assignmentId": "admin-d1-locations",
  "agentId": "<from session>",
  "claimedAt": "2026-05-28T16:00:00Z",
  "subStatus": "spec_drafting",
  "branch": "feat/admin/d1-locations-polish",
  "worktreePath": ".claude/worktrees/admin-d1-locations",
  "specFile": null,
  "prNumber": null,
  "prUrl": null,
  "reviewIteration": 0,
  "reviewers": [],
  "approvedAt": null,
  "approvedBy": null,
  "approvalContext": null,
  "mergedAt": null,
  "mergedInPr": null
}
```

**Field semantics (v2.2 — P1-6 fix, complete schema):**

| Field | Set by | When |
|---|---|---|
| `assignmentId`, `agentId`, `claimedAt`, `branch`, `worktreePath` | `/assign` | At claim time, never mutated |
| `subStatus` | every transitioning skill | State machine transitions |
| `specFile` | agent (after drafting) or `/review-spec` (auto-detect newest) | First `/review-spec` invocation |
| `reviewIteration`, `reviewers[]` | `/review-spec` | Each review pass |
| `approvedAt`, `approvedBy`, `approvalContext` | `/approve-spec` ONLY (after AskUserQuestion) | User explicitly approves; hook reads these to validate `implementing` transition is genuine |
| `prNumber`, `prUrl` | `/pr-opened` | After PR creation |
| `mergedAt`, `mergedInPr` | `/finish` | After PR merged on GitHub |

This file is:
- Branch-scoped (lives only on the claiming branch).
- Read by every v0.5 skill + the `enforce-spec-gate.sh` hook.
- Updated atomically by skills (`review-spec`, `approve-spec`, `pr-opened`, `finish`).
- Committed on every transition so history is auditable via `git log .claude/assignment-claims/`.

### Slug

`slug = assignmentId` (verbatim — P1-5 fix). No separate naming.

### Worktree recovery (P1-4 fix)

If a previous session crashed mid-claim:
- `git worktree list` shows orphan: `.claude/worktrees/<slug> [feat/...]`.
- Re-running `/assign <id>` detects existing worktree, reads the claim file, reports current sub-status, and offers to continue (no re-create).
- If user wants a clean restart: `/pr-autopilot:unassign <id>` first (housekeeping skill below).

---

## Pre-PR Adapter Layer (P0-1 resolution)

`/review-spec` does **NOT** call v0.4 post-PR adapters as-is. The invocation paths are different even though the rubric (PUSHBACK.md, SELF-REVIEW-RUBRIC.md) is shared.

### Interface

Every pre-PR adapter implements:

```
adapter.reviewSpec(input: { specFilePath: string, assignmentId: string })
  → Promise<Findings[]>
```

Findings format identical to v0.4 (PUSHBACK rubric):

```json
{ "priority": "P0" | "P1" | "P2", "confidence": 5..10, "title": "...", "body": "...", "filePath": "...", "line": null }
```

### Adapter inventory

| # | Adapter | Cost | Wire call | Sync/Async | Default ON? |
|---|---|---|---|---|---|
| 1 | `claude-code-reviewer-subagent` | 🟢 FREE | `Agent({ subagent_type: 'feature-dev:code-reviewer', prompt: ... })` | SYNC inline | ✅ YES |
| 2 | `claude-self-review` (hostile) | 🟢 FREE | `Agent({ subagent_type: 'general-purpose', prompt: ... })` parallel | SYNC inline | ✅ YES |
| 3 | `composer-2.5-manual` | 🟢 FREE (Cursor Free) | Agent prints copy-paste prompt; user runs Composer (Cmd+I), pastes back | MANUAL ~30s | ✅ YES (prompts user) |
| 4 | `codex-exec` | 🟡 PAID ($20 ChatGPT Plus or OpenAI API token) | `Bash codex exec --json --sandbox read-only --ask-for-approval never <prompt>` | SYNC inline | ❌ Opt-in: requires `OPENAI_API_KEY` env OR `codex` CLI on PATH |
| 5 | `cursor-cloud-agent` | 🟡 PAID ($20 Cursor Pro) | `POST https://api.cursor.com/v1/agents` with `model.id: "composer-2.5"`, `autoCreatePR: false`. **Poll contract (P1-5 fix):** poll `GET /v1/runs/<id>` every 5s until `status: done` OR 120s elapsed. If timeout → record `{ id, status: 'pending', timeoutAt: <iso> }` in claim file `reviewers` array; `/review-spec` is **idempotent** — re-running it fetches pending Cursor results and folds in. Does NOT block `spec_review_complete` transition. | SEMI-ASYNC (poll w/ timeout) | ❌ Opt-in: requires `CURSOR_API_KEY` env |
| 6 | `marcin` | 🟢 FREE | User reads spec, decides | MANUAL | ✅ YES (mandatory final via `approve-spec`) |

P1-7 fix: `composer-2.5` consistently (not `composer-2`) — confirmed against Cursor Cloud Agents API docs which list `composer-2.5` as available model.id.

### Coverage per command

| Command | Adapters fired |
|---|---|
| `review-spec` (pre-PR, markdown file) | 1, 2, 3, 4 (if env), 5 (if env) — Cursor PR bot / Copilot PR bot SKIPPED (they only trigger on PR push) |
| v0.4 `step` (post-PR, code diff) | v0.4 adapters unchanged — Cursor PR bot + Copilot PR bot + Codex `review --diff` + Claude self via SELF-REVIEW-RUBRIC.md |

Same rubric (PUSHBACK.md). Different wire calls. Same Findings interface.

---

## Skill: `pr-autopilot:assign <id>`

**Purpose:** atomically claim an assignment + create worktree + brief the agent.

### Pre-flight

- Required CLIs on PATH: `gh`, `jq`, `git` (inherited from v0.4 pattern).
- ExoVault MCP reachable + `vaultId` configured (P1-6 fix — see settings snippet).
- `assignments.yaml` present in repo root.
- Repo on `/pr-autopilot:allow` allowlist; not paused (`~/.pr-autopilot/paused` absent).

### Steps

1. Read `assignments.yaml`. Find assignment with `id == <id>`. If missing → graceful error (EVAL 39).
2. If id not provided: list READY + IN_PROGRESS + BLOCKED sets.
   - **READY** = assignments where `assignments.yaml` says `status: todo` AND every entry in `deps` is either:
     (a) in `excludes` array with `pr: <number>` merged, OR
     (b) has `status: merged` in `assignments.yaml`, OR
     (c) has matching ExoVault task with `status: done`.
   - **IN_PROGRESS** = source: `mcp__exo-vault__list_tasks(status='in_progress')` filtered by `title` matching `assignment:<id>` (P1-7 fix: NOT yaml — yaml never has in_progress per truth model). Show with `assignedAgentId` from task. Optionally cross-check `git branch -r feat/*` to surface remote branches that match without ExoVault entries (recovery scenario).
   - **BLOCKED** = `status: blocked` in yaml, with `needs_decision` flag and reason in surrounding context.
   Ask user to pick from READY.
3. Verify all `deps` satisfied (EVAL 40).
4. **Atomic claim via git** (the heart of P0-2 resolution):
   ```bash
   git fetch origin main
   git worktree add .claude/worktrees/<id> -b <branch> origin/main
   ```
   If exit code != 0:
   - If error is "branch already exists" → assignment already claimed; print `git log -1 --format='%H %s' <branch>` to surface claim metadata; STOP gracefully (EVAL 41).
   - Other errors → propagate.
5. `cd .claude/worktrees/<id>`.
6. Write initial `.claude/assignment-claims/<id>.json` (claim file schema above) with `subStatus: spec_drafting`, `approvedAt: null`, `approvedBy: null`. Commit with message `chore(pr-autopilot): claim assignment <id>`.
7. Mirror to ExoVault (idempotent, P1-6 fix):
   - `list_tasks` → find task with exact title `assignment:<id>`.
   - If exists with `status: in_progress` and `assignedAgentId == <me>` → no-op (re-assign on the same worktree).
   - If exists with different `assignedAgentId` → STOP, race detected (git branch creation should have caught this earlier; defensive).
   - If exists with `status: done` and matching id → `update_task(status='in_progress', assignedAgentId=<me>)`.
   - Otherwise → `create_task(title="assignment:<id>", status="in_progress", assignedAgentId=<me>, description=<task-schema markdown>)`.
   - **Not critical path** — if MCP unreachable, log warning, continue.
8. **DO NOT mutate `assignments.yaml` on the feature branch.** (P0-3 fix: main yaml truth model excludes `in_progress`. Runtime state lives only in claim file.)
9. Load assignment's `first_prompt` from yaml. Echo to chat. Inject directive: **"Step 1: write the spec at `specs/<today>-<id>.md`. DO NOT modify any other file until spec is approved via `/pr-autopilot:approve-spec`. The PreToolUse hook will block your edits otherwise."**

### Output

- Branch name + worktree path.
- Path of expected spec file.
- Sub-status: `spec_drafting`.

---

## Skill: `pr-autopilot:review-spec`

**Purpose:** dispatch pre-PR adapter layer against the current assignment's spec file.

### Pre-flight

- Inside a worktree with `.claude/assignment-claims/<id>.json` present.
- Sub-status must be `spec_drafting` or `spec_revising` (otherwise no-op + suggestion).
- A spec file must exist at the path recorded in claim file (or auto-detect newest `specs/*-<id>.md`).

### Steps

1. Read claim file. Set `subStatus: spec_review_requested`. Commit.
2. Dispatch adapters in parallel (see §Pre-PR Adapter Layer for which are ON):
   ```
   parallel: [
     claude-code-reviewer-subagent.reviewSpec(spec),
     claude-self-review.reviewSpec(spec),
     (codex-exec.reviewSpec(spec) if env.OPENAI_API_KEY || which codex),
     (cursor-cloud-agent.reviewSpec(spec) if env.CURSOR_API_KEY),
   ]
   ```
   Plus: print composer-2.5-manual prompt block; user can paste back later.
3. Aggregate findings from sync adapters that completed. Increment `reviewIteration`. Append review entry to claim file (and to ExoVault task description mirror).
4. **Composer 2.5 manual paste handling (P1-4 fix):** the manual prompt is **advisory only**, NOT blocking. `/review-spec` may set `spec_review_complete` even if user hasn't yet pasted Composer's reply. If user wants to fold Composer's findings in later:
   - User pastes Composer reply into chat.
   - User re-runs `/review-spec` (or `/review-spec --append-manual` for explicit semantics) → skill detects paste in conversation context, appends to `reviewers[]` as `kind: composer-2.5-manual`, re-aggregates, may flip state if P0 newly surfaced.
   - Idempotent: pasting same findings twice does not duplicate entries (dedup by hash of body).
5. Decision based on aggregated findings:
   - **0 P0 findings** → set `subStatus: spec_review_complete` (P1-2 fix). Echo: "Spec review complete. Marcin: when ready, run `/pr-autopilot:approve-spec`. (Optional: paste Composer 2.5 findings for additional perspective.)"
   - **≥1 P0** → set `subStatus: spec_revising`. Echo findings + instruct agent to fix and re-run `/review-spec`.
6. Commit claim file update.

### Pre-PR adapter scope per env

| Env state | Auto channels in `review-spec` |
|---|---|
| Both env keys absent | claude-code-reviewer-subagent + claude-self-review + manual Composer prompt |
| `OPENAI_API_KEY` set | + codex-exec |
| `CURSOR_API_KEY` set | + cursor-cloud-agent |
| Both set | All 4 auto + manual prompt |

---

## Skill: `pr-autopilot:approve-spec`

**Purpose:** Marcin's user-only gate, enforced by hook + interactive primitive.

### Pre-flight

- Inside a worktree with claim file present.
- Sub-status must be `spec_review_complete` (P0-6 fix — must have reviewed first; EVAL 44 covers attempting approve without review).

### Steps (v2.1 — P0-2 + P0-4 fixes)

1. Read claim file. Verify `subStatus == spec_review_complete`. If `spec_revising` or earlier → reject: "Spec has open P0 findings or hasn't been reviewed. Run `/pr-autopilot:review-spec` first."
2. **AskUserQuestion (mandatory, interactive primitive):**
   > "Approve spec for assignment `<id>`? This unlocks Write/Edit across the entire codebase for this branch. Findings summary: <N P0 findings (resolved), M P1, K P2>. Spec: `<path>`."
   > Options: ✅ Approve · ❌ Reject (back to spec_revising) · 🔵 Show full spec

   Agent **cannot fabricate this primitive** — it's an interactive UI element with user-visible chips that the user physically clicks. Conversation transcript shows the user response verbatim, providing audit + forensic trail.
3. If user picks Approve:
   - Capture `<iso-timestamp>` and `<user-identifier>` (from session context — Claude Code surfaces it via `$CLAUDE_USER` env or session metadata).
   - Update claim file: `subStatus: implementing`, `approvedAt: <iso>`, `approvedBy: <user-identifier>`, `approvalContext: { findings: { p0: N, p1: M, p2: K }, specFile: <path> }`. Commit with message `chore(pr-autopilot): approve assignment <id> spec`.
4. If user picks Reject → set `subStatus: spec_revising`, no `approvedAt`. Commit. Echo: "Spec rejected by user. Address findings and re-run `/review-spec`."
5. Mirror to ExoVault.
6. On approve: echo "Spec approved by `<user>`. Hard gate lifted (subStatus=implementing). Proceed to TDD red → green → PR. When PR open, run `/pr-autopilot:pr-opened <PR#>` to hand off to v0.4 step loop."

**Note on `spec_approved` removal:** v2 had `spec_approved` as a standalone state between user-approval and first-code-edit. v2.1 collapses this — `/approve-spec` flips directly to `implementing`. The hook treats `implementing` as "user-approved, coding allowed". This removes the gap where `pr-opened` rejected because `spec_approved → implementing` transition was unspecified (P0-4).

### How the hard gate is enforced — `enforce-spec-gate.sh` PreToolUse hook (v2.1, P0-2 + P1-1 + P1-8 fixes)

Installed via plugin's `hooks/enforce-spec-gate.sh` + project's `.claude/settings.json` PreToolUse entry on `Write|Edit|NotebookEdit`.

```bash
#!/usr/bin/env bash
# pr-autopilot v0.5 — enforce spec-approval gate before any Write/Edit outside specs/.
# Reads tool call JSON from stdin; exit non-zero ABORTS the tool call.

set -euo pipefail

# P1-8: honor pause sentinel + allowlist (PreToolUse hook is opt-in per project).
[ -f "$HOME/.pr-autopilot/paused" ] && exit 0

# Allowlist check: read repo URL from git remote, compare to allowlist file.
REPO=$(git -C "$(pwd)" remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+/[^/.]+)(\.git)?$|\1|')
ALLOWLIST="$HOME/.pr-autopilot/allowed-repos"
if [ -f "$ALLOWLIST" ] && ! grep -qiFx "$REPO" "$ALLOWLIST" 2>/dev/null; then
  # P1-5 fix: case-insensitive match (consistent with v0.4 /allow + auto-trigger gate).
  exit 0  # not opted in, no gate
fi

INPUT=$(cat)
TARGET=$(jq -r '.tool_input.file_path // empty' <<< "$INPUT")
[ -z "$TARGET" ] && exit 0  # not a path-targeting tool call

# Walk up from CWD looking for .claude/assignment-claims/*.json (single file).
CLAIM=""
DIR="$(pwd)"
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  CANDIDATE=$(find "$DIR/.claude/assignment-claims" -maxdepth 1 -name "*.json" 2>/dev/null | head -1)
  if [ -n "$CANDIDATE" ]; then CLAIM="$CANDIDATE"; break; fi
  DIR=$(dirname "$DIR")
done
[ -z "$CLAIM" ] && exit 0  # no active claim → outside pre-PR lifecycle, allow

SUB_STATUS=$(jq -r '.subStatus // "none"' "$CLAIM")
APPROVED_AT=$(jq -r '.approvedAt // "null"' "$CLAIM")

# P1-1 fix: correct bash conditional (case statement, not invalid [[ x == a|b ]]).
case "$SUB_STATUS" in
  implementing|pr_opened|pr_review_requested|pr_revising|merged)
    # Gate lifted — but only if approvedAt is set (P0-2 fix: claim file integrity check).
    if [ "$APPROVED_AT" = "null" ] || [ -z "$APPROVED_AT" ]; then
      echo "[pr-autopilot] BLOCKED: subStatus=$SUB_STATUS but approvedAt is null." >&2
      echo "  Claim file appears tampered. /approve-spec must be invoked via AskUserQuestion." >&2
      exit 1
    fi
    exit 0
    ;;
esac

# Pre-approval states: allow only edits to specs/ + claim file itself.
case "$TARGET" in
  */specs/*|*/.claude/assignment-claims/*)
    exit 0
    ;;
  *)
    echo "[pr-autopilot] BLOCKED: spec not approved (subStatus=$SUB_STATUS)." >&2
    echo "  Run /pr-autopilot:review-spec then /pr-autopilot:approve-spec." >&2
    exit 1
    ;;
esac
```

**Gate strength (P0-2 resolution):**

| Threat | v2 design | v2.1 design |
|---|---|---|
| Agent writes code before approval | Hook blocks ✅ | Hook blocks ✅ |
| Agent edits claim file to set `subStatus: spec_approved` | Audit trail only ❌ | Hook checks `approvedAt` — null → BLOCK ✅ |
| Agent fabricates `approvedAt` timestamp | n/a | Conversation transcript audit: no preceding AskUserQuestion = forensic flag (defense-in-depth, not bulletproof) |
| Hook bypassed by tool not in matcher | Possible | Possible — matcher MUST cover Write+Edit+NotebookEdit (Bash w/ `cat >` is theoretically a hole; covered by case "edit-via-Bash" in PUSHBACK.md PR review) |

This is **strong** (interactive UI primitive + claim file integrity check), not bulletproof. Bulletproof would require signed tokens or cryptographic attestation, which is overkill for v0.5.

---

## Skill: `pr-autopilot:pr-opened <PR#>` (P1-3 fix — handoff to v0.4)

**Purpose:** bridge from pre-PR to post-PR after `gh pr create`.

### Steps (v2.2 — P1-2 fix: also sets `pr_review_requested`)

1. Read claim file. Verify `subStatus == implementing` (v2.1 — `spec_approved` state was dropped per P0-4; if a stale `spec_approved` is found, accept it with deprecation warning).
2. Fetch PR metadata via `gh pr view <PR#> --json url,number,headRefName`. Verify branch matches claim file (defensive).
3. Set `subStatus: pr_review_requested` (P1-2 fix: PR exists ⇒ review loop is about to start; v0.4 `step` will not touch the claim file, so this is the right moment to flip). Write `prNumber: <PR#>`, `prUrl: <url>`. Commit.
4. Mirror to ExoVault.
5. Echo: "PR #<N> opened. Sub-status flipped to `pr_review_requested`. Hand off to v0.4: `/loop /pr-autopilot:step <PR#>`."

State machine note: there is no separate `pr_opened` sub-status in claim file — it exists only conceptually between `gh pr create` and `/pr-opened` invocation (a few seconds). v0.4 `step` then operates against `pr_review_requested` until the v0.4 loop reports merge-ready; on user `/finish`, sub-status moves to `merged`.

Audit-trail value of this 5-line skill: the moment claim file commit records the PR linkage, future readers can trace assignment ↔ PR without searching git history.

---

## Skill: `pr-autopilot:finish <id>` (post-merge cleanup)

**Purpose:** close the loop opened by `assign`.

### Pre-flight

- `gh pr view <prNumber from claim file> --json mergedAt` returns non-null.

### Steps (v2.2 — P1-3 fix: explicit main yaml update workflow)

1. Read claim file. Verify PR merged (EVAL 46 — reject if not). Capture `mergedAt`, `mergedCommit`.
2. Update claim file (on the feature branch, before checkout): `subStatus: merged`, `mergedAt: <iso>`, `mergedInPr: <PR#>`. Commit on feature branch with message `chore(pr-autopilot): finish assignment <id>`.
3. Mirror to ExoVault: `update_task(taskId, status='done')`.
4. **Update `assignments.yaml` on `main` (the real truth update):**
   - `cd` out of worktree to main worktree root.
   - `git fetch origin main`.
   - `git checkout main`.
   - `git pull --ff-only origin main` (defensive: fast-forward only; if local main diverged, abort with clear error).
   - Edit `assignments.yaml`: locate assignment by `id`, set `status: merged`, add `merged_at: <iso>`, `merged_in_pr: <PR#>`. **Do NOT touch the `excludes:` array** (excludes is for historical/external context, not for in-flow merged assignments — fresh merges accumulate in `assignments[*].status: merged`).
   - `git add assignments.yaml && git commit -m "chore(assignments): mark <id> merged in PR #<N>"`.
   - `git push origin main` (NO `--no-verify` per P1-8). If push fails (branch protection) → echo: "main is push-protected. Open a cleanup PR with this commit: `git checkout -b chore/finish-<id>-cleanup && git push -u origin chore/finish-<id>-cleanup && gh pr create --base main`. Continue with steps 5–7 manually after that PR merges."
5. **Worktree cleanup (best-effort, non-blocking):**
   - `git worktree remove .claude/worktrees/<id>` — if it fails (uncommitted changes), echo warning + leave for manual cleanup.
   - `git branch -D <branch>` — if branch was deleted remotely (v0.4 `automerge` typically does this), local delete is safe; otherwise echo: "local branch retained — delete manually if not needed: `git branch -D <branch>`".
6. List dependent assignments whose `deps` are now all satisfied. Notify: "Newly READY after this merge: [admin-d2, admin-d3, ...]". This is informational — does not auto-claim anything.
7. **Idempotency:** if claim file already says `merged` OR main yaml already says `merged` for this id, skip mutating but still run steps 5–6 if worktree/branch still exist.

---

## Skill: `pr-autopilot:unassign <id>` (housekeeping — symmetry)

**Purpose:** release a claim without merging (agent changes mind, slice re-classified, deps blocked indefinitely).

### Steps

1. Read claim file. If sub-status `merged` → reject (use `finish` lifecycle).
2. Confirm with user (interactive prompt — this is destructive).
3. `cd` to repo root (out of worktree).
4. `git worktree remove .claude/worktrees/<id>`.
5. `git branch -D <branch>` (assumes unpushed; if pushed → instruct user to delete remote).
6. Mirror to ExoVault: `update_task(taskId, status='todo')` to release for re-claim.
7. Update `assignments.yaml`: status back to `todo`. Commit on main (or via separate PR).

---

## Hook: `check-origin-main.sh` (SessionStart — full bash, P1-3 fix)

Always runs (ignores allowlist + pause — this is pre-PR safety net, not opt-in). Two checks + 8s timeout + always `exit 0`.

```bash
#!/usr/bin/env bash
# pr-autopilot v0.5 — SessionStart safety net: warn if local main or feature branch base is stale vs origin/main.
# Output to stdout is consumed by Claude Code as session prefix context. Always exit 0.

set -u

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$REPO_ROOT" || exit 0

# Fetch with timeout. Offline → graceful skip.
if ! timeout 8 git fetch --quiet origin main 2>/dev/null; then
  echo "[pr-autopilot/origin-check] could not fetch origin/main (offline or slow); skipping."
  exit 0
fi

# A) is local `main` branch behind origin/main?
MAIN_BEHIND=$(git rev-list --count main..origin/main 2>/dev/null || echo "?")

# B) is current branch's base behind origin/main? (true rebase signal)
BASE=$(git merge-base HEAD origin/main 2>/dev/null || echo "")
if [ -n "$BASE" ]; then
  BASE_BEHIND=$(git rev-list --count "$BASE"..origin/main 2>/dev/null || echo "?")
else
  BASE_BEHIND="?"
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "(detached)")

case "$MAIN_BEHIND/$BASE_BEHIND" in
  "0/0")
    echo "[pr-autopilot/origin-check] up to date with origin/main ✓ (branch: $CURRENT_BRANCH)"
    ;;
  "0/"*)
    echo "[pr-autopilot/origin-check] ⚠ assignment base is $BASE_BEHIND commit(s) behind origin/main on '$CURRENT_BRANCH'."
    echo "  Recent missed commits:"
    git log --oneline "$BASE"..origin/main 2>/dev/null | head -5 | sed 's/^/    /'
    echo "  Consider rebasing: git fetch && git rebase origin/main"
    ;;
  *)
    echo "[pr-autopilot/origin-check] ⚠ local 'main' is $MAIN_BEHIND commit(s) behind origin/main."
    echo "  Recent missed commits:"
    git log --oneline main..origin/main 2>/dev/null | head -5 | sed 's/^/    /'
    echo "  If starting new work: git worktree add .claude/worktrees/<id> -b <branch> origin/main"
    ;;
esac

exit 0  # never block a session
```

## Hook: `enforce-spec-gate.sh` (PreToolUse — NEW per P0-6)

See body in §Skill: approve-spec → "How the hard gate is enforced".

Installed only when project opts in via settings snippet (off-by-default for v0.4 projects upgrading; opt-in via settings merge).

### Hook policy summary (P1-9 clarification)

| Hook | Honors allowlist? | Honors pause sentinel? | Reason |
|---|---|---|---|
| `check-origin-main.sh` (SessionStart) | ❌ NO | ❌ NO | Pre-PR safety net; cost is tiny (8s), false positives are zero |
| `enforce-spec-gate.sh` (PreToolUse) | ✅ YES | ✅ YES | Gates writes — pause/allowlist let user disable per-repo when needed |

---

## `assignments.yaml` schema

(P1-10 fix — schema content inline.)

```yaml
version: 1                             # schema version (this spec = 1)

excludes:                              # already-shipped assignments — context only
  - id: <id>
    pr: <number>
    merged_at: <iso-date>

assignments:                           # P0-1 fix: root key matches the unit name
  - id: <id>                           # globally unique within project (recommend <area>-<seq>-<topic>)
    title: <human>
    branch: <git-branch>               # full ref incl. feat/ prefix
    status: todo                       # todo | merged | blocked  (P0-3 fix: NO 'in_progress' on main;
                                       #   in-flight state lives in claim file only)
    deps: [<id>]                       # other assignment IDs that must be merged before ready
    blocks: [<id>]                     # informational reverse pointer (NOT validated — P2 note)
    effort: <human>                    # e.g. "0.5-1d", "2-3d"
    needs_decision: false              # if true: blocked awaiting user decision (P2: no auto-unblock skill yet)
    files_touched: [<path>]
    scope_in: [<bullet>]
    scope_out: [<bullet>]
    acceptance: [<criterion>]
    first_prompt: |
      <multi-line kickoff prompt loaded by /assign after worktree creation>
```

**Status truth model (P0-3 fix):**

| State | Where it lives | Who writes it |
|---|---|---|
| `todo` | `assignments.yaml` on `main` | initial seed (project onboarding); reset on `/unassign` |
| `merged` | `assignments.yaml` on `main` | `/finish` commits to `main` (or via cleanup PR if branch-protected) |
| `blocked` | `assignments.yaml` on `main` | `/assign` rejects with reason if found; user manually edits to set/unset |
| in-flight (`spec_drafting` → `implementing` → `pr_*`) | **Claim file** `.claude/assignment-claims/<id>.json` on the feature branch | every v0.5 skill that transitions the assignment |
| `done` (mirror) | ExoVault task `status` | `/finish` mirrors |

`main` never has `status: in_progress` — runtime state is branch-scoped. Other agents reading `main`'s yaml see a clean `todo`/`merged`/`blocked` view; to check "who's working on what now" they either inspect ExoVault `list_tasks(status='in_progress')` or `git branch -r feat/*`.

JSON Schema lives at `templates/assignments.schema.json` (full schema definition shipped with v0.5; project can validate with any YAML/JSON Schema validator).

---

## Backward compatibility

- Plugin name: `pr-autopilot` (unchanged).
- Plugin version: `0.4.0` → `0.5.0`.
- ROADMAP: this PR updates `ROADMAP.md`. Previous v0.5 ("Cursor-native runtime adapter, Path C") moves to **v0.6**.
- v0.4 skills (`allow`, `automerge`, `pause`, `resume`, `step`) — unchanged.
- v0.4 projects see no change until they opt into v0.5 by adding `assignments.yaml` + merging settings snippet.
- v0.4 PR loop continues to work for projects not using assignment lifecycle (legacy mode = create PR → `/loop /pr-autopilot:step <PR#>` directly).

---

## Test plan (EVAL.md additions — renumber 39–47, P0-3 fix)

| # | Scenario |
|---|---|
| 39 | `assign` on non-existent id → graceful error |
| 40 | `assign` with deps not all merged → reject with explanation |
| 41 | `assign` race: two agents try same id within 100ms → git branch creation fails for loser. Loser's expected output: read claim file via `git show <branch>:.claude/assignment-claims/<id>.json | jq '{agentId, claimedAt, subStatus}'` and echo "claimed by `<agentId>` since `<claimedAt>`, current state `<subStatus>`". (P1-4 fix: git error itself does not carry agent identity; loser must explicitly fetch from claim file.) |
| 42 | `review-spec` with no env keys → 2 Claude subagents + composer-2.5 manual prompt only; aggregation works |
| 43 | `review-spec` with both `OPENAI_API_KEY` and `CURSOR_API_KEY` → 4 auto channels fire in parallel + manual prompt; aggregation works |
| 44 | `approve-spec` without prior `review-spec` reaching `spec_review_complete` → reject |
| 45 | SessionStart hook offline (`git fetch` timeout) → graceful skip in <8s, exit 0 |
| 46 | `finish` on a PR not yet merged → reject with PR state |
| 47 | Abandoned worktree retry: previous session crashed mid-claim; new `/assign` detects existing worktree + claim file, offers continue (no clobber) |

EVAL.md edit will append these after existing scenarios 1–38.

---

## Adoption per project (~10 min one-time)

1. `/plugin update pr-autopilot@claude-pr-autopilot` → v0.5.
2. Copy `templates/assignments.yaml.template` → `<project>/assignments.yaml`. Fill in real assignments.
3. Merge `templates/settings-snippet.json` into `<project>/.claude/settings.json`. Includes:
   - SessionStart hook for `check-origin-main.sh`
   - PreToolUse hook for `enforce-spec-gate.sh`
   - `vaultId` env var binding for ExoVault MCP (P1-6 fix)
4. `/pr-autopilot:allow <owner/repo>` if not already.
5. Optional: set `OPENAI_API_KEY` and/or `CURSOR_API_KEY` env for paid auto reviewers (graceful degradation if absent).
6. New session opens with SessionStart hook output. Ready.

### Settings snippet (`templates/settings-snippet.json`)

```jsonc
{
  // Merge into project's .claude/settings.json
  "env": {
    "EXOVAULT_VAULT_ID": "<your-vault-uuid>"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/cache/claude-pr-autopilot/pr-autopilot/0.5.0}/hooks/check-origin-main.sh",
            "timeout": 8
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/cache/claude-pr-autopilot/pr-autopilot/0.5.0}/hooks/enforce-spec-gate.sh",
            "timeout": 4
          }
        ]
      }
    ]
  }
}
```

---

## Resolved review items

### v1 → v2 (Composer 2.5 v1 review)

| Item | Resolution |
|---|---|
| **P0-1** fake adapter reuse | New §Pre-PR Adapter Layer with explicit interface + invocation paths separate from v0.4 |
| **P0-2** non-atomic claim | Git branch creation as atomic primitive; claim file as runtime truth; ExoVault as mirror |
| **P0-3** EVAL numbering | Renumbered 39–47 |
| **P0-4** ROADMAP collision | v0.5 = pre-PR (this spec); v0.6 = Cursor-native adapter (ROADMAP edit included) |
| **P0-5** dual SoT | (refined in v2.1; see below) |
| **P0-6** approve-spec not enforced | `enforce-spec-gate.sh` PreToolUse hook |
| P1-1 `claim` transient | Removed from state machine diagram |
| P1-2 spec-review exit ambiguous | New state `spec_review_complete` |
| P1-3 missing pr_opened handoff | New skill `pr-autopilot:pr-opened <PR#>` |
| P1-4 worktree retry | `assign` detects existing worktree + claim file, offers continue |
| P1-5 `<slug>` undefined | `slug = assignmentId` verbatim |
| P1-6 ExoVault pre-flight | Added to all skills' pre-flight; `vaultId` in settings snippet |
| P1-7 composer-2 vs composer-2.5 | Standardized on `composer-2.5` |
| P1-8 `--no-verify` | Removed from `finish` default path; user opens follow-up PR if push protected |
| P1-9 hook allowlist policy | Explicit table: SessionStart always-on, PreToolUse honors allowlist + pause |
| P1-10 missing schema file | `assignments.schema.json` shipped with v0.5; YAML schema inline in spec |

### v2 → v2.1 (Composer 2.5 v2 review)

| Item | Resolution |
|---|---|
| **P0-1 v2** naming drift `slices:` vs `assignments:` | YAML schema root key renamed to `assignments:`; step 8 of `/assign` dropped (was the offending `slices[<id>].status` reference); all references audited |
| **P0-2 v2** hook bypass via claim-file edit | `/approve-spec` requires `AskUserQuestion` interactive primitive (cannot be fabricated by agent); claim file now carries `approvedAt` + `approvedBy`; hook BLOCKS coding states with `approvedAt: null` |
| **P0-3 v2** yaml on feature branch ≠ truth on main | Main `assignments.yaml` truth model excludes `in_progress` — only `todo | merged | blocked`. Runtime state lives in claim file (branch-scoped). `/assign` does NOT mutate yaml. `/finish` is the only writer to main yaml |
| **P0-4 v2** `pr-opened` requires `implementing` never set | Dropped `spec_approved` as standalone state. `/approve-spec` flips directly to `implementing`. State machine simplified. Hook treats `implementing`/`pr_*` as gate-lifted set |
| P1-1 v2 bash syntax error in hook | Rewrote `enforce-spec-gate.sh` with proper `case` statement; full bash inlined |
| P1-3 v2 `check-origin-main.sh` not in v2 | Full bash inlined in v2.1 |
| P1-4 v2 Composer manual aggregation | Manual paste is advisory, NOT blocking `spec_review_complete`. Idempotent re-aggregation when user pastes later (dedup by body hash) |
| P1-5 v2 cursor-cloud poll contract | Poll every 5s, 120s timeout; pending entries recorded in claim file; `/review-spec` idempotent for re-folding pending results |
| P1-6 v2 ExoVault duplicate tasks | Idempotent: `list_tasks` search by canonical title before `create_task` |
| P1-7 v2 state machine arrow typo | `spec_revising` re-loops to `spec_review_requested` (not `pr_review_requested`) |
| P1-8 v2 hook honors allowlist + pause | Added pause-sentinel + allowlist checks at top of `enforce-spec-gate.sh` |
| P1-10 v2 `spec-review` naming in non-goals | Updated to `/review-spec` |

---

### v2.1 → v2.2 (Composer 2.5 v2.1 review — APPROVE 9/10)

| Item | Resolution |
|---|---|
| **P1-1 v2.1** metadata stale (`v2 drafted`, G5 `spec_approved`, `spec-review` naming) | Header bumped to v2.2 (APPROVED); G5 rewritten with `implementing`; non-goals + Adapter Layer header use `/review-spec` |
| **P1-2 v2.1** `pr_review_requested` never set | `/pr-opened` now sets `pr_review_requested` directly (PR exists ⇒ review loop starting). Added clarifying note about `pr_opened` being conceptual-only |
| **P1-3 v2.1** `/finish` main yaml workflow ambiguous | Explicit checkout-main + pull-ff-only + edit + commit + push flow. Push-protected fallback documented. Worktree cleanup best-effort. Idempotency clarified |
| **P1-4 v2.1** EVAL 41 expected output | Expected: read claim file via `git show <branch>:.claude/assignment-claims/<id>.json` and surface `agentId`+`claimedAt`+`subStatus` |
| **P1-5 v2.1** hook grep case-sensitive | `grep -qiFx` (case-insensitive, consistent with v0.4 `/allow` + auto-trigger) |
| **P1-6 v2.1** claim file schema incomplete | Schema now includes `approvedAt`, `approvedBy`, `approvalContext`, `prUrl`, `mergedAt`, `mergedInPr` with semantics table |
| **P1-7 v2.1** `/assign` step 2 IN_PROGRESS source unclear | Explicit: `mcp__exo-vault__list_tasks(status='in_progress')` filtered by `assignment:<id>` title + optional `git branch -r` cross-check |
| "slice base" leftover in hook output | Renamed to `assignment base` |
| Other P2 nits (ROADMAP edit, schema preview, G8 wording, `/unassign` yaml no-op) | Tracked for implementation PR (not blocking approve) |

---

## Status

- **v1:** drafted 2026-05-28 16:45 PL. Reviewed by Composer 2.5 → 6 P0, 10 P1.
- **v2:** drafted 2026-05-28 17:30 PL. Addressed all v1 findings. Reviewed by Composer 2.5 → 8/10 CONDITIONAL CLEAR, 4 new P0, 8 P1.
- **v2.1:** drafted 2026-05-28 18:15 PL. Addressed all v2 P0 + key P1. Reviewed by Composer 2.5 → **9/10 APPROVE**, 7 P1 + P2 nits.
- **v2.2 (this):** drafted 2026-05-28 18:45 PL. Addresses all 7 v2.1 P1 + naming/metadata cleanup. **Ready for Marcin `/approve-spec`.**

**Awaiting:** Marcin `/pr-autopilot:approve-spec` (the spec dogfoods its own pattern — user clicks Approve via interactive primitive to validate the workflow).

Once approved → implementation: 6 skills (`assign`, `review-spec`, `approve-spec`, `pr-opened`, `finish`, `unassign`) + 2 hooks (`check-origin-main.sh` + `enforce-spec-gate.sh`) + 4 templates + plugin.json bump 0.4.0 → 0.5.0 + ROADMAP update + EVAL.md additions (scenarios 39–47) → run EVAL on a real Asistel assignment → ship to marketplace.
