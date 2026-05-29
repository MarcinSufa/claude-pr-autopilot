---
name: review-spec
description: Dispatch the pre-PR adapter layer against a spec markdown file. Supports two modes — normal (claim-file-driven, lifecycle-integrated) and --bootstrap (standalone, advisory-only, no claim file required). Always runs 2 free Claude subagents (code-reviewer + adversarial); runs Codex CLI + Cursor Cloud Agent if env keys + plan eligibility checks pass; prints copy-paste fenced prompt for optional Composer 2.5 manual paste-back. Prints a progress status table at dispatch and a final aggregated table at completion. Aggregates findings → claim file `review_history` (normal mode) or stdout summary (bootstrap mode). Use when - "review my spec", "check the spec before approving", "run findings on the design doc", "review this draft", "/review-spec --bootstrap <path>".
---

# /pr-autopilot:review-spec

Pre-PR adapter dispatch on a markdown spec file. Idempotent and re-runnable.

Full algorithm + adapter inventory + cursor-cloud poll contract: `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5-pre-pr-lifecycle-design.md` (v2.2 §Pre-PR Adapter Layer + §`/review-spec`).
v0.5.1 changes (this version): `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.1-review-spec-improvements.md`.

## Mode detection (READ FIRST — determines control flow)

If the invocation contains `--bootstrap` (either `--bootstrap=<path>` or `--bootstrap <path>`):

→ go to **Bootstrap mode** section. Do NOT proceed to "Pre-flight (normal mode)" or "Steps (normal mode)".

Otherwise (no `--bootstrap` argument):

→ go to **Pre-flight (normal mode)** section. Do NOT proceed to "Bootstrap mode".

Modes are mutually exclusive. Do not run both. If unclear which mode applies, refuse with:
`[pr-autopilot/review-spec] ambiguous invocation; expected either no args (normal mode) or --bootstrap <path>.`

## Argument parsing protocol

This skill is markdown that Claude interprets. There is no bash `getopts`. The contract for argument parsing:

- The invocation `/pr-autopilot:review-spec` with no arguments → **normal mode**.
- The invocation `/pr-autopilot:review-spec --bootstrap=<path>` → **bootstrap mode** with `<path>` as the spec file path. The path is the token immediately following the `=` sign.
- The invocation `/pr-autopilot:review-spec --bootstrap <path>` (whitespace-separated) → **bootstrap mode** with `<path>` as the spec file path. The path is the **first non-flag token** after `--bootstrap`.
- If the path token itself begins with `--`, Claude MUST treat it as a path (not a flag). E.g., `--bootstrap --weird-name.md` is a path of `--weird-name.md`. (Rare; documented for completeness.)
- If `--bootstrap` is followed by nothing (end of invocation), refuse with: `[pr-autopilot/review-spec] --bootstrap requires a path argument; got none.`
- If `--bootstrap` is specified TWICE in the same invocation, refuse with: `[pr-autopilot/review-spec] duplicate --bootstrap flag; only one path is supported per invocation.`
- Single-dash `-bootstrap` is NOT supported → refuse with `[pr-autopilot/review-spec] unknown flag '-bootstrap'; did you mean '--bootstrap'?`.
- An additional flag `--force` may appear AFTER the path in bootstrap mode (e.g., `--bootstrap path.md --force`). It disables the enforcement guard. See Bootstrap mode B-Pre-flight step 2.
- Before running ANY dispatch, Claude MUST verify the path exists via Read tool. If the file does not exist, refuse with: `[pr-autopilot/review-spec] --bootstrap path not found: <path>.`

## Pre-flight (normal mode)

Required preconditions for normal mode:

- Inside a worktree with `.claude/assignment-claims/<id>.json` present.
- `subStatus` is `spec_drafting`, `spec_revising`, or `spec_review_complete` (re-run after manual paste).
- Spec file exists at `claimFile.specFile` or auto-detect newest `specs/*-<id>.md`.

If preconditions fail, refuse with the corresponding error. Do NOT silently fall through to bootstrap mode.

## Bootstrap mode (v0.5.1)

Use cases:
- A PR that introduces pr-autopilot to a new repo (bootstrap PR has no assignment yet).
- Reviewing a draft spec before deciding whether to formally assign it.
- Standalone spec review without lifecycle overhead.

### B-Pre-flight (bootstrap-specific)

1. The `<path>` argument resolves to an existing markdown file (verified via Argument parsing protocol).

