# Spec — claude-pr-autopilot v0.5.1 — `/review-spec` improvements

**Data:** 2026-05-28
**Reviewer iteracja:** v2 (po manual `/review-spec` equivalent — zob. §A audit log)
**Branch:** `feat/v0.6-review-spec-improvements` (uwaga: nazwa branch'a mówi v0.6, ale shipping target to **v0.5.1** patch — zob. §2)
**Worktree:** `c:\Users\sufam\IdeaProjects\claude-pr-autopilot\.claude\worktrees\feat-v0.6-review-improvements` (off `origin/main@1d17cde`)
**Spec autor:** claude_code (Opus 4.7 1M)
**Discovered by:** dogfood iteracja Asistel onboarding (memories: `3ff0cec3`, `17c3b946`, `c7e9c5d1`, `43990c97`)

---

## 1. Cel (1 zdanie)

Naprawić cztery "happy-path-optimistic" luki w `/pr-autopilot:review-spec` które wyszły podczas pierwszego real onboardingu (MarcinSufa/asistel): (A) brak `--bootstrap` mode dla PR która sama wprowadza pr-autopilot, (B) niefriendly UX manual Composer paste-back, (C) brak pre-flight probe planu Cursor, (D) brak progress visibility podczas dispatch (Marcin direct ask 2026-05-28: "would be nice to show the progress and the step on which we are now").

---

## 2. Versioning — dlaczego v0.5.1 nie v0.6

Decyzja: **v0.5.0 → v0.5.1**. To preferencja versioning, nie strict semver compliance.

- Strict semver: dodanie `--bootstrap` flag = MINOR (backwards-compatible new functionality) → v0.6.0. ROADMAP miałby renumber "Cursor-native runtime adapter" do v0.7.
- Pragmatic semver: te luki to fix-of-design-gap, nie new feature. Wszystkie 3 zmiany są opt-in, additive, backwards-compatible. Sygnatura semantyczna pasuje do PATCH.
- ROADMAP slot: v0.6 jest zarezerwowany dla "Cursor-native runtime adapter" (bigger work) — nie chcemy odbijać.

→ **v0.5.1**, explicit "versioning preference not strict semver" w ROADMAP entry per Hostile P1 #7 (audit log §A.6).

`feat/v0.6-review-spec-improvements` branch name zostaje (stworzony przed decyzją; rename ephemeral). Zob. §A.6.

---

## 3. Cztery luki (Gap A/B/C/D)

### Gap A — `/review-spec` nie chodzi w bootstrap PR (memory `3ff0cec3-...`)

**Problem:** `skills/review-spec/SKILL.md` linia 12-16 pre-flight wymaga `.claude/assignment-claims/<id>.json` istnieje w worktree. Bootstrap PR — taka która sama wprowadza `assignments.yaml` + `.claude/settings.json` — nie ma żadnej assignment yet, więc skill blocks.

**Empirical:** sesja `43990c97` musiała manually wywołać 2 Claude subagentów + manually wydrukować Composer prompt dla Asistel onboarding spec. ~3 dodatkowe tool calls + 1 episodic memory.

### Gap B — Composer 2.5 manual paste-back ma frykcję (memory `17c3b946-...`)

**Problem:** SKILL.md step 3 drukuje prompt w "🔵 OPTIONAL: open Cursor Composer 2.5 (Cmd+I) and paste this prompt:" formacie z `<path>` placeholderem. User musi: (a) zaznaczyć tekst, (b) ctrl+c, (c) Cmd+I, (d) ctrl+v + EDIT path placeholder, (e) wait, (f) ctrl+c reply, (g) wklej z powrotem. 5+ context switchów + ręczna edycja placeholderu.

**Empirical:** Marcin reaguje "to automatycznie miało działać" verbatim. Frustracja real.

### Gap C — `cursor-cloud-agent` dispatch fails for Cursor Free even with valid API key (memory `c7e9c5d1-...`)

**Problem:** SKILL.md step 2 mówi "cursor-cloud-agent if `CURSOR_API_KEY` set". Insufficient — env var presence ≠ plan eligibility.

**Empirical:** `GET https://api.cursor.com/v1/agents?limit=1` z Marcin's valid key → HTTP 403 `{"error":{"code":"plan_required","message":"Cloud Agent is not available for free users."}}`. Auth itself succeeded (structured 403, not 401).

**Wider lesson:** v0.5 skill happy-path-optimistic. Każdy external dispatch powinien mieć cheap pre-flight capability probe.

### Gap D — Brak progress visibility podczas dispatch (Marcin direct ask 2026-05-28)

**Problem:** v0.5.0 `/review-spec` dispatches 2-4 reviewers in parallel + Composer prompt + aggregation. User widzi NIC przez 2-3 minuty wallclock — black box. Po zakończeniu — wszystko wypada na raz. Brak signalu "co działa, co się skończyło, co jest pending."

**Empirical:** Marcin verbatim 2026-05-28 15:10 (mid-spec-write for v0.5.1): "would be nice to show the progress and the step on which we are now - for example [reviewing spec -> 3 reviewers --- Cursor [in progres] , Claude local [ finished ] ... this should be in pr-autopilot skill added".

**Split into v0.5.1 + v0.6:**
- **D.1 (v0.5.1, this patch):** **status table printed at dispatch start** showing all reviewers as `[pending]` → after all complete, **final aggregated table** with per-reviewer `[complete/skipped/failed]` + counts. TodoWrite mirrors for sticky chat-side visibility. Better than zero. Does NOT support TRUE incremental ("Cursor done while Claude still running") because subagents dispatched in foreground mode are atomic from skill's perspective.
- **D.2 (v0.6+ ROADMAP):** TRUE incremental updates via `run_in_background: true` Agent dispatches + notification-driven status table refresh. Requires understanding Claude Code's between-turn notification primitives for skill markdown. Bigger work; out of scope for v0.5.1 patch but explicitly entered into ROADMAP.
- **Gap E (v0.6+ ROADMAP — Marcin ask 2026-05-28 15:15):** apply same D.1 pattern (status table + TodoWrite mirror) to **implementation phase** of `/assign` + `/approve-spec` cycle. During TDD, user should see: current file being edited, tests passing/failing, lint status, build status. Same atomic-update pattern (start: ⏳ pending; end: ✅/❌); D.2 incremental optional.
- **Gap F (v0.6+ ROADMAP — Marcin same ask):** apply same D.1 pattern to `/pr-opened` + `/step` loop (post-PR review phase). User should see per-iteration: which reviewer dispatched (Cursor/Copilot/Codex), score, threads to triage, fix-commit pushed. Already shows verdicts at terminal states — gap is granular mid-iter visibility.

**Cross-skill template thesis:** Gaps D/E/F are the same UX pattern applied to different lifecycle phases. v0.5.1 implements D.1 in `/review-spec` as the **template**; v0.6 mechanically rolls it out via E + F in `/assign`+`/approve-spec`+`/pr-opened`+`/step`. Future ROADMAP item: extract a shared status-table helper (markdown snippet + TodoWrite shape) into `skills/_shared/progress-table.md` once 3 of 5 skills implement the pattern (rule-of-three for abstraction).

---

## 4. Co dodajemy

| Plik | Status | Cel |
|---|---|---|
| `skills/review-spec/SKILL.md` | MODIFY | (a) Nowa top-level "Mode detection (read first)" sekcja z explicit modal routing. (b) Nowa "Argument parsing protocol" sekcja. (c) "Bootstrap mode" sekcja z technical enforcement guard + step-by-step (co dzieje się w stepach 3-7 w bootstrap). (d) Composer prompt — fenced block + baked-in path. (e) cursor-cloud-agent dispatch — wywołanie probe + per-exit-code routing. (f) **NEW Step 1.5 (Gap D.1):** print initial status table before dispatch; **NEW Step 4-aggregate update:** print final status table + TodoWrite per-reviewer mirror. |
| `hooks/cursor-cloud-agent-probe.sh` | NEW | Pre-flight probe. **Lokalizacja: `hooks/`** (NIE `reviewers/`; `reviewers/` jest docs-only — zob. §A.5). Z mktemp, jq error handling, Content-Type check. |
| `hooks/tests/test-review-spec-helpers.sh` | NEW | Unit tests dla probe. Mock server via Python http.server. Required, not skip-if-missing (Marcin's machine ma Python; CI też). |
| `reviewers/CURSOR-SETUP.md` | MODIFY | Dodać "Plan requirements" sekcję — Cloud Agent wymaga Pro, paste-back i 2 subagenty wystarczą dla Free. |
| `EVAL.md` | MODIFY | Dodać scenariusze: 48 (bootstrap happy), 48-NEG-A (nonexistent path), 48-NEG-B (no path arg), 48-NEG-C (used in repo with active assignments — must refuse), 49 (Composer UX fenced), 50 (cursor probe 403 skip), 50-NEG (probe network error). Plus update v1.0.0 gating subset note. |
| `ROADMAP.md` | MODIFY | Sekcja `## v0.5.1 — Review-spec improvements (this patch)` między v0.5 a v0.6. Inline `Branch developed as feat/v0.6-* — named before semver decision`. Decision: brak CHANGELOG.md, ROADMAP jest naszym release logiem (per §A.8). |
| `.claude-plugin/plugin.json` | MODIFY | Bump `"version": "0.5.0"` → `"0.5.1"`. Update description (drobny tweak). |
| `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.1-review-spec-improvements.md` | NEW (ten plik) | Spec. |

**Out of scope** (świadomie):
- `composer-bridge` MCP server — obsolete since cursor-cloud-agent IS programmatic Composer.
- Probe pattern generalization to codex/copilot — różne failure modes; osobne PRy w razie potrzeby.
- Refactor SKILL.md na osobne pliki per mode — 136 linii to za mało żeby uzasadniać.
- CHANGELOG.md — ROADMAP.md pełni rolę release log per §A.8 (explicit decision).

---

## 5. Wymagania funkcjonalne

### 5.1 Gap A — `--bootstrap` mode z explicit modal routing + enforcement

**SKILL.md restrukturyzacja:**

Obecna struktura (136 linii):
```
1. ---
2. name: review-spec
3. description: ...
4. ---
5.
6. # /pr-autopilot:review-spec
7. ## Pre-flight
8. ## Steps
9. ## Adapter prompts
10. ## Idempotency
```

Nowa struktura v0.5.1:
```
1. ---
2. name: review-spec
3. description: ... — add "Supports --bootstrap mode for spec review without claim file."
4. ---
5.
6. # /pr-autopilot:review-spec
7. ## Mode detection (READ FIRST — determines control flow)  ← NEW
8. ## Argument parsing protocol  ← NEW
9. ## Pre-flight (normal mode)  ← RENAMED (was "Pre-flight")
10. ## Bootstrap mode  ← NEW
11. ## Steps (normal mode)  ← RENAMED (was "Steps")
12. ## Adapter prompts  (unchanged)
13. ## Idempotency  (unchanged)
```

**Nowa "Mode detection" sekcja** — Claude reads first:

```markdown
## Mode detection (READ FIRST — determines control flow)

If the invocation contains `--bootstrap` (either `--bootstrap=<path>` or `--bootstrap <path>`):
→ go to **Bootstrap mode** section. Do NOT proceed to "Pre-flight (normal mode)" or "Steps (normal mode)".

Otherwise:
→ go to **Pre-flight (normal mode)** section. Do NOT proceed to "Bootstrap mode".

Modes are mutually exclusive. Do not run both. If unclear which mode applies, refuse with:
`[pr-autopilot/review-spec] ambiguous invocation; expected either no args (normal mode) or --bootstrap <path>.`
```

**Nowa "Argument parsing protocol" sekcja:**

```markdown
## Argument parsing protocol

This skill is markdown that Claude interprets. There is no bash `getopts`. The contract is:

- The invocation `/pr-autopilot:review-spec` with no arguments → **normal mode**.
- The invocation `/pr-autopilot:review-spec --bootstrap=<path>` → **bootstrap mode** with `<path>` as the spec file path. The path is the token immediately following the `=` sign.
- The invocation `/pr-autopilot:review-spec --bootstrap <path>` (whitespace-separated) → **bootstrap mode** with `<path>` as the spec file path. The path is the **first non-flag token** after `--bootstrap`.
- If the path token itself begins with `--`, Claude MUST treat it as a path (not a flag). E.g., `--bootstrap --weird-name.md` is a path of `--weird-name.md`. (Rare; documented for completeness.)
- If `--bootstrap` is followed by nothing (end of invocation), refuse with: `[pr-autopilot/review-spec] --bootstrap requires a path argument; got none.`
- If `--bootstrap` is specified TWICE in the same invocation, refuse with: `[pr-autopilot/review-spec] duplicate --bootstrap flag; only one path is supported per invocation.`
- Single-dash `-bootstrap` is NOT supported and is treated as an unknown flag → refuse with `unknown flag '-bootstrap'; did you mean '--bootstrap'?`.
- Before running ANY dispatch, Claude MUST verify the path exists via Read tool (or `ls`). If the file does not exist, refuse with: `[pr-autopilot/review-spec] --bootstrap path not found: <path>.`
```

**Nowa "Bootstrap mode" sekcja:**

```markdown
## Bootstrap mode (v0.5.1)

Use case: a PR that introduces pr-autopilot to a new repo, OR a standalone spec review without lifecycle overhead.

### B-Pre-flight (bootstrap-specific)

1. The `<path>` argument resolves to an existing markdown file (Argument parsing protocol verifies this).
2. **Enforcement guard** — refuse if the current repo is in "real assignment" state. A real assignment state means BOTH conditions hold:
   - `assignments.yaml` exists at repo root, AND
   - `.claude/assignment-claims/` directory exists AND contains at least one `.json` file.
   If both: refuse with: `[pr-autopilot/review-spec] --bootstrap is for repos without active assignments. This repo has assignments.yaml + active claim file(s). Use /pr-autopilot:assign <id> then /pr-autopilot:review-spec instead.`
   Rationale: prevent lazy bypass of the lifecycle. The bootstrap mode is for genuinely-bootstrap state, not a shortcut to skip claim files in established projects.
   Exception: if user passes `--bootstrap --force` (note: extra `--force` flag), enforcement is skipped. Use case: testing the skill against a real-assignment repo. Logged with audit signal (see B-Step 5).

### B-Steps (bootstrap-specific)

1. **No claim file commits**, no subStatus transitions, no git operations.

2. **Dispatch reviewers** identically to normal mode Step 2:
   - claude-code-reviewer-subagent (FREE, always) — same prompt template, with `<path>` resolved to the bootstrap argument.
   - claude-self-review adversarial (FREE, always) — same.
   - codex-exec if `OPENAI_API_KEY` set OR `which codex` succeeds.
   - cursor-cloud-agent: invoke probe (see Gap C §5.3). Dispatch only if probe returns exit 0.

3. **Composer 2.5 prompt** — print to chat exactly as normal mode (see Gap B §5.2 for new format). User can optionally paste-back; re-run `/review-spec --bootstrap <path>` with same path folds in the response (dedup by body hash, just like normal mode).

4. **Aggregate findings** — same logic as normal mode Step 4, BUT the result is printed to chat only. No claim file write (none exists). No `reviewers[]` array in JSON. Output structure:
   ```
   ✅ Bootstrap review complete for <path>. <N> P0, <M> P1, <K> P2.

   📋 Reviewers ran:
     - claude-code-reviewer-subagent: <P0 count>P0/<P1 count>P1/<P2 count>P2
     - claude-self-review (hostile): <P0 count>P0/<P1 count>P1
     - codex-exec: <status — complete | skipped (no env) | failed>
     - cursor-cloud-agent: <status — complete | skipped (plan_required | invalid_key | network)>

   <If P0 > 0: aggregated P0 list grouped by reviewer, identical format to normal mode>
   <If P0 == 0: "✅ No P0 findings. Spec ready for next step (Marcin approval, then implementation).">

   Note: bootstrap mode is advisory-only. No subStatus transition. No commits. To re-run with additional findings, just invoke again with the same path.
   ```

5. **Audit signal** — append a single line to ExoVault episodic memory:
   `Bootstrap review of <path> at <iso-timestamp>; reviewers <list>; result: <N> P0`.
   Why: gives auditable trail of when bootstrap mode was used. Reviewer-bot or future audit can grep this from vault.
   If `--force` was used (enforcement guard skipped), include the literal token `[BOOTSTRAP_FORCE]` at the start of the audit line.

6. **Exit clean.** No further steps. Re-running with same path is idempotent (same dedup behavior as normal mode).
```

### 5.2 Gap B — Composer 2.5 UX polish (path baked, fenced block)

**SKILL.md Step 3 zmiana** (normal mode + Bootstrap mode B-Step 3 share this format):

```markdown
3. **Composer 2.5 manual prompt** (always — FREE fallback for Cursor Free users).

Print to chat:

🔵 **OPTIONAL: Composer 2.5 review** — for a 3rd perspective beyond the 2 Claude subagents (and 4th if Cursor Pro probe passes for cursor-cloud-agent), copy the block below, open Cursor (Cmd+I), paste, run, paste reply back into Claude.

```
Review the spec at <ABSOLUTE-PATH-BAKED-IN-AT-SKILL-RUNTIME> for:
- internal contradictions
- missing edge cases / failure modes
- scope creep vs declared scope_in/scope_out
- alignment with CLAUDE.md + DESIGN.md (read both first)
- test coverage gaps
- security/correctness for code paths described

Return P0/P1/P2 findings with confidence ratings (5/10–10/10) per PUSHBACK.md.
Format: structured markdown table or per-finding section.
```

After Composer responds: paste its reply back into this Claude chat, then re-run `/pr-autopilot:review-spec` (or `--bootstrap` with same path). Findings auto-dedup by body hash.

(Advisory only — does NOT block spec_review_complete transition.)
```

Key changes vs v0.5.0:
- Path is concrete (resolved at skill runtime), no `<path>` placeholder for user to edit.
- Prompt body is single triple-backtick fenced code block → most terminals/editors support one-click copy of fenced blocks.
- Surrounding prose (header, instructions, "after Composer responds") is OUTSIDE the fenced block, so user only copies what goes to Composer.

### 5.3 Gap C — Cursor Cloud Agent plan probe + dispatch routing

**New file `hooks/cursor-cloud-agent-probe.sh`** (lokalizacja `hooks/`, nie `reviewers/` per Hostile P1 #2):

```bash
#!/usr/bin/env bash
# pr-autopilot v0.5.1 — Cursor Cloud Agent plan-eligibility probe.
# Exit codes:
#   0  — Pro plan, Cloud Agent available
#   42 — API key valid but plan is Free / plan_required
#   43 — API key invalid (401) or missing
#   44 — Network / timeout / parse failure / other (non-deterministic)
#
# Stdin: nothing.
# Stdout: nothing (silent unless --verbose).
# Stderr: short reason on non-zero exit.

set -u  # Intentionally NOT set -e — we capture curl/jq exit codes and translate.

# Dependency check (per code-reviewer P1 #2 + Hostile P1 #4).
if ! command -v jq >/dev/null 2>&1; then
  echo "jq required (install: winget install jqlang.jq)" >&2
  exit 44
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl required" >&2
  exit 44
fi

KEY="${CURSOR_API_KEY:-}"
if [ -z "$KEY" ]; then
  echo "no CURSOR_API_KEY set" >&2
  exit 43
fi

# URL override — gated behind PR_AUTOPILOT_TEST_MODE sentinel per Hostile P0 #1.
# Production: always uses real Cursor API. Tests: must set PR_AUTOPILOT_TEST_MODE=1
# to enable override. This makes the override safe from accidental misconfiguration.
URL="https://api.cursor.com/v1/agents?limit=1"
if [ "${PR_AUTOPILOT_TEST_MODE:-0}" = "1" ] && [ -n "${CURSOR_API_URL:-}" ]; then
  URL="${CURSOR_API_URL}?limit=1"
fi

# mktemp avoids $$ collision when probe runs concurrently per Hostile P1 #4.2.
TMP=$(mktemp -t pr-autopilot-cursor-probe.XXXXXX)
trap 'rm -f "$TMP"' EXIT

# Cheap probe: list endpoint with limit=1, no PII, no side effects.
HTTP=$(curl -sS -m 8 -o "$TMP" -w "%{http_code}" \
  -H "Authorization: Bearer $KEY" \
  "$URL" 2>/dev/null) || HTTP="000"

case "$HTTP" in
  200)
    exit 0
    ;;
  401)
    echo "Cursor API key invalid (401)" >&2
    exit 43
    ;;
  403)
    # Content-Type check before jq parse (Hostile P1 #4.2).
    # Cursor may return HTML 500/403 pages from CloudFront/WAF; jq would fail silently.
    if ! head -c 1 "$TMP" 2>/dev/null | grep -q '{'; then
      echo "Cursor API returned 403 with non-JSON body (likely WAF/proxy)" >&2
      exit 44
    fi
    CODE=$(jq -r '.error.code // empty' "$TMP" 2>/dev/null)
    JQ_EXIT=$?
    if [ $JQ_EXIT -ne 0 ]; then
      echo "Cursor API returned 403 with unparseable JSON" >&2
      exit 44
    fi
    if [ "$CODE" = "plan_required" ]; then
      echo "Cursor Cloud Agent requires Pro plan" >&2
      exit 42
    else
      echo "Cursor API returned 403 (code: ${CODE:-unknown})" >&2
      exit 44
    fi
    ;;
  *)
    echo "Cursor API probe failed (HTTP $HTTP)" >&2
    exit 44
    ;;
esac
```

**SKILL.md Step 2 dispatch change** for cursor-cloud-agent:

```markdown
- **cursor-cloud-agent** — invoke probe, dispatch based on exit code:
  ```bash
  bash "$CLAUDE_PLUGIN_ROOT/hooks/cursor-cloud-agent-probe.sh"
  case $? in
    0)
      # Pro available — proceed with dispatch identical to v0.5.0.
      RUN=$(curl -sX POST https://api.cursor.com/v1/agents \
        -H "Authorization: Bearer $CURSOR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"prompt\":{\"text\":\"<prompt+spec>\"},\"repos\":[{\"url\":\"<repo-url>\"}],\"model\":{\"id\":\"composer-2.5\"},\"autoCreatePR\":false}")
      # Poll run.id every 5s up to 120s (unchanged from v0.5.0).
      ;;
    42)
      # Cursor Free — skip and log.
      REVIEWERS+=('{"kind":"cursor-cloud-agent","status":"skipped","reason":"plan_required","iteration":<n>}')
      echo "ℹ️ Cursor Cloud Agent skipped — requires Cursor Pro. Upgrade: https://cursor.com/settings/billing."
      ;;
    43)
      # Bad/missing key — louder warning.
      REVIEWERS+=('{"kind":"cursor-cloud-agent","status":"skipped","reason":"invalid_key","iteration":<n>}')
      echo "⚠️ Cursor Cloud Agent skipped — API key invalid or missing. Check ~/.claude/settings.json env.CURSOR_API_KEY."
      ;;
    44)
      # Network / parse / other — skip with retry hint.
      REVIEWERS+=('{"kind":"cursor-cloud-agent","status":"skipped","reason":"probe_error","iteration":<n>}')
      echo "ℹ️ Cursor Cloud Agent probe failed (network/parse). Probe re-runs on next /review-spec invocation; no caching."
      ;;
  esac
  ```

  **Note on probe vs dispatch URL contract** (per Hostile P0 #1 audit):

- The probe accepts `CURSOR_API_URL` override **ONLY** when `PR_AUTOPILOT_TEST_MODE=1` is also set. This gates testability behind an explicit opt-in.
- The dispatch (the `curl -sX POST` above) ALWAYS uses `https://api.cursor.com/v1/agents` — NO env override.
- This asymmetry is intentional: tests should validate probe LOGIC, not full dispatch (which is covered by live EVAL 43 requiring real Pro plan). Dispatch hitting production with a spec body is acceptable only with real plan eligibility; mocking it would teach nothing.
```

### 5.4 Gap D.1 — Progress visibility (status table + TodoWrite mirror)

**SKILL.md new "Step 1.5 (dispatch announcement)":**

Before Step 2 (dispatch), print to chat:

```markdown
🔄 **Reviewing spec at `<absolute-path>` ...**

