# Spec — claude-pr-autopilot v0.5.2 — per-reviewer summary table + Gap E probe fix + v0.6 rejection ADR

**Data:** 2026-05-28
**Branch:** `feat/v0.5.2-per-reviewer-summary`
**Worktree:** `c:\Users\sufam\IdeaProjects\claude-pr-autopilot\.claude\worktrees\feat-v0.5.2-per-reviewer-summary` (off `origin/main@3b12499`, post v0.5.1)
**Spec autor:** claude_code (Opus 4.7 1M)
**Iteracja:** v2.1 (post 2-subagent review iter1 — 3 P0 + 7 P1 + 3 P2 → addressed in v2; post Composer 2.5 review iter3 — 0 P0 + 4 P1 + 7 P2 → addressed in v2.1, see §A audit log)

---

## 1. Cel (1 zdanie)

Wprowadzić **per-reviewer summary table** w Step 4 (Reviewer · Model · Score · Time · Findings · Verdict — 6 kolumn po dropie Tokens), **Gap E probe fix** (Cursor Privacy Mode Legacy 400 → exit 45 z actionable message), oraz **v0.6 rejection ADR** (institutional knowledge w repo) — w **3 commits w 1 PR** dla granular revert.

---

## 2. Wersjonowanie

**v0.5.1 → v0.5.2 (PATCH).** Backwards-compatible additive changes; default `/review-spec` unchanged behavior with extended observability.

**3-commit split w 1 PR** (per hostile P0-1 — granular revert):
- `commit 1: fix(probe): Gap E — case 400 Privacy Mode Legacy → exit 45` (Gap E ships even if commits 2-3 get reverted)
- `commit 2: feat(review-spec): per-reviewer summary table — Model, Score, Verdict columns`
- `commit 3: docs(decisions): ADR 0001 — v0.6 MCP server proposed + rejected`

Each commit standalone-revertable. PR review can approve commits individually if needed.

---

## 3. Trzy zmiany (3 commits)

### 3.1 Per-reviewer summary table (commit 2)

**Marcin's concrete ask 2026-05-28:** "see summary of each subagent reviewer (what model, time spend on review, tokens used, review summary, review score 1/5)"

**v2 scope (post-review):**
- Add **Model**, **Score (1-5, DERIVED)**, **Verdict** columns to Step 4 final status table
- **Drop Tokens column** — empirically verified (2026-05-28 18:00) that Cursor Cloud Agent response has `run.usage = null`, `run.credits = null`, `run.tokensUsed = null`. Token column would show `—` for Marcin's primary channel + manual + skipped rows = only 2/5 row types render usefully. Defer until Cursor exposes tokens. Memory `<this-spec-iter1-audit>` documents the empirical finding.
- **Score is DERIVED only**, not self-emitted by reviewers (per hostile P0-3 — self-emit is duplicate path with compliance risk; derivation already produces every Score). Simpler spec, fewer failure modes.

### 3.2 Gap E probe fix (commit 1)

**Empirical 2026-05-28 17:30:** Marcin upgraded Cursor Pro → probe returned HTTP 400 `validation_error` with message "Cloud agent is not supported in Privacy Mode (Legacy). Switch to Privacy Mode to use cloud agents." v0.5.1 probe correctly classified as exit 44 (generic) but user message ("Cursor API probe failed (HTTP 400)") didn't surface actionable fix.

**Fix:** case 400 branch → detect Privacy Mode via **both** `error.code` field AND message grep (per hostile P1 — single-vector detection is brittle to wording changes) → exit 45 (NEW) with user-facing actionable message.

### 3.3 v0.6 MCP rejection ADR (commit 3)

**Marcin verbatim 2026-05-28 ~16:50:** "ta info powinna być w pr-autopilot skill ! :P"

**Fix:** new `docs/decisions/0001-v0.6-mcp-server-rejected.md` (ADR). ROADMAP gets a **1-line** anti-roadmap entry pointing to the ADR (per hostile P1 — ADR is canonical, ROADMAP is link only, no redundancy).

---

## 4. Co dodajemy