2. **Enforcement guard.** Refuse if the current repo is in "real assignment" state. A real assignment state means BOTH conditions hold:
   - `assignments.yaml` exists at repo root, AND
   - `.claude/assignment-claims/` directory exists AND contains at least one `.json` file.

   If both: refuse with:
   ```
   [pr-autopilot/review-spec] --bootstrap is for repos without active assignments.
   This repo has assignments.yaml AND active claim file(s).
   Use /pr-autopilot:assign <id> then /pr-autopilot:review-spec instead.
   (Override: append --force to this invocation if you really mean to bypass.)
   ```

   Rationale: prevent lazy bypass of the lifecycle. Bootstrap mode is for genuinely-bootstrap state, not a shortcut to skip claim files in established projects.

   **Exception:** if `--force` is appended to the invocation, enforcement is skipped. Use case: testing the skill against a real-assignment repo. Always logged with audit signal `[BOOTSTRAP_FORCE]` (see B-Step 5).

### B-Steps (bootstrap-specific)

1. **No claim file commits.** No subStatus transitions. No git operations on the claim file. The bootstrap mode is read-only with respect to git.

2. **Step 1.5 — print initial status table.** See `Step 1.5` in normal mode "Steps (normal mode)". Same format. Skip the "iter <n>" annotation (bootstrap has no iter tracking).

3. **Dispatch reviewers** identically to normal mode Step 2 (see below). Use the bootstrap `<path>` as the `<path>` placeholder in adapter prompts.

4. **Composer 2.5 prompt** — print to chat per "Step 3" in normal mode. Same format. Path is the bootstrap argument.

5. **Aggregate findings.** Same logic as normal mode Step 4 (v0.5.2 — 6-column table + Score derivation + outlier footer apply identically). BUT the result is printed to chat ONLY — no claim file write (none exists), no `reviewers[]` JSON array persisted. Output structure (same Step 4 final-table format from normal mode):

   ```markdown
   ✅ Bootstrap review complete for <path> in <wall-clock-time>s.

   | Reviewer | Model | Score | Time | Findings (P0/P1/P2) | Verdict |
   |---|---|---|---|---|---|
   | feature-dev:code-reviewer | claude-opus-4-7 (feature-dev) | 4/5 | 102s | 0/3/5 | Solid spec; minor polish |
   | general-purpose adversarial | claude-opus-4-7 (general) | 3/5 | 84s | 3/6/0 | Three blockers |
   | codex-exec | — | ⏭ skipped | — | — | OPENAI_API_KEY not set |
   | cursor-cloud-agent | composer-2.5 | <✅ N/5 OR ⏭ skipped (reason)> | <time> | <findings> | <verdict> |
   | composer-2.5 manual | — | 📋 prompt printed | — | — | Optional paste-back |

   Aggregate: P0 X, P1 Y, P2 Z, avg <A>/5 over <M> scored channels.
   ```

   Outlier footer (if any single reviewer Score ≤ 2) — same format as normal mode.

   If `P0 > 0`: also print aggregated P0 list grouped by reviewer (same format as normal mode).
   If `P0 == 0`: print `✅ No P0 findings. Spec ready for next step (Marcin approval, then implementation).`

6. **Audit signal.** Write a memory to ExoVault via `mcp__exo-vault__write_memory` (memoryType: `episodic`). The memory body MUST be generated by the helper script (NOT constructed in prose by Claude) to guarantee the `[BOOTSTRAP_FORCE]` token is byte-exact + grep-able for future audits:

   ```bash
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/cache/claude-pr-autopilot/pr-autopilot/0.5.2}"

   # Without --force:
   AUDIT_BODY=$(bash "$PLUGIN_ROOT/hooks/bootstrap-force-audit.sh" "<spec-abs-path>")

   # With --force (B-Pre-flight enforcement guard skipped):
   AUDIT_BODY=$(bash "$PLUGIN_ROOT/hooks/bootstrap-force-audit.sh" "<spec-abs-path>" force)
   ```

   Then append the reviewer summary + counts to that base body before writing:
   ```
   <AUDIT_BODY>
   Reviewers: <list>. Result: <N>P0/<M>P1/<K>P2.
   ```

   Why a script and not prose: per review iter2 finding, prose-only enforcement risks token drift (`[bootstrap-force]` vs `[BOOTSTRAP_FORCE]`, etc.) or skip-under-context-pressure. The script hardcodes the exact token and ISO8601 timestamp format.