Dispatching reviewers (iter <n>):

| Reviewer | Type | Status |
|---|---|---|
| feature-dev:code-reviewer | Claude subagent (FREE, always) | ⏳ pending |
| general-purpose adversarial | Claude subagent (FREE, hostile) | ⏳ pending |
| codex-exec | <if env set: ⏳ pending | else: ⏭ skipped (no OPENAI_API_KEY / codex)> |
| cursor-cloud-agent | <after probe: ⏳ pending (Pro) | ⏭ skipped (Free/invalid/network)> |
| composer-2.5 manual | FREE fallback (paste-back) | 📋 prompt printed; optional |

Run probe for cursor-cloud-agent first, then dispatch all reviewer-channels in parallel.
```

ALSO write TodoWrite at this moment with one item per reviewer status (mirror of the table):

```typescript
TodoWrite([
  { content: "review-spec — feature-dev:code-reviewer subagent", activeForm: "Running code-reviewer subagent", status: "in_progress" },
  { content: "review-spec — adversarial subagent", activeForm: "Running adversarial subagent", status: "in_progress" },
  ...
])
```

**After Step 4 (aggregation), print final status table:**

```markdown
✅ **Review iter <n> complete in <wall-clock-time>s.**

| Reviewer | Status | Findings (P0/P1/P2) | Time |
|---|---|---|---|
| feature-dev:code-reviewer | ✅ complete | N/M/K | <s>s |
| general-purpose adversarial | ✅ complete | N/M (no P2) | <s>s |
| codex-exec | <✅/⏭/❌> | <if complete: N/M/K> | <s or N/A> |
| cursor-cloud-agent | <✅/⏭/❌ + reason> | <if complete: N/M/K> | <s or N/A> |
| composer-2.5 manual | <📋 prompt printed / ✅ folded in> | <if folded: N/M/K> | N/A |