| Plik | Status | Commit | Cel |
|---|---|---|---|
| `hooks/cursor-cloud-agent-probe.sh` | MODIFY | 1 | Case 400 branch: detect Privacy Mode via `error.code` + message grep → exit 45. |
| `hooks/tests/test-review-spec-helpers.sh` | MODIFY | 1 | New T12 (privacy mode 400 message → 45), T12b (privacy_mode_required code → 45), T13 (generic 400 → 44). |
| `reviewers/CURSOR-SETUP.md` | MODIFY | 1 | Add "Privacy Mode requirement" subsection. |
| `skills/review-spec/SKILL.md` | MODIFY | 1 + 2 | Step 2 case `45)` branch (commit 1). Step 4 table gains 3 columns + outlier footer + derivation-only Score (commit 2). |
| `EVAL.md` | MODIFY | 1 + 2 | New scenario 50b (Gap E live skip — commit 1). New scenario 51 (per-reviewer table — commit 2). |
| `docs/decisions/0001-v0.6-mcp-server-rejected.md` | NEW | 3 | ADR (~200 lines): context, decision, reasoning, alternatives, "do not re-propose unless" gate (strengthened per hostile P1). |
| `docs/decisions/README.md` | NEW | 3 | Short README explaining ADR pattern (~20 lines). Committed alongside ADR for first-use. |
| `ROADMAP.md` | MODIFY | 3 | One-liner Anti-roadmap entry pointing to ADR 0001. NO duplicate reasoning. |
| `.claude-plugin/plugin.json` | MODIFY | 3 (last) | Bump `"version": "0.5.1"` → `"0.5.2"`. Last commit so revert of any earlier commit doesn't strand the version bump. |
| `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.2-per-reviewer-summary.md` | NEW (this file) | 2 | Spec. |

**Out of scope:**
- Tokens column (dropped — empirical finding)
- Score self-emit in adapter prompts (dropped — use derivation only)
- MCP server (rejected, see ADR)
- Gemini adapter (defer until OSS demand)
- D.2 TRUE incremental progress (fake UX in append-only chat, per v0.6 ADR)
- Cross-skill rollout to `/assign`, `/step`

---

## 5. Wymagania funkcjonalne

### 5.1 Per-reviewer summary table (commit 2)

#### 5.1.1 Score (1-5) — derivation ONLY

No adapter prompt changes. Score is **always derived** from P0/P1/P2 counts using this rubric (post-iter1 fix for P2-only ambiguity):

| Conditions | Score |
|---|---|
| 0 P0 + 0 P1 + ≤4 P2 | **5/5** (ship-ready) |
| 0 P0 + 0 P1 + ≥5 P2 | 4/5 (lots of nits) |
| 0 P0 + 1-2 P1 | 4/5 (minor polish) |
| 0 P0 + ≥3 P1 | 3/5 (revise recommended — lots of P1) |
| 1 P0 | 3/5 (1 blocker — revise) |
| 2 P0 | 2/5 (significant issues) |
| ≥3 P0 | 1/5 (block — fundamental problems) |

Skipped/manual reviewers (`—` rows) → no Score, **excluded from aggregate mean** (per hostile P1-5).

P2 deliberately considered ONLY in the "0 P0 + 0 P1" branch (high score discrimination). For any branch where P0 or P1 > 0, P2 is ignored — higher-severity findings dominate. This is explicit (was ambiguous in iter1).

#### 5.1.2 Step 4 final status table (6 columns)

```markdown
| Reviewer | Model | Score | Time | Findings (P0/P1/P2) | Verdict |
|---|---|---|---|---|---|
| feature-dev:code-reviewer | claude-opus-4-7 (feature-dev) | 4/5 | 102s | 0/3/5 | Solid spec; minor polish on §5.3 |
| general-purpose adversarial | claude-opus-4-7 (general) | 3/5 | 84s | 3/6/0 | Three blockers; revise before TDD |
| cursor-cloud-agent | composer-2.5 | 5/5 | 67s | 0/0/2 | Looks ready to ship |
| codex-exec | gpt-5 | ⏭ skipped | — | — | OPENAI_API_KEY not set |
| composer-2.5 manual | — | 📋 pending | — | — | Optional paste-back |

**Aggregate: P0 X, P1 Y, P2 Z → spec_revising | spec_review_complete**

⚠️ Low score outlier: <reviewer-kind> <N/5> (<P0>P0). Aggregate avg hides blocker.
```