7. **Exit clean.** No further steps. Re-running with same path is idempotent — same dedup behavior as normal mode (Composer manual paste-back parsed from conversation context, body-hash dedup).

## Steps (normal mode)

### Step 1 — read claim file + start

Read `.claude/assignment-claims/<id>.json`. Update `subStatus: spec_review_requested`. Increment `reviewIteration` if existing, else set to 1. Commit:
```bash
git add .claude/assignment-claims/<id>.json
git commit -m "chore(pr-autopilot): review-spec start for <id> (iter <n>)"
```

### Step 1.5 — print initial status table (v0.5.1, Gap D.1)

Before any dispatch, print to chat:

```markdown
🔄 **Reviewing spec at `<absolute-path>` (iter <n>)** ...

Dispatching reviewers:

| Reviewer | Type | Status |
|---|---|---|
| feature-dev:code-reviewer | Claude subagent (FREE, always) | ⏳ pending |
| general-purpose adversarial | Claude subagent (FREE, hostile) | ⏳ pending |
| codex-exec | <if env+CLI set: ⏳ pending; else: ⏭ skipped (no OPENAI_API_KEY / codex)> |
| cursor-cloud-agent | <after probe: ⏳ pending (Pro) OR ⏭ skipped (Free/invalid/network)> |
| composer-2.5 manual | FREE paste-back | 📋 prompt will print below |
```

Then write TodoWrite with a **single sentinel item** for the whole dispatch (NOT one per reviewer). This respects TodoWrite's hard constraint "Exactly ONE task must be in_progress at any time":

```typescript
TodoWrite([
  { content: "/review-spec dispatch (iter <n>) — N reviewers in parallel",
    activeForm: "Running N reviewers in parallel (iter <n>)",
    status: "in_progress" }
])
```

Where N is the count of channels actually dispatching (e.g., 2 for free-only, 3 with codex, 4 with cursor-cloud-agent on Pro). Per-channel status is shown in the chat status table above; TodoWrite is only the sticky sentinel.

In Step 4, this item flips to `completed` with `activeForm: "Done: N reviewers, X P0 / Y P1 / Z P2"`.

v0.5.1 limitation: status table updates atomically at Step 4 (since subagent dispatch via Agent tool is foreground/blocking — once a single Agent-call message dispatches multiple subagents in parallel, all complete before control returns). TRUE incremental per-reviewer status updates are v0.6+ (Gap D.2 — see ROADMAP for hooks-based vs MCP-server-based architecture choice). The chat status table above provides the visual map; the single TodoWrite sentinel provides sticky persistence.

### Step 2 — dispatch sync adapters in parallel