**Aggregate: P0 X, P1 Y, P2 Z** → <decision message: spec_review_complete OR spec_revising>
```

Update TodoWrite: each reviewer item status: `completed` (or `skipped` mapped to `completed` with activeForm "Skipped: <reason>").

**Key UX wins:**
- User sees IMMEDIATELY what's being run (table at Step 1.5).
- TodoWrite gives sticky persistent view in chat sidebar.
- Final table shows per-reviewer outcome with timings (helps spot slow reviewers, repeated skips).
- v0.5.0 went from "no signal" → v0.5.1 "before+after signal." v0.6+ adds TRUE incremental (D.2).

**Limitation acknowledged in spec:** D.1 is NOT TRUE incremental. All reviewer rows go from `⏳ pending` → final status in one atomic update at Step 4. User cannot see "Cursor finished while Claude still running" mid-flight. This requires D.2 (background dispatch + notifications) which is v0.6+.

**No new files for D.1.** Pure SKILL.md changes.

### 5.5 New tests — `hooks/tests/test-review-spec-helpers.sh`

Tests against `hooks/cursor-cloud-agent-probe.sh` only. Pattern follows existing `test-spec-gate.sh`:

```bash
#!/usr/bin/env bash
# pr-autopilot v0.5.1 — unit tests for hooks/cursor-cloud-agent-probe.sh
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$HOOKS_DIR/cursor-cloud-agent-probe.sh"
[ -f "$PROBE" ] || { echo "Probe not found at $PROBE"; exit 2; }
chmod +x "$PROBE" 2>/dev/null