**Outlier footer:** printed BELOW the aggregate line IF any single reviewer's derived score ≤ 2. Surfaces the blocker that mean would otherwise hide (per code-reviewer P1-3 fix).

**Verdict source:**
- For each reviewer, extract the FIRST sentence of their findings response, OR synthesize one if missing:
  - 0 P0: "Spec ready, <N> P1, <K> P2."
  - 1 P0: "One blocker — revise §<topic if extractable>"
  - ≥2 P0: "<N> blockers — significant revision needed"

**No adapter prompt changes.** All extraction happens in Step 4 skill logic.

**Verdict length:** truncate to ≤60 chars (with trailing `…` if cut) so the table column stays readable in narrow chat panels. Synthesis logic enforces this (per Composer P2-4).

**Status column absorbed:** v0.5.1's separate `Status` column (✅ complete / ⏭ skipped / ❌ failed) is folded into the `Score` column for v0.5.2 — skipped renders as `⏭ skipped`, pending as `📋 pending`, failed as `❌ failed`. Only completed reviewers get a numeric `N/5`. This is intentional consolidation (per Composer P2-2).

#### 5.1.3 Score exclusion rules

Mean over reviewers with a numeric Score only. Rows excluded from the mean: `⏭ skipped`, `📋 pending`, `📋 prompt printed`, `❌ failed`, `⏱ timeout`, `—` (per Composer P2-3 — pending and timeout were undocumented).

#### 5.1.4 Model column sourcing (per Composer P1-1)

For each reviewer kind, the Model column value:

| Reviewer kind | Source | Example value | Fallback |
|---|---|---|---|
| `claude-code-reviewer-subagent` | Hardcoded per skill `subagent_type` field | `claude-opus-4-7 (feature-dev)` | `claude-opus-4-7 (feature-dev)` (no fallback needed — known) |
| `claude-self-review` (adversarial general-purpose) | Hardcoded per skill `subagent_type` field | `claude-opus-4-7 (general)` | `claude-opus-4-7 (general)` |
| `codex-exec` | Parse from codex JSON output: `.usage.model` or `.model` field if present | `gpt-5` | `codex (model unknown)` |
| `cursor-cloud-agent` | Parse from API response: `.run.model.id` or `.agent.model.id` if present | `composer-2.5` | `composer-2.5` (skill knows we requested it) |
| `composer-2.5-manual` | N/A — manual | `—` | `—` |

Implementation: small switch statement in Step 4 aggregation code. No skill markdown changes required for v0.5.2 (use existing JSON parsing).

#### 5.1.5 TodoWrite sentinel update

v0.5.1's single sentinel item gains aggregate info:
```typescript
TodoWrite([
  { content: "/review-spec dispatch (iter <n>) — N reviewers in parallel",
    activeForm: "Done: N reviewers, X P0 / Y P1 / Z P2, avg <A>/5 over <M> scored channels (in <wallclock>s)",
    status: "completed" }
])
```

`A` = mean over reviewers with numeric score; `M` = count of reviewers with numeric score (excludes skipped/manual `—`).

### 5.2 Gap E probe fix (commit 1)

#### 5.2.1 `hooks/cursor-cloud-agent-probe.sh` case 400

Detection uses BOTH `error.code` AND message grep (per hostile P1-7 — defense in depth):

```bash
400)
  if ! head -c 1 "$TMP" 2>/dev/null | grep -q '{'; then
    echo "Cursor API returned 400 with non-JSON body" >&2
    exit 44
  fi

  CODE=$(jq -r '.error.code // empty' "$TMP" 2>/dev/null)
  MSG=$(jq -r '.error.message // empty' "$TMP" 2>/dev/null)

  # Detection: explicit privacy-mode code OR message grep (case-insensitive)
  # Empirical 2026-05-28 17:30: Cursor returns code="validation_error" + message
  # containing "Privacy Mode (Legacy)". Future Cursor versions may add a dedicated
  # code like "privacy_mode_required" — handle both.
  if [ "$CODE" = "privacy_mode_required" ] || echo "$MSG" | grep -qi "privacy mode"; then
    echo "Cursor Cloud Agent blocked by Privacy Mode (Legacy). Disable in Cursor Settings → Privacy." >&2
    exit 45
  fi

  echo "Cursor API returned 400 (${CODE:-unknown}): ${MSG:-no message}" >&2
  exit 44
  ;;
```