**Graphify dispatch-time filesystem check (v0.5.3+):** before dispatching adapters, check whether this repo has a graphify code knowledge graph at `graphify-out/graph.json`. /review-spec has NO per-PR state file (bootstrap mode has no PR; normal mode hasn't loaded claim state at this point), so the check is purely filesystem-based:

```bash
# PR #9 review P1 fix: also gate on `advisory != "off"` so the hint is NEVER injected
# when the user opted out at the config level, even if a graph happens to exist on disk.
# Matches the /step §0.6a contract: advisory=off means "skip entirely" everywhere.
if [ "${config_graphify_advisory:-auto}" != "off" ] \
  && [ -f "graphify-out/graph.json" ] \
  && [ "${config_graphify_promptHint:-true}" = "true" ]; then
  _graphifyHintEnabled="true"
else
  _graphifyHintEnabled="false"
fi
```

When `_graphifyHintEnabled == "true"`, the **claude-code-reviewer-subagent** and **claude-self-review** prompts (see "Adapter prompts" below) get a graphify hint prepended that tells the subagent to query the graph before grep'ing files.

For cursor-cloud-agent, run the **probe FIRST** to determine plan eligibility:
```bash
# Fallback CLAUDE_PLUGIN_ROOT for manual-copy contexts (per Composer review iter3 P2-2):
# matches the pattern documented in templates/settings-snippet.json
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/cache/claude-pr-autopilot/pr-autopilot/0.5.2}/hooks/cursor-cloud-agent-probe.sh"
PROBE_EXIT=$?
```

Based on `PROBE_EXIT`:
- **0** → Cursor Pro available. Will dispatch cursor-cloud-agent below.
- **42** → Cursor Free (plan_required). Skip cursor-cloud-agent. Append to `reviewers[]`: `{kind:"cursor-cloud-agent", status:"skipped", reason:"plan_required", iteration:<n>}`. Echo: `ℹ️ Cursor Cloud Agent skipped — requires Cursor Pro. Upgrade: https://cursor.com/settings/billing.`
- **43** → API key invalid or missing. Skip with louder warning. Append `reason:"invalid_key"`. Echo: `⚠️ Cursor Cloud Agent skipped — API key invalid or missing. Check ~/.claude/settings.json env.CURSOR_API_KEY.`
- **44** → Network / parse / other error. Skip with retry hint. Append `reason:"probe_error"`. Echo: `ℹ️ Cursor Cloud Agent probe failed (network/parse). Probe re-runs on next /review-spec invocation; no caching.`
- **45** (v0.5.2) → Cursor account setting blocks Cloud Agent (Privacy Mode Legacy currently). Append `reason:"privacy_mode_legacy"`. Echo: `⚠️ Cursor Cloud Agent skipped — Privacy Mode (Legacy) blocks Cloud Agent. Disable in Cursor Settings → Privacy.`

`skipReason` union (v0.5.2 extension): `plan_required | invalid_key | probe_error | no_env | privacy_mode_legacy`.

Now dispatch all enabled adapters in parallel via a single Agent-tool-call message containing multiple invocations:

**Always (FREE):**
- **claude-code-reviewer-subagent**: `Agent({ subagent_type: 'feature-dev:code-reviewer', description: 'Pre-PR spec review', prompt: <see "Adapter prompts" below, with <path> = claimFile.specFile or bootstrap argument> })`
- **claude-self-review** (hostile, FREE): `Agent({ subagent_type: 'general-purpose', description: 'Adversarial spec review', prompt: <hostile template, same path substitution> })`

**Opt-in PAID (if env set):**
- **codex-exec** if `OPENAI_API_KEY` set OR `which codex` succeeds:
  ```bash
  codex exec --json --sandbox read-only --ask-for-approval never \
    --output-last-message "/tmp/codex-review-<id>-iter<n>.md" \
    "$(cat <prompt-template-with-spec-path>)"
  ```
- **cursor-cloud-agent** (ONLY if probe returned 0):
  ```bash
  RUN=$(curl -sX POST https://api.cursor.com/v1/agents \
    -H "Authorization: Bearer $CURSOR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"prompt\":{\"text\":\"<prompt+spec>\"},\"repos\":[{\"url\":\"<repo-url>\"}],\"model\":{\"id\":\"composer-2.5\"},\"autoCreatePR\":false}")
  # Poll run.id every 5s up to 120s
  ```
  If timeout → record `{kind: "cursor-cloud-agent", status: "pending", runId: "<id>", timeoutAt: "<iso>"}` in `reviewers[]`. Re-run `/review-spec` folds in pending result idempotently.

**Note on URL contract:** the dispatch always uses production `https://api.cursor.com/v1/agents`. There is NO env-var override on dispatch. The probe accepts `CURSOR_API_URL` override ONLY when `PR_AUTOPILOT_TEST_MODE=1` is also set (test-mode-only path). This asymmetry is intentional: tests validate probe LOGIC; dispatch is exercised by EVAL 43 ("all keys set" — requires Cursor Pro available) and EVAL 50 (Free graceful skip) as live integration tests, not by mocked unit tests.

### Step 3 — Composer 2.5 manual prompt (always — FREE fallback)

Print to chat:

```markdown
🔵 **OPTIONAL: Composer 2.5 review** — for a 3rd perspective beyond the 2 Claude subagents, copy the block below, open Cursor (Cmd+I), paste, run, paste reply back into Claude.
```

Then immediately print a single triple-backtick fenced code block. The block content must have the spec path **baked in at skill runtime** (no `<path>` placeholder for user to edit):

````
```
Review the spec at <ABSOLUTE-PATH-RESOLVED-AT-SKILL-RUNTIME> for:
- internal contradictions
- missing edge cases / failure modes
- scope creep vs declared scope_in/scope_out
- alignment with CLAUDE.md + DESIGN.md (read both first)
- test coverage gaps
- security/correctness for code paths described

Return P0/P1/P2 findings with confidence ratings (5/10-10/10) per PUSHBACK.md.
Format: structured markdown table or per-finding section.
```
````

After Composer responds: user pastes its reply back into this Claude chat, then re-runs `/pr-autopilot:review-spec` (or `--bootstrap` with same path). Findings auto-dedup by body hash.

(Advisory only — does NOT block `spec_review_complete` transition.)

### Step 4 — aggregate findings + print final status table

Aggregate findings from all sync adapters that completed. Increment `reviewIteration` if not already done in Step 1. Append entries to `reviewers[]` in claim file:
```json
{
  "kind": "claude-code-reviewer-subagent" | "claude-self-review" | "codex-exec" | "cursor-cloud-agent" | "composer-2.5-manual",
  "status": "complete" | "pending" | "timeout" | "skipped",
  "iteration": <n>,
  "findings": { "p0": N, "p1": M, "p2": K, "details": "..." },
  "completedAt": "<iso>",
  "skipReason": "plan_required" | "invalid_key" | "probe_error" | "no_env" | "privacy_mode_legacy"  // only if status: skipped
}
```

**Score derivation (v0.5.2 — DERIVED only, no adapter prompt changes):**

For each reviewer with `status: "complete"`, derive a 1-5 score from P0/P1/P2 counts using this rubric:

| Conditions | Score |
|---|---|
| 0 P0 + 0 P1 + ≤4 P2 | **5/5** (ship-ready) |
| 0 P0 + 0 P1 + ≥5 P2 | 4/5 (lots of nits) |
| 0 P0 + 1-2 P1 | 4/5 (minor polish) |
| 0 P0 + ≥3 P1 | 3/5 (revise — lots of P1) |
| 1 P0 | 3/5 (1 blocker) |
| 2 P0 | 2/5 (significant issues) |
| ≥3 P0 | 1/5 (block — fundamental) |

Skipped, pending, timeout, manual reviewers (`—` rows) → no Score; **excluded from aggregate mean**.

**Model column sourcing** (per kind):

| Reviewer kind | Source | Default |
|---|---|---|
| `claude-code-reviewer-subagent` | hardcoded by `subagent_type` | `claude-opus-4-7 (feature-dev)` |
| `claude-self-review` | hardcoded by `subagent_type` | `claude-opus-4-7 (general)` |
| `codex-exec` | parse JSON `.usage.model` or `.model` | `codex (model unknown)` |
| `cursor-cloud-agent` | parse API `.run.model.id` or `.agent.model.id` | `composer-2.5` (we requested it) |
| `composer-2.5-manual` | N/A | `—` |

**Verdict extraction:** first sentence of the reviewer's response. If extraction fails or reviewer omitted a summary, synthesize: `0 P0` → `Spec ready, N P1, K P2.`; `1 P0` → `One blocker — revise.`; `≥2 P0` → `N blockers — significant revision needed.`. Truncate to ≤60 chars (append `…` if cut).

**Print final status table to chat (v0.5.2 — 6 columns):**

```markdown
✅ **Review iter <n> complete in <wall-clock-time>s.**

| Reviewer | Model | Score | Time | Findings (P0/P1/P2) | Verdict |
|---|---|---|---|---|---|
| feature-dev:code-reviewer | claude-opus-4-7 (feature-dev) | 4/5 | 102s | 0/3/5 | Solid spec; minor polish on §5.3 |
| general-purpose adversarial | claude-opus-4-7 (general) | 3/5 | 84s | 3/6/0 | Three blockers; revise before TDD |
| cursor-cloud-agent | composer-2.5 | 5/5 | 67s | 0/0/2 | Looks ready to ship |
| codex-exec | — | ⏭ skipped | — | — | OPENAI_API_KEY not set |
| composer-2.5 manual | — | 📋 pending | — | — | Optional paste-back |

**Aggregate: P0 X, P1 Y, P2 Z, avg <A>/5 over <M> scored channels** → <decision: spec_review_complete OR spec_revising>
```

**Status column absorbed into Score column** (v0.5.2): instead of a separate Status column, the Score cell renders `⏭ skipped (reason)`, `📋 pending`, `❌ failed`, `⏱ timeout` for non-numeric states. Only completed reviewers get a numeric `N/5`.

**Outlier footer (v0.5.2):** if ANY single reviewer's derived Score is ≤ 2, append BELOW the aggregate line:

```markdown
⚠️ Low score outlier: <reviewer-kind> <N/5> (<P0>P0). Aggregate avg hides blocker.
```

This surfaces the blocker that the mean would otherwise mask (e.g., 4 reviewers at 5/5/5/1 → mean 4.0/5 looks safe but the 1/5 is a real blocker).

**Bootstrap mode parity (v0.5.2):** identical 6-column table + outlier footer + Score derivation apply in bootstrap mode (B-Step 5). No claim-file write in bootstrap — table printed to chat only.

**Update the single TodoWrite sentinel item** added in Step 1.5 to `completed`:
```typescript
TodoWrite([
  { content: "/review-spec dispatch (iter <n>) — N reviewers in parallel",
    activeForm: "Done: N reviewers, X P0 / Y P1 / Z P2 (in <wallclock>s)",
    status: "completed" }
])
```

The per-reviewer outcomes (skipped, failed, completed counts) are visible in the chat status table above. Skipped channels are reflected in the aggregate P0/P1/P2 counts (counted as 0 findings) and the `reviewers[]` JSON array on the claim file. The TodoWrite sentinel is intentionally summary-level — Claude's chat sidebar shows it as one completed item with the aggregate counts in its label.

### Step 5 — Composer manual paste handling

If conversation context contains a pasted Composer reply since the last `/review-spec` invocation, parse it, dedup by body hash (do not duplicate entries), append as `{kind: "composer-2.5-manual", status: "complete", iteration: <n>, ...}`. Advisory only — re-aggregation may flip state if new P0 surfaces.

### Step 6 — decision based on aggregated P0 count

- **0 P0** → `subStatus: spec_review_complete`. Echo (after the final status table from Step 4):
  ```
  📋 Spec ready for next step.

  Marcin: when ready, run /pr-autopilot:approve-spec.
  (Optional: paste Composer 2.5 findings + re-run /review-spec for additional perspective.)
  ```

- **≥1 P0** → `subStatus: spec_revising`. Echo aggregated P0 list grouped by reviewer (after the final status table):
  ```
  ⚠️ Spec revision needed. <N> P0 findings:

  [P0 from <reviewer-kind>, confidence 8/10] <title> — <body>
  ...

  Agent: address findings, re-run /pr-autopilot:review-spec.
  ```

### Step 7 — commit claim file update

```bash
git add .claude/assignment-claims/<id>.json
git commit -m "chore(pr-autopilot): review-spec iter <n> for <id> — <N> P0, <M> P1"
```

## Adapter prompts (PUSHBACK.md rubric)

**Graphify hint prefix (v0.5.3+):** when `_graphifyHintEnabled == "true"` (set in Step 2), prepend the following block to BOTH `claude-code-reviewer-subagent` and `claude-self-review` prompts:

```
**Code knowledge graph available:** This repo has a graphify-built knowledge graph at
`graphify-out/graph.json`. BEFORE grep'ing for symbols or reading source files, query
the graph: `graphify explain "<symbol>"` returns the node + connections + community
in ~1-3k tokens vs ~30-100k for a multi-file grep. Use `graphify path "A" "B"` for
dependency-trace. If `graphify` errors with "command not found" (CLI not installed
locally), fall back to grep + Read without retrying.

```

When `_graphifyHintEnabled == "false"`, the hint block is omitted entirely (no instruction injection).

**claude-code-reviewer-subagent prompt template:**
```
Review the spec at <path> for engineering rigor:
- internal contradictions
- missing edge cases / failure modes
- scope creep vs scope_in/scope_out
- alignment with CLAUDE.md + DESIGN.md (read both first)
- test coverage gaps
- security/correctness for any code paths described

Return P0/P1/P2 findings with confidence ratings (5/10-10/10) per PUSHBACK.md rubric.
Format: structured markdown table or per-finding section.
```

**claude-self-review (hostile) prompt template:**
```
You are a HOSTILE reviewer reading the spec at <path>. Find WEAKNESSES:
- what is underspecified / hand-wavy
- what assumptions might be wrong
- what edge cases / error paths / race conditions are missed
- what scope creep is hidden in scope_in
- what tests would actually catch the failures the author hand-waved

Be ruthless. Do NOT be polite. Tighten the spec by finding weaknesses,
not by validating the author's choices.

Return P0/P1 ONLY (no P2 noise) with confidence ratings.
```

## Idempotency

- **Normal mode:** re-running `/review-spec` after `spec_review_complete` is safe — it re-dispatches reviewers and may flip back to `spec_revising` if new P0 appear.
- **Bootstrap mode:** re-running with same path is safe — prints fresh status tables + aggregated findings to chat. No state persistence between runs (no claim file).
- Pending Cursor Cloud Agent runs get re-polled on re-run.
- Manual Composer paste dedup'd by body hash across iterations.
- TodoWrite items from a previous run are overwritten by Step 1.5's fresh TodoWrite call (idempotent re-render).