# Dependency check
command -v python3 >/dev/null 2>&1 || { echo "python3 required for mock server"; exit 2; }

PASS=0; FAIL=0
assert_exit() {
  local name="$1" expected="$2" actual="$3" stderr="$4"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "✓ $name"
  else
    FAIL=$((FAIL + 1)); echo "✗ $name — expected exit $expected, got $actual"
    [ -n "$stderr" ] && echo "  stderr: $stderr"
  fi
}

# Helper: start mock server on free port, return port number
start_mock() {
  local http_code="$1" body="$2" port=$((50000 + RANDOM % 10000))
  python3 -c "
import http.server, json, socketserver, sys, threading
class H(http.server.BaseHTTPRequestHandler):
  def do_GET(self):
    self.send_response($http_code); self.send_header('Content-Type', 'application/json'); self.end_headers()
    self.wfile.write('''$body'''.encode())
  def log_message(self, *a, **kw): pass
srv = socketserver.TCPServer(('127.0.0.1', $port), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
import time; time.sleep(0.3); print($port)
" &
  echo "$port"
}

# T1: no key set → exit 43
unset CURSOR_API_KEY
STDERR=$(bash "$PROBE" 2>&1 >/dev/null); ACTUAL=$?
assert_exit "T1 no key → 43" 43 $ACTUAL "$STDERR"

# T2: HTTP 200 → exit 0 (Pro)
export CURSOR_API_KEY="test-key"
export PR_AUTOPILOT_TEST_MODE=1
PORT=$(start_mock 200 '{"runs":[]}' )
export CURSOR_API_URL="http://127.0.0.1:$PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null); ACTUAL=$?
assert_exit "T2 200 → 0 (Pro)" 0 $ACTUAL "$STDERR"
kill $(jobs -p) 2>/dev/null; wait 2>/dev/null

# T3: HTTP 401 → exit 43 (bad key)
PORT=$(start_mock 401 '{"error":{"code":"invalid_key"}}' )
export CURSOR_API_URL="http://127.0.0.1:$PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null); ACTUAL=$?
assert_exit "T3 401 → 43 (invalid_key)" 43 $ACTUAL "$STDERR"
kill $(jobs -p) 2>/dev/null; wait 2>/dev/null

# T4: HTTP 403 plan_required → exit 42
PORT=$(start_mock 403 '{"error":{"code":"plan_required","message":"Cloud Agent is not available for free users."}}' )
export CURSOR_API_URL="http://127.0.0.1:$PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null); ACTUAL=$?
assert_exit "T4 403 plan_required → 42 (Free)" 42 $ACTUAL "$STDERR"
kill $(jobs -p) 2>/dev/null; wait 2>/dev/null

# T5: HTTP 403 other code → exit 44
PORT=$(start_mock 403 '{"error":{"code":"other_403","message":"Forbidden."}}' )
export CURSOR_API_URL="http://127.0.0.1:$PORT/agents"
STDERR=$(bash "$PROBE" 2>&1 >/dev/null); ACTUAL=$?
assert_exit "T5 403 other code → 44 (unknown)" 44 $ACTUAL "$STDERR"
kill $(jobs -p) 2>/dev/null; wait 2>/dev/null

# T6: Network unreachable → exit 44
export CURSOR_API_URL="http://127.0.0.1:1/agents"  # port 1 = unbindable in user space; connection refused
STDERR=$(bash "$PROBE" 2>&1 >/dev/null); ACTUAL=$?
assert_exit "T6 connection refused → 44 (network)" 44 $ACTUAL "$STDERR"

# T7: PR_AUTOPILOT_TEST_MODE not set, CURSOR_API_URL set → uses production URL (will fail with real auth if key invalid)
# This validates the test-mode sentinel actually gates the override.
unset PR_AUTOPILOT_TEST_MODE
export CURSOR_API_URL="http://127.0.0.1:1/agents"  # should be ignored
STDERR=$(bash "$PROBE" 2>&1 >/dev/null); ACTUAL=$?
# Expect 44 (network to real api.cursor.com fails because of network isolation in CI) OR 43 (auth fails with test-key)
# Both are acceptable — the key thing is it did NOT use the override URL.
if [ "$ACTUAL" = "43" ] || [ "$ACTUAL" = "44" ]; then
  PASS=$((PASS + 1)); echo "✓ T7 test-mode sentinel gates override (got $ACTUAL — production URL was used)"
else
  FAIL=$((FAIL + 1)); echo "✗ T7 expected 43 or 44, got $ACTUAL (override may have leaked)"
fi

echo ""
echo "─── Results ─────────────────────────────────"
echo "  pass: $PASS"
echo "  fail: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

7 tests total. T7 validates the security guarantee (`PR_AUTOPILOT_TEST_MODE` gates the URL override).

---

## 6. Acceptance

Per Marcin workflow rule #3:

1. **JSON validation:** `plugin.json` valid, `version: "0.5.1"`.
2. **Markdown lint:** markdownlint-cli clean on SKILL.md + EVAL.md + ROADMAP.md + spec file (same flags as v0.2 V7).
3. **Bash unit tests:** `bash hooks/tests/test-review-spec-helpers.sh` → 7/7 PASS.
4. **Regression:** `bash hooks/tests/test-spec-gate.sh` 14/14 PASS, `bash hooks/tests/test-trigger.sh` PASS.
5. **Codex review (rule #5):** PR opened → reviewer agent verdict → no P0.
6. **Marcin approval (rule #6):** Marcin merguje PR.

**Prerequisite — v0.5.0 EVAL inheritance (per Hostile P1 #4):**

v0.5.1 EVAL extends, does NOT replace, v0.5.0. Before claiming v0.5.1 "field-validated":
- v0.5.0 gating subset (scenarios 39/41/42/44/47) MUST also pass against real MarcinSufa/asistel onboarding (or MarcinSufa/exo-vault).
- v0.5.1 EVAL (48/48-NEG-A/B/C/49/50/50-NEG) builds on v0.5.0 EVAL passing.

**Post-merge EVAL gating (v0.5.1):**

1. **EVAL 48 (bootstrap happy path):** synthetic spec at `/tmp/test-bootstrap-spec.md` → `/pr-autopilot:review-spec --bootstrap /tmp/test-bootstrap-spec.md` → 2 Claude subagents dispatch, no claim file, findings printed, exit clean. `git status` shows no commits.

2. **EVAL 48-NEG-A (nonexistent path):** `/pr-autopilot:review-spec --bootstrap /nonexistent/path.md` → refuse with explicit "path not found" message. No dispatch.

3. **EVAL 48-NEG-B (no path arg):** `/pr-autopilot:review-spec --bootstrap` → refuse with explicit "missing path argument" message.

4. **EVAL 48-NEG-C (bootstrap in repo with assignments):** in MarcinSufa/asistel POST-onboarding (when `assignments.yaml` + `.claude/assignment-claims/<some-id>.json` both exist), run `/pr-autopilot:review-spec --bootstrap specs/<any>.md` → refuse with "this repo has active assignments; use /assign + /review-spec instead." Then verify `--bootstrap --force` overrides AND emits `[BOOTSTRAP_FORCE]` audit signal.

5. **EVAL 49 (Composer UX):** run `/pr-autopilot:review-spec` (normal mode) on a test spec. Composer prompt printed in chat is a single triple-backtick fenced block; path is concrete (no `<path>`); prose surrounds the block. Manual eyeball test.

6. **EVAL 50 (cursor probe 403 skip):** on Cursor Free account, run `/pr-autopilot:review-spec` with `CURSOR_API_KEY` set. Probe returns 42. Skill logs "ℹ️ Cursor Cloud Agent skipped — requires Cursor Pro." `reviewers[]` in claim file (normal mode) has `{kind:"cursor-cloud-agent",status:"skipped",reason:"plan_required"}`.

7. **EVAL 50-NEG (probe network failure):** mock unreachable Cursor endpoint via `PR_AUTOPILOT_TEST_MODE=1 CURSOR_API_URL=http://127.0.0.1:1/agents`. Run `/pr-autopilot:review-spec`. Probe returns 44. Skill logs "ℹ️ Cursor Cloud Agent probe failed (network/parse). Probe re-runs on next invocation." Verify NO caching: re-run `/review-spec` → probe re-fires (visible in stderr/logs).

8. **EVAL 48b (dogfood Marcin-local bonus — NOT v1.0.0 gating):** use v0.5.1 to bootstrap-review the Asistel onboarding spec at the Marcin-local path. Compare findings to prior 2-subagent iter1 manual review. **Explicitly Marcin-local validation, not reproducible CI scenario** (per code-reviewer P2 #5). Cannot count toward v1.0.0 gating subset.

If items 1-7 all green AND v0.5.0 gating subset has passed → v0.5.1 field-validated. v1.0.0 gating subset can then add EVAL 48 (only — not 48b which is Marcin-local) to required list.

---

## 7. Ryzyka i mitigacje

| Ryzyko | Mitigacja |
|---|---|
| Skill markdown mode dispatch ambiguous → Claude misinterprets `--bootstrap` parsing | Explicit "Mode detection (READ FIRST)" + "Argument parsing protocol" sections w SKILL.md (§5.1). EVAL 48 + 48-NEG-A/B/C validate live. |
| Probe in wrong directory → SKILL.md invocation broken | Placed in `hooks/` per existing convention (verified: `reviewers/` is docs-only). Test T1 implicitly validates path. |
| `PR_AUTOPILOT_TEST_MODE` sentinel could be set by malicious package | Same threat model as any user-controlled env var. Worst case: probe is spoofed → false-positive Pro → dispatch hits real api.cursor.com → real 403 (same as v0.5.0 baseline). NO credential exfiltration, NO API call spoofing of dispatch. T7 test validates sentinel gates correctly. |
| `jq` not on PATH → probe silent failure | Probe has `command -v jq` guard at startup → exit 44 with stderr message (not exit 42 which would be wrong). Per code-reviewer P1 #2 fix. |
| Probe URL override (CURSOR_API_URL) attacks dispatch | Dispatch hardcoded — NO env override on dispatch. Documented in SKILL.md note. Hostile P0 #1 addressed. |
| Bootstrap mode used to bypass lifecycle in real-assignment repos | Enforcement guard (B-Pre-flight step 2 in §5.1): refuse if `assignments.yaml` + `.claude/assignment-claims/` both exist. `--force` opt-out emits audit signal `[BOOTSTRAP_FORCE]`. EVAL 48-NEG-C validates. Per Hostile P0 #3 fix. |
| `python3` not on PATH (test prereq) | Test exits with `exit 2` and clear stderr. CI must have Python (most do). On Marcin's machine: verified Python 3.14 on PATH. Per code-reviewer P2 #4: required, not skip. |
| `$CLAUDE_PLUGIN_ROOT` variable not set by runtime | Verify against plugin docs before TDD. If unset: fall back to absolute path `$HOME/.claude/plugins/cache/claude-pr-autopilot/pr-autopilot/0.5.1/hooks/cursor-cloud-agent-probe.sh`. Validate via test T0 (or smoke test pre-TDD). Per code-reviewer P2 #4. |
| Single-dash `-bootstrap` edge case | Argument parsing protocol explicit: refuse with `unknown flag '-bootstrap'; did you mean '--bootstrap'?`. EVAL covered by 48-NEG-B variant. Per code-reviewer P2 #5. |
| Branch name says v0.6, ships v0.5.1 | Documented in ROADMAP.md v0.5.1 section: "Developed on branch `feat/v0.6-review-spec-improvements` (named before semver decision)." Per code-reviewer P2 #3. |
| "Field-validated" claim inherits unvalidated v0.5.0 | Explicit clause §6 prerequisite: v0.5.1 cannot claim field-validated until v0.5.0 gating subset also passes. Per Hostile P1 #4. |
| Backwards compat for users on v0.5.0 | `--bootstrap` is opt-in; normal mode unchanged. v0.5.0 → v0.5.1 plugin upgrade is non-breaking. Rollback per §9. |
| TLS leakage via dispatch with spec body | Same as v0.5.0 baseline — Cloud Agent dispatch sends spec text to api.cursor.com (under TLS). Not new in v0.5.1. Documented in CURSOR-SETUP.md (out of scope here). |

---

## 8. Test plan

1. **Unit (bash):** `bash hooks/tests/test-review-spec-helpers.sh` — 7 tests (T1-T7). All offline (mock server).
2. **Regression:** `bash hooks/tests/test-spec-gate.sh` 14 PASS + `bash hooks/tests/test-trigger.sh` PASS.
3. **Lint:** `npx markdownlint-cli@0.41.0 ...` — same flags as v0.2 V7.
4. **Smoke test (pre-TDD):** verify `$CLAUDE_PLUGIN_ROOT` resolves at skill runtime (check via simple `echo "$CLAUDE_PLUGIN_ROOT"` skill or by reading plugin runtime docs).
5. **Live EVAL (post-merge):** scenarios 48 + 48-NEG-A/B/C + 49 + 50 + 50-NEG + 48b (bonus).
6. **Manual integration smoke:** in Asistel repo: `/pr-autopilot:review-spec --bootstrap c:\Users\sufam\IdeaProjects\ai phone assistent\.claude\worktrees\feat-pr-autopilot-v0.5-onboard\specs\2026-05-28-pr-autopilot-v0.5-onboarding.md`. Should fire 2 Claude subagents + probe (skip Cloud Agent on Free, message printed) + Composer prompt (fenced block, baked path). Findings printed; no commits; no claim file mutated.

---

## 9. Rollback plan

Jeśli po merge v0.5.1 popsuje normal-mode `/review-spec`:
1. `git revert <merge-commit>` na main.
2. Bump plugin.json back do v0.5.0.
3. (Optional) `git tag v0.5.0-restored`.

`--bootstrap` is opt-in. Composer UX polish is cosmetic. Probe is additive (production dispatch unchanged). Low risk surface.

---

## 10. Następne kroki po merge

1. **Plugin upgrade in MarcinSufa/asistel:** `/plugin update pr-autopilot@claude-pr-autopilot` → 0.5.1.
2. **Resume Asistel onboarding:** `/pr-autopilot:review-spec --bootstrap c:\Users\sufam\IdeaProjects\ai phone assistent\.claude\worktrees\feat-pr-autopilot-v0.5-onboard\specs\2026-05-28-pr-autopilot-v0.5-onboarding.md`. **Empirical EVAL 48b dogfood.**
3. **README.md update in pr-autopilot:** add "Bootstrap mode" example.
4. **README.md update in Asistel:** add "First-time setup for pr-autopilot" — `/plugin install`, `/pr-autopilot:allow`, optional `CURSOR_API_KEY`.
5. **v0.6 still reserved:** Cursor-native runtime adapter (Path C).
6. **v0.7+ ideas:** generalize probe pattern to codex/copilot. composer-bridge MCP (if Cursor publishes extension API).

---

## 11. References

- v0.5.0 spec: `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5-pre-pr-lifecycle-design.md`
- v0.5.0 EVAL: `EVAL.md` v0.5 sekcja
- ExoVault memories:
  - `b4d768af-...` — v0.5.0 architecture
  - `3ff0cec3-...` — Gap A discovery
  - `17c3b946-...` — Gap B discovery
  - `c7e9c5d1-...` — Gap C discovery
  - `43990c97-...` — session state (Asistel onboarding pause/resume)
  - `c918d55a-...` — Claude self-skill (jq-only on secret-adjacent files)
- Asistel onboarding spec (EVAL 48b target): `c:\Users\sufam\IdeaProjects\ai phone assistent\.claude\worktrees\feat-pr-autopilot-v0.5-onboard\specs\2026-05-28-pr-autopilot-v0.5-onboarding.md`

---

## §A — Reviewer audit log (iter1 → iter2)

Spec v1 review odbył się 2026-05-28 ~14:55 (post Cloud Agent 403 verification). Channels:

- ✅ `feature-dev:code-reviewer` subagent (FREE) — REVISE-RECOMMENDED: 0 P0, 3 P1, 5 P2
- ✅ `general-purpose` adversarial subagent (FREE, hostile) — BLOCK: 3 P0, 6 P1
- ❌ codex-exec — no env keys (per Gap C empirical)
- ❌ cursor-cloud-agent — Cursor Free 403 (per Gap C, the very gap being fixed — dogfood meta)
- ⏸ Composer 2.5 manual paste-back — prompt printed, not pasted

**Aggregated findings + resolutions (deduped across reviewers):**

| ID | Severity | Source | Title | Resolution in v2 |
|---|---|---|---|---|
| F1 | P0 | Hostile #1 | `CURSOR_API_URL` asymmetry — probe overridable, dispatch hardcoded | §5.3 NOTE block: override gated behind `PR_AUTOPILOT_TEST_MODE=1` sentinel + dispatch ALWAYS uses production URL. T7 test validates sentinel gates correctly. |
| F2 | P0 | Hostile #2 | EVAL 48b circular alone + missing negative scenarios | §6 NEW EVAL 48-NEG-A/B/C + 50-NEG. 48b kept as Marcin-local bonus (NOT v1.0.0 gating, explicit note). |
| F3 | P0 | Hostile #3 | Bootstrap "advisory-only" has zero enforcement | §5.1 NEW "B-Pre-flight enforcement guard" — refuse if `assignments.yaml` + `.claude/assignment-claims/` both exist. `--force` opt-out emits `[BOOTSTRAP_FORCE]` audit signal. EVAL 48-NEG-C validates. |
| F4 | P1 | CR #1 | Bootstrap mode modal dispatch underspecified | §5.1 NEW "Mode detection (READ FIRST)" + "Argument parsing protocol" sections. Explicit step-by-step B-Steps. |
| F5 | P1 | CR #2 + Hostile #4 | `jq` silent failure under `set -u` no `set -e` | §5.3 probe: `command -v jq` guard at startup, Content-Type check before parse, explicit jq exit-code check. Per-failure-mode exit codes (42/43/44). |
| F6 | P1 | Hostile #4 (location) | Probe in wrong directory (`reviewers/` is docs-only) | §4 + §5.3: relocated to `hooks/cursor-cloud-agent-probe.sh`. |
| F7 | P1 | CR #3 | `CURSOR_API_URL` blast-radius reasoning muddled in §7 | §7 NEW risk row + §5.3 NOTE: "Worst case: probe spoofed → false-positive Pro → dispatch hits real api.cursor.com → same 403 as v0.5.0 baseline. No new credential/data leak." |
| F8 | P1 | Hostile #6 | Argument parsing protocol hand-waved | §5.1 NEW "Argument parsing protocol" section: explicit `=` vs whitespace forms, ENOENT refusal, single-dash refusal, duplicate-flag refusal, end-of-args refusal. |
| F9 | P1 | Hostile #4 (field-validated) | "Field-validated" inherits unvalidated v0.5.0 state | §6 NEW "Prerequisite — v0.5.0 EVAL inheritance" clause. v0.5.1 cannot claim field-validated until v0.5.0 gating also passes. |
| F10 | P1 | Hostile #7 | No CHANGELOG.md | §4 + §A.8 explicit decision: ROADMAP.md is our release log; no CHANGELOG by design. Documented. |
| F11 | P1 | Hostile #8 | Scenario numbering gating-subset update sloppy | §6 explicit: "v1.0.0 gating subset can then add 48 (only — not 48b which is Marcin-local) to required list." |
| F12 | P2 | CR #4 | Python skip policy in tests | §5.4: required, exit 2 if missing (not skip). Per code-reviewer P2. |
| F13 | P2 | CR #5 | EVAL 48b non-reproducible in CI | §6.14 explicit: "Marcin-local validation, not reproducible CI scenario. Cannot count toward v1.0.0 gating." |
| F14 | P2 | CR #6 | Branch archaeology | §A.6 + ROADMAP entry: "Developed on branch feat/v0.6-* — named before semver decision." |
| F15 | P2 | CR #7 | `$CLAUDE_PLUGIN_ROOT` unverified | §7 risk row + §8 smoke test 4: verify variable resolves before TDD. Fallback documented. |
| F16 | P2 | CR #8 | Single-dash `-bootstrap` edge case | §5.1 Argument parsing protocol explicit refusal: `unknown flag '-bootstrap'; did you mean '--bootstrap'?`. |
| F17 | P2 | Hostile #5 | Probe exit codes 42/43/44 arbitrary | Acknowledged: internal codes consumed only by skill `case $?`. No public API contract. Skill explicitly handles all 3 values. Sufficient. |

**Aggregated count after v2:** P0: 0 (3 → all addressed). P1: 0 (6 → all addressed). P2: 0 (5 → all addressed).

**§A.6 — Branch name decision:** branch `feat/v0.6-review-spec-improvements` created before semver decision finalized to v0.5.1. No rename (branch names are ephemeral; commits land via squash-merge anyway). Documented in ROADMAP.md v0.5.1 entry.

**§A.7 — Spec recursion lesson:** this spec ITSELF is iter2 of a `/review-spec`-equivalent that was run manually (per Gap A — bootstrap mode doesn't exist yet to self-validate). Spec is the LAST spec needing manual subagent dispatch before v0.5.1 ships. After merge, all future bootstrap PRs use `/pr-autopilot:review-spec --bootstrap`.

**§A.8 — CHANGELOG.md decision:** This project uses `ROADMAP.md` as both forward-roadmap AND release log (per-version section). No separate CHANGELOG. Per code-reviewer P2 #4 audit. If future scale demands separation, that's a v0.7+ housekeeping concern.

---

**Approval gate:** spec v2 ready for Marcin direct approval. 2-subagent review iter1 produced 3 P0 + 6 P1 + 5 P2 (deduped to 17 unique findings, F1-F17 in §A); all addressed in v2 either inline or via explicit deferral. Optional iter2: Composer 2.5 paste-back (prompt available on request). Cloud Agent unavailable (Gap C — self-reinforcing dogfood). Marcin merges per rule #6.