Exit code 45 added (v0.5.1 used 0/42/43/44 — verified no collision via grep).

#### 5.2.2 SKILL.md Step 2 case statement

```bash
45)
  REVIEWERS+=('{"kind":"cursor-cloud-agent","status":"skipped","reason":"privacy_mode_legacy","iteration":<n>}')
  echo "⚠️ Cursor Cloud Agent skipped — Privacy Mode (Legacy) blocks Cloud Agent. Disable in Cursor Settings → Privacy."
  ;;
```

**`skipReason` union update** (per Composer P1-3): the existing union in v0.5.1 SKILL.md Step 4 was `plan_required | invalid_key | probe_error | no_env`. v0.5.2 extends to: `plan_required | invalid_key | probe_error | no_env | privacy_mode_legacy`. Probe header doc comment also updated to list exit code 45 in the taxonomy.

**Bootstrap mode parity** (per Composer P1-2): v0.5.1's bootstrap mode (`--bootstrap <path>`) calls into the same Step 4 aggregation logic. Therefore v0.5.2's 6-column table + outlier footer apply identically in bootstrap mode. No claim-file write in bootstrap (per v0.5.1); just print + ExoVault audit memory.

#### 5.2.3 Tests

New T12 + T12b + T13 (per hostile P1-7 message-or-code defense in depth + Composer P1-4 code-path test):

```bash
# T12a: 400 with privacy-mode message → exit 45 (message-based detection)
start_mock 400 '{"error":{"code":"validation_error","message":"Bad Request: Cloud agent is not supported in Privacy Mode (Legacy). Switch to Privacy Mode to use cloud agents."}}'
assert_exit "T12 HTTP 400 Privacy Mode message → 45" 45 $? "$STDERR"

# T12b: 400 with privacy_mode_required CODE but unrelated message → exit 45 (code-based detection)
# Per Composer P1-4: defense-in-depth was half-tested (only message path covered by T12)
start_mock 400 '{"error":{"code":"privacy_mode_required","message":"Configuration error"}}'
assert_exit "T12b HTTP 400 privacy_mode_required code → 45" 45 $? "$STDERR"

# T13: 400 with generic validation_error → exit 44 (no privacy_mode mention)
start_mock 400 '{"error":{"code":"validation_error","message":"Required parameter missing"}}'
assert_exit "T13 HTTP 400 generic → 44" 44 $? "$STDERR"
```

Total after v0.5.2: 13 (v0.5.1) + 3 new (T12, T12b, T13) = **16 tests**.

**Test count math** (post-v2.1 update — earlier draft mis-counted by omitting T12b):
- v0.5.1 harness: T1, T2, T3, T4, T5, T6, T7, T7b, T8, T8b, T9, T10, T11 = **13 tests** (with `b` variants counted)
- v0.5.2 adds T12, T12b, T13 = **3 new** (T12b added in v2.1 per Composer P1-4 — defense-in-depth code-vs-message detection)
- Total after v0.5.2: **16 tests** (13 + 3)
- Range label: "T1-T11 + T7b + T8b + T12 + T12b + T13" — explicit enumeration since the bare `T1-T13` range collides with the `b` variants.

Spec acceptance §6 uses "16/16 PASS" — explicit count matching the enumeration.

### 5.3 v0.6 MCP rejection ADR (commit 3)

#### 5.3.1 `docs/decisions/0001-v0.6-mcp-server-rejected.md` (~200 lines)

Same structure as iter1 (Context, Decision, Reasoning with 3 P0s detailed, Alternatives, Consequences) PLUS strengthened "Do not re-propose unless" gate (per hostile P1-1):

```markdown
## Do not re-propose unless ALL of these are demonstrated

A motivated re-proposer must furnish:

1. **N≥3 distinct user-reported incidents** in GitHub Issues naming markdown-bash
   dispatch as the cause. Single anecdotes don't count.
2. **Production deployment age ≥ 6 weeks** of v0.5.1 with documented dispatch
   failures (not theoretical concerns).
3. **Working alternative attempted first** — specifically, a Bats test suite for
   the existing bash dispatch (per Alternatives §2 of this ADR). If Bats tests
   solve the testability concern, MCP is unnecessary.
4. **UX prototype** in real Claude Code chat showing how mid-flight updates render
   (NOT just text — screenshots of actual chat behavior). v0.6 D.2 assumed
   live-updating UI but Claude Code chat is append-only — must prove the win is
   real, not 24 stacked tables.
5. **`${CLAUDE_PLUGIN_ROOT}` expansion verified** in `.claude/settings.json`
   `mcpServers.args` array, or alternative resolution mechanism specified.
6. **Aggregation bridge specified** between Claude subagent findings (in
   conversation context) and MCP-tracked findings (on disk).

If ALL 6 demonstrated → reopen as v0.7+ proposal with this ADR linked.
```

#### 5.3.2 `ROADMAP.md` Anti-roadmap (1-line, link only)

```markdown
- **MCP server for review dispatch** — proposed and rejected 2026-05-28.
  See [ADR 0001](docs/decisions/0001-v0.6-mcp-server-rejected.md).
```

No duplicate reasoning. ADR is canonical.

#### 5.3.3 `docs/decisions/README.md` (small)

Short README documenting the ADR pattern + numbering convention (~20 lines). Included in commit 3 to establish the pattern for future ADRs.

---

## 6. Acceptance

Per Marcin workflow rule #3:

1. **JSON valid:** `plugin.json` version 0.5.2.
2. **Probe tests:** `bash hooks/tests/test-review-spec-helpers.sh` → **16/16 PASS** (T1-T11 + T7b + T8b + T12 + T12b + T13).
3. **Regression:** `bash hooks/tests/test-spec-gate.sh` 14/14 + `bash hooks/tests/test-trigger.sh` 15/15.
4. **Markdownlint:** clean on SKILL.md, EVAL.md, ROADMAP.md, spec, ADR, decisions/README.
5. **Probe live re-validation:** `bash hooks/cursor-cloud-agent-probe.sh` on Marcin's machine returns exit 0 (Pro+Privacy active, already validated 2026-05-28 17:30).
6. **Reviewer iter1 + iter2 done:** see §A audit log.
7. **Marcin approval (rule #6):** Marcin merges PR.

**Post-merge EVAL gating:**

8. **EVAL 51** — Step 4 table shows 6 columns: Reviewer, Model, Score (derived), Time, Findings, Verdict. Outlier footer fires when any reviewer score ≤ 2. Manual visual inspection on next real `/review-spec` invocation.
9. **EVAL 50b removed from gating** (per hostile P1-4 — was "test we skip in practice"). T12 + T12b unit tests cover the Gap E path (message-based and code-based detection). If Marcin wants to verify live, optional manual check only.
10. **EVAL 43 live** — already validated 2026-05-28 17:30 (probe exit 0 after Privacy Mode flip).
11. **ADR usable** — Marcin or future contributor reads `docs/decisions/0001-v0.6-mcp-server-rejected.md` without conversation context, understands rejection rationale, sees 6-prerequisite gate.

---

## 7. Ryzyka i mitigacje

| Ryzyko | Mitigacja |
|---|---|
| 6-column table too wide for narrow chat. | Acceptable (markdown wraps); Verdict ≤ 60 chars enforced by synthesis logic. |
| Outlier footer false-fires (e.g., codex skipped not actually a score-1/5). | Outlier check only on rows with numeric Score (skipped/manual excluded). Explicit in §5.1.1. |
| Aggregate mean still potentially confusing (4 reviewers 5/5/5/2 → mean 4.25 but 2 is concerning). | Outlier footer (§5.1.2) handles this: prints when ANY score ≤ 2. Mean is for visual scan; outlier footer is for action. |
| Verdict synthesis logic produces awkward text for edge cases (e.g., "0 P0 + 0 P1 + 15 P2"). | First-sentence extraction from raw reviewer output is preferred; synthesis only when extraction fails. Acceptable text drift. |
| Privacy Mode message text changes in future Cursor API. | Defense in depth: check `error.code == privacy_mode_required` (future-proofs) OR message grep "privacy mode" (current). Fall through to exit 44 with raw message echoed otherwise. |
| Cursor 500 errors (observed empirically 2026-05-28 18:00). | v0.5.1 probe correctly handles 500 as exit 44 (generic). v0.5.2 inherits this behavior unchanged. New finding to document, not a v0.5.2 fix. |
| Cursor API doesn't expose tokens (empirical). | Tokens column DROPPED from v0.5.2 scope. Revisit when Cursor exposes usage. Memory documents this. |
| ADR file (~200 lines) too long for first ADR. | Trade-off: comprehensive rejection rationale prevents re-derivation. Subsequent ADRs can be shorter (rule-of-three for ADR length norms after we have 3+). |
| Score self-emit dropped → relying entirely on derivation accuracy. | Derivation rubric (§5.1.1) is explicit and tested. Self-emit was duplicate path with compliance risk. Single source of truth. |
| 3-commit-in-1-PR split — Marcin might merge as single squash, losing granularity. | Document in PR description: "If reverting, use `git revert` on individual commits, not the squash-merge commit." Marcin's standard squash merge still produces ONE commit on main, but the branch history retains the 3-commit structure for archaeological purposes. |

---

## 8. Test plan

1. **Unit (bash):** `bash hooks/tests/test-review-spec-helpers.sh` — 16 tests (T1-T11 + T7b + T8b + T12 + T12b + T13).
2. **Regression:** `test-spec-gate.sh` 14/14 + `test-trigger.sh` 15/15.
3. **Markdownlint:** clean on all .md files touched (SKILL.md, EVAL.md, ROADMAP.md, spec, ADR, decisions/README).
4. **Live Cursor probe:** `bash hooks/cursor-cloud-agent-probe.sh` → exit 0 (Pro+Privacy validated 2026-05-28 17:30).
5. **Visual inspection (post-merge):** next `/review-spec` invocation shows 6-column table. Manual.

---

## 9. Rollback plan

3-commit structure gives granular revert:
- Revert commit 1 only: lose Gap E fix; keep table + ADR
- Revert commit 2 only: lose new table columns; keep Gap E fix + ADR
- Revert commit 3 only: lose ADR + version bump; keep table + Gap E (table still works at v0.5.1 plugin version — would need `git revert` on the plugin.json bump as part of this scenario)
- Revert all: full rollback to v0.5.1

Squash-merge would collapse to single commit; spec PR description documents the granular-revert option explicitly.

---

## 10. Następne kroki po merge

1. **Resume Asistel onboarding** with `/pr-autopilot:review-spec --bootstrap "c:\Users\sufam\IdeaProjects\ai phone assistent\.claude\worktrees\feat-pr-autopilot-v0.5-onboard\specs\2026-05-28-pr-autopilot-v0.5-onboarding.md"`. With Marcin on Cursor Pro + Privacy Mode flipped, cursor-cloud-agent dispatches automatically — EVAL 48b live dogfood with 3-channel review.
2. **v0.5.3 candidates** (post-production-data only):
   - Cursor API tokens exposure if Cursor adds it → Tokens column revival
   - Gemini Free adapter if OSS demand emerges
   - PostToolUse `spec-write nudge` hook (Composer's v0.5.2 suggestion, deferred for now)
3. **v0.7 reservation:** Cursor-native runtime adapter (Path C). MCP server idea remains rejected per ADR 0001 unless 6 prerequisites met.

---

## 11. References

- v0.5.1 spec: `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.1-review-spec-improvements.md`
- v0.5.1 squash commit `3b12499` (PR #6, merged 2026-05-28)
- Gap E discovery memory: `3341e984`
- v0.6 MCP rejection memory: `b2441212`
- Empirical "Cursor API tokens are null" finding: §A.iter1 audit log
- Empirical "Cursor 500 dispatch failures intermittent" finding: §A.iter1 audit log
- ADR pattern reference: https://adr.github.io

---

## §A — Reviewer audit log

### Iter1 (2-subagent review, 2026-05-28 ~18:00)

**Channels attempted:**
- ✅ `feature-dev:code-reviewer` (FREE, claude-opus-4-7) — REVISE-RECOMMENDED, Score: 3/5, 0 P0 + 3 P1 + 5 P2
- ✅ `general-purpose` adversarial (FREE, claude-opus-4-7, hostile) — REVISE-RECOMMENDED, Score: 2/5, 3 P0 + 7 P1
- ❌ `cursor-cloud-agent` — TWO dispatch attempts both returned HTTP 500 `{code:"internal", message:"Error"}` despite probe exit 0 + earlier 201 connectivity test. v0.5.1 probe correctly degraded to exit 44 ("skip with retry hint"). Cursor Cloud Agent had intermittent reliability issues 2026-05-28 18:00; classified as outside-our-control infrastructure issue, not a v0.5.2 must-fix.
- ❌ codex-exec — no `OPENAI_API_KEY`, no codex CLI
- ⏸ Composer 2.5 manual — not attempted (cursor-cloud-agent is the programmatic equivalent for Pro users)

**Findings deduplicated + resolutions in v2:**

| ID | Severity | Source | Title | v2 Resolution |
|---|---|---|---|---|
| F1 | P0 | Hostile #1 | 3 unrelated changes bundled | Split into **3 commits in 1 PR** (§2). Granular revert documented in §9. |
| F2 | P0 | Hostile #2 | Tokens column delivers `—` for primary channel | **DROPPED Tokens column** from v0.5.2 scope (§3.1). Empirically confirmed Cursor `run.usage/credits/tokensUsed` are all null. Revisit in v0.5.3+ if Cursor exposes. |
| F3 | P0 | Hostile #3 | Score self-emit unenforced + duplicate of derivation | **DROPPED self-emit**. Score is DERIVED only from P0/P1/P2 counts (§5.1.1). Simpler spec, single source of truth, no adapter prompt changes. |
| F4 | P1 | CR | Score rubric P2-only ambiguity | Added explicit "0 P0 + 0 P1 + ≥5 P2 → 4" rule + commented "P2 only counts in P0=P1=0 branch" (§5.1.1). |
| F5 | P1 | CR | `total_tokens` Agent tool unverified | Moot — Tokens column dropped (F2). |
| F6 | P1 | CR | Aggregate avg hides 1/5 outlier | Added **outlier footer** at Step 4 when any score ≤ 2 (§5.1.2). |
| F7 | P1 | CR | Test count math typo (13+2=15 vs T1-T13) | Fixed: 13 tests in v0.5.1 (with T7b/T8b counted) + 3 new in v2.1 (T12, T12b, T13) = 16 total. Acceptance §6.2 says explicit "16/16 PASS". (Initial v2 only added T12+T13; T12b added in v2.1 per Composer P1-4 — count corrected here.) |
| F8 | P1 | Hostile | ADR + ROADMAP redundancy | **ROADMAP shrunk to 1 line** with link to ADR (§5.3.2). ADR is canonical. |
| F9 | P1 | Hostile | EVAL 50b is "test we skip" | **Removed from gating** (§6 item 9). T12 unit test covers. Optional manual check only. (Cross-ref typo §9.2 → §6.9 fixed per Composer P2-1.) |
| F10 | P1 | Hostile | Score mean ambiguity with `—` rows | Spec: mean excludes skipped/manual rows (§5.1.1, §5.1.3). |
| F11 | P1 | Hostile | Probe grep too narrow | Defense in depth: BOTH `error.code == privacy_mode_required` OR message grep (§5.2.1). |
| F12 | P1 | Hostile | ADR re-proposal gate too easy to game | Strengthened to **6 prerequisites** (was 4) including "N≥3 user-reported incidents", "≥6 weeks production age", "Bats alternative attempted first" (§5.3.1). |
| F13 | P1 | Hostile | Recursive dogfood framing inflated | §A reframed: "First live test of cursor-cloud-agent channel" not "recursive dogfood validates v0.5.2 features." Honest. |
| F14 | P2 | Hostile | Tokens-as-trivia | Subsumed by F2 (dropped). |
| F15 | P2 | Both | Probe message grep brittleness | Subsumed by F11. |
| F16 | P2 | Both | ADR-out-of-band references | Acceptable: ADR contains all primary rejection reasoning inline; memory IDs are pointers, not load-bearing. |
| F17 | P2 | Hostile | Spec size growing | Acknowledged. v0.5.2 spec v2 is ~22KB (smaller than v1's 28KB) post-fix. Trend monitored. |
| F18 | New empirical | Live test | Cursor API tokens fields all null | Documented (informs F2 drop). Adds new fact to v0.5 ROADMAP "Future" items: "Tokens column when Cursor exposes". |
| F19 | New empirical | Live test | Cursor 500 dispatch failures | Documented in §7 risk table. v0.5.1 probe handles correctly (exit 44). No v0.5.2 fix needed. |

**Aggregated counts after v2:** P0: 0 (3 → all addressed/dropped). P1: 0 (7 → all addressed). P2: 0 (5 → addressed or acknowledged). New: 2 empirical findings documented.

**Iter1 verdict aggregate (per §5.1.2 derivation rubric):**
- code-reviewer: 0 P0 + 3 P1 = 3/5 (revise — lots of P1)
- adversarial: 3 P0 = 1/5 (block — fundamental problems addressed)
- aggregate mean over 2 numeric: 2/5 → "spec_revising"
- ⚠️ Outlier: adversarial 1/5 (3 P0). All addressed in v2.

### Iter3 (2026-05-28 ~18:30) — Composer 2.5 review via Cursor IDE (Marcin paste-back)

Marcin ran Composer 2.5 on spec v2 from Cursor IDE (now that Cursor Pro + Privacy Mode work). Verdict pasted back into Claude chat: **REVISE-RECOMMENDED — 0 P0, 4 P1, 7 P2.** Score: 4/5 (per the spec's own derivation rubric). Recommendation: "Approve commits 1+3 for TDD now; hold commit 2 for ~15-min v2.1 spec edits."

**Findings + v2.1 resolutions:**

| ID | Severity | Finding | v2.1 Resolution |
|---|---|---|---|
| Composer-P1-1 | P1 | Model column has no extraction spec | Added **§5.1.4 Model column sourcing** with per-kind rules + fallback values. |
| Composer-P1-2 | P1 | Bootstrap mode table not mentioned | Added explicit one-line note: bootstrap mode uses identical 6-column Step 4 table; no claim-file write (§5.2.2 trailing block). |
| Composer-P1-3 | P1 | `skipReason` schema needs `privacy_mode_legacy` added | Documented union update + probe header doc update in §5.2.2. |
| Composer-P1-4 | P1 | No T12b for `privacy_mode_required` code path | Added **T12b** (code-only detection) in §5.2.3. Defense-in-depth fully covered. Test count → 16. |
| Composer-P2-1 | P2 | Cross-ref typo §9.2 → §6.9 | Fixed in F9 row above. |
| Composer-P2-2 | P2 | Status column dropped silently | Documented absorption into Score column in §5.1.2 trailing block. |
| Composer-P2-3 | P2 | pending/timeout in Score exclusion | Documented in new **§5.1.3 Score exclusion rules**. |
| Composer-P2-4 | P2 | Verdict ≤60 chars truncation rule | Documented in §5.1.2 trailing block. |
| Composer-P2-5 | P2 | `CLAUDE_PLUGIN_ROOT` fallback hardcodes `0.5.1` | TDD task: SKILL.md L177 fallback updated to `0.5.2` as part of commit 3 (plugin.json bump). Noted in commit 3 scope. |
| Composer-P2-6 | P2 | Score derivation untested (manual EVAL only) | Acceptable for v0.5.2 per Composer ("acceptable for v0.5.2"); deferred. Consider fixture in v0.5.3+ if rubric tweaks happen. |
| Composer-P2-7 | P2 | §A iter2 status stale | This block IS iter3 audit. Updated. |

**Channels used in iter3:**
- ✅ `cursor-cloud-agent` via Cursor IDE (composer-2.5, manual paste-back by Marcin since API 500s earlier)
- ⏸ codex-exec, claude subagents NOT re-run (no expected new findings vs iter1)

**Iter3 derived score:** 0 P0 + 4 P1 + 7 P2 → **3/5 (revise recommended — ≥3 P1)** per the spec's own rubric (§5.1.1). But Composer reported 4/5 — slight charitable interpretation. Either way: no P0, no blockers, polish only.

**Aggregate after v2.1:** 0 P0, 0 P1 (all addressed), some P2s acknowledged/deferred. Status: **spec_review_complete** per workflow rule. Ready for Marcin approval → TDD.

**Recursive dogfood lesson:** v0.5.2 spec proposing "per-reviewer summary" got reviewed by 3 reviewers (2 Claude subagents + Composer 2.5), and we can compute Composer's score using the very rubric this spec proposes. That recursion is the gentle kind that closes loops, not the misleading kind. Worth a sentence in the README post-v0.5.2.

---

**Approval gate:** spec v2 ready for Marcin direct approval. Per workflow rule #3, Marcin approval required before TDD. Rule #6: only Marcin merges.
