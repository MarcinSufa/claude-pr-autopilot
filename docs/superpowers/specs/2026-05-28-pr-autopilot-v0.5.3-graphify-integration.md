# Spec — claude-pr-autopilot v0.5.3 — graphify code knowledge graph awareness (scope-reduced)

**Data:** 2026-05-29 (iter3 — scope-reduced revision after iter1 + iter2)
**Branch:** `feat/v0.5.3-graphify-integration`
**Worktree:** `c:\Users\sufam\IdeaProjects\claude-pr-autopilot-graphify` (off `origin/main@a93a69f`)
**Spec autor:** claude_code (Opus 4.7 1M)
**Iteracja:** v3 — **scope reduced** (recipe + Mode Y @copilot augmentation DROPPED; see §A audit log for full disposition)
**Prior art:** ExoVault memories `a9df909c`, `fb285a18`, `ca13f9dd`
**Slot freed by:** [ADR 0002](../../decisions/0002-v0.5.3-cso-final-pass-deferred.md)

---

## 1. Cel (1 zdanie)

Dodać **opt-in graphify code knowledge graph awareness** w `/pr-autopilot:assign`, `/pr-autopilot:step` (Mode X), oraz `/pr-autopilot:review-spec` — filesystem-only pre-check dla `graphify-out/graph.json`, **advisory=auto = INFO + continue, advisory=always = PAUSE**, dispatched subagents w `/review-spec` + main-loop triage w `/step` step 10 otrzymują hint o graf-query-first pattern. **Sharing model (commit-vs-CI-vs-vault) jest USER-DRIVEN choice; v0.5.3 NIE prescribes a recipe** — README zawiera krótki pointer do trzech approaches z honest tradeoffs.

---

## 2. Wersjonowanie

**v0.5.2 → v0.5.3 (PATCH).** Strictly additive + state schema bump v3 → v4 (purely additive fields):

- New pre-flight check at 0.4b (named anchor)
- State schema v3 → v4 (additive: `graphifyAvailable`, `graphifyBuiltAtCommit`)
- New `state.graphifyAvailable=true` triggers prompt enhancement in `/review-spec` adapter prompts + `/step` step 10 triage preamble
- New brief "Code knowledge graph (graphify)" subsection in README pointing to (but not prescribing) 3 sharing approaches
- 7 new EVAL scenarios (renumbered 52-52g, fixing iter2 P0 #1 collision with existing scenario 26)

Single commit.

---

## 3. Główna zmiana

Pr-autopilot becomes **graph-aware**:

- **Default behavior (`advisory=auto`):** Filesystem check for `graphify-out/graph.json`. Present → silent pass + subagents/triage get the hint. Absent → ONE-TIME per-repo INFO notification suggesting `/graphify .`, loop continues normally.
- **Strict mode (`advisory=always`):** PAUSE with actionable message if graph missing.
- **Off (`advisory=off`):** Skip the check entirely.

**No auto-build. No prescribed sharing model. No comment-body augmentation.** v0.5.3 is a minimal awareness mechanism — sharing recipe is deferred to v0.5.4 after empirical hook testing.

**Why the scope reduction (from iter2):** the original iter2 recipe shipped 7 of the 8 P0 surface area (auto-amend `--no-verify` recursion empirically verified to fire 6 times in a tmp repo, `built_at_commit` confabulation, `graphify update` doesn't update doc-files, `@copilot` comment body unsupported speculation, gitleaks "MANDATORY" without integration). The pr-autopilot integration itself (~60 lines of skill edits) is conceptually clean and survives. v0.5.3 ships the clean part; the recipe gets its own spec once we've tested a hook pattern end-to-end in `/tmp`.

---

## 4. Co dodajemy

| Plik | Status | Cel |
|---|---|---|
| `skills/step/SKILL.md` | MODIFY | Pre-flight 0.4b (filesystem-only `_graphifyFsState`); state schema v3→v4 bump + additive field defaults; new §0.5a (post-load state setting + advisory dispatch) **placed AFTER §0.6 merge-wait short-circuit** (per iter2 P0 #5 — auto-merge wait must not be disturbed); §10 triage **preamble** hint (APPEND position per iter2 P1 #7 — long context); stop conditions table extension. |
| `skills/review-spec/SKILL.md` | MODIFY | Adapter prompt templates (Step 2) gain graphify hint via **dispatch-time filesystem check** (NOT state lookup — bootstrap mode has no PR state per iter1 P0). |
| `skills/assign/SKILL.md` | MODIFY | Pre-flight equivalent: **always advisory, never PAUSE** (per iter1 P0 #1). Broken-folder still INFOs, never blocks claim creation. |
| `EVAL.md` | MODIFY | Scenarios **52, 52b, 52c, 52d, 52e, 52f, 52g** — renumbered from iter2's `26-26h` per iter2 P0 #1 (collision with existing v0.3 scenario 26 "Auto-trigger: draft skip"). Update EVAL counter at bottom. |
| `README.md` | MODIFY | One-paragraph "Code knowledge graph awareness" + short "Sharing your graph" pointer listing 3 approaches (commit / CI artifact / ExoVault) without prescribing one. Explicit Mode Y carve-out. No 50-70% token reduction claim. |
| `.claude-plugin/plugin.json` | MODIFY | Bump `0.5.2` → `0.5.3`. |
| `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.3-graphify-integration.md` | NEW (this file) | Spec, iter3. |

**Out of scope (v0.5.3, deferred to v0.5.4+):**

- **Sharing recipe** (committed graph.json + git merge driver + pre/post-commit hook). Reason: iter2 recipe was empirically broken (`--no-verify` doesn't prevent post-commit recursion; verified by adversarial reviewer running it in tmp). v0.5.4 will ship a recipe AFTER we've tested a hook pattern end-to-end (with sentinel env var, doc-file detection, gitleaks integration, husky-append example, Windows PATH propagation verified).
- **Mode Y `@copilot` comment body augmentation** (iter2 §5.2 C). Reason: speculation about SWE Agent context-reading behavior; could break Mode Y trigger (highest blast radius mode). v0.5.4 will revisit after empirical measurement.
- **`graphify.minimumStaleness` config** — needs `state.graphifyBuiltAtCommit` infrastructure (which v0.5.3 persists for forward-compat) plus git ancestry checks. v0.5.4.
- **Auto-build of missing graph by pr-autopilot** — cost-surprise UX risk.
- **Subagent graph-excerpt injection** — hint only; subagent picks what to query.
- **Multi-repo graph merging** (`graphify merge-graphs`).
- **ExoVault integration to store graphs centrally** — Option C from sharing-model decision; multi-day build.

---

## 5. Wymagania funkcjonalne

### 5.1a — Pre-flight at 0.4b (BEFORE state load — NO state interaction)

Insert in `skills/step/SKILL.md` AFTER existing 0.4 (PR exists) and BEFORE 0.5 (Load State), as named anchor `0.4b`:

```bash
# 0.4b — graphify filesystem detection (NO state interaction)
if [ -f "graphify-out/graph.json" ]; then
  _graphifyFsState="present"
elif [ -d "graphify-out" ]; then
  _graphifyFsState="broken"   # folder exists but no graph.json — last build failed
else
  _graphifyFsState="absent"
fi

# Capture owner/repo ONCE for reuse (iter2 P1 #5 — perf: no triple-gh-call)
GRAPHIFY_OWNER=$(gh repo view --json owner --jq '.owner.login')
GRAPHIFY_REPO=$(gh repo view --json name --jq '.name')
GRAPHIFY_NOTICE_FLAG="$HOME/.pr-autopilot/${GRAPHIFY_OWNER}-${GRAPHIFY_REPO}-graphify-notice.flag"
```

**No state references. No `gh pr comment`. Pure filesystem + cached owner/repo.**

### 5.1b — Post-load state setting + advisory dispatch (NEW §0.5a, placed AFTER §0.6 merge-wait)

**Critical placement fix from iter2 P0 #5:** §5.1b must run **AFTER §0.6 Merge-wait short-circuit**, not before. Reason: if `state.autoMergeQueued == true`, the tick is purely waiting for GitHub to complete an auto-merge — no review work happens, no subagents dispatch, the only valid next action is "check merge status." A graphify notification (or worse, PAUSE on `_graphifyFsState=broken`) during a queued-merge wait would abandon the merge completion path entirely. §5.1b therefore lives AFTER §0.6.

```python
# §0.5a — graphify state + advisory (runs AFTER §0.6 merge-wait short-circuit, BEFORE Mode dispatch)

cfg_advisory = config.graphify.advisory  # "auto" (default) | "always" | "off"

# ITER2 P0 #2 FIX: advisory=off short-circuits at TOP, before any filesystem dispatch
if cfg_advisory == "off":
  state.graphifyAvailable = false
  # Skip ALL filesystem dispatches AND the merge-driver advisory
  goto __graphify_advisory_done__

# advisory in {"auto", "always"} — apply filesystem state
case _graphifyFsState of:

  "present":
    state.graphifyAvailable = true

    # ITER2 ADVERSARIAL P0 #3 FIX: hardened jq filter with type check
    BUILT_AT=$(jq -r 'if (.built_at_commit | type) == "string" then .built_at_commit else "" end' graphify-out/graph.json 2>/dev/null || echo "")
    state.graphifyBuiltAtCommit = BUILT_AT
    # graphifyBuiltAtCommit may be empty string "" (legitimate when graphify produced an empty value).
    # NOT used to gate behavior in v0.5.3 — persisted for v0.5.4 `minimumStaleness` ancestry check.

  "broken":
    state.graphifyAvailable = false
    PushNotification("PR #${prNumber} PAUSED — graphify build incomplete", "graphify-out/ exists but graph.json is missing (last `graphify extract` may have failed). Run `graphify extract . --backend deepseek` to rebuild, then re-run /pr-autopilot:step ${prNumber}.")
    saveState($STATE_FILE)
    return  # PAUSE; KEEP state

  "absent":
    state.graphifyAvailable = false
    if cfg_advisory == "always":
      PushNotification("PR #${prNumber} PAUSED — graphify required but missing", "graphify.advisory=always but no graphify-out/graph.json found. Run `/graphify .` first, then re-run /pr-autopilot:step ${prNumber}. To disable strict mode set graphify.advisory=auto.")
      saveState($STATE_FILE)
      return  # PAUSE; KEEP state
    else:  # cfg_advisory == "auto"
      # Per-repo notice flag (NOT per-PR — fixes iter1 P1-12)
      if [ ! -f "$GRAPHIFY_NOTICE_FLAG" ]; then
        PushNotification("INFO: graphify recommendation", "This repo has no graphify code knowledge graph. Run `/graphify .` once for token-reduction during PR review loops. (See README §'Code knowledge graph awareness'.)")
        touch "$GRAPHIFY_NOTICE_FLAG"
      fi
      # fall through normally — loop continues

# ITER2 ADVERSARIAL P1 #1 FIX: merge-driver advisory now ALSO gated behind `cfg_advisory != "off"`
# (placed INSIDE the non-off branch via goto exit point)

__graphify_advisory_done__:
```

**State schema bump v3 → v4** (iter2 P0 #2 fix — explicit position in SKILL.md):

In `skills/step/SKILL.md` section "Key changes from v0.1 state" (~line 261-271), insert a new bullet **between** the existing v0.4 auto-merge fields bullet and the `resolvedMode` bullet:

> - **Graphify awareness fields (v0.5.3, schema v4):** `graphifyAvailable: false`, `graphifyBuiltAtCommit: ""` — set by new §0.5a check. Migration is purely additive: a v3 state file loads with both defaulted; no fresh start needed. The `state.stateSchemaVersion is None` Mode-Y ABORT guard (Y.0.5) is unaffected — v3→v4 is additive only, the guard fires on field absent, not on field value.

Update the JSON schema example block (~lines 221-258) to `"stateSchemaVersion": 4`.

### 5.1c — Variant for `/pr-autopilot:assign` (ALWAYS ADVISORY, NEVER PAUSE)

In `skills/assign/SKILL.md`, BEFORE creating the claim file:

```bash
# Filesystem-only check; assign uses INFO for ANY graphify state, never PAUSE
GRAPHIFY_OWNER=$(gh repo view --json owner --jq '.owner.login')
GRAPHIFY_REPO=$(gh repo view --json name --jq '.name')
GRAPHIFY_NOTICE_FLAG="$HOME/.pr-autopilot/${GRAPHIFY_OWNER}-${GRAPHIFY_REPO}-graphify-notice.flag"

if [ -f "graphify-out/graph.json" ]; then
  : # silent; no notification
elif [ -d "graphify-out" ]; then
  # Broken folder still INFOs in /assign (iter2 P1 #7 — rationale documented)
  # Rationale: broken-folder in /assign INFOs because blocking claim creation is worse
  # than proceeding without graph hints. /step PAUSEs because loop progress with stale
  # state would be misleading.
  echo "[INFO] graphify-out/ exists but graph.json missing. Run 'graphify extract .' to rebuild for token-reduction during /pr-autopilot:step. (advisory only; claim file will be created.)"
else
  # Honor per-repo notice flag (same flag /step uses)
  if [ ! -f "$GRAPHIFY_NOTICE_FLAG" ]; then
    echo "[INFO] This repo has no graphify code knowledge graph. Run /graphify . once for token-reduction during PR review loops. (advisory only.)"
    touch "$GRAPHIFY_NOTICE_FLAG"
  fi
fi

# Continue claim file creation regardless
```

### 5.1d — Variant for `/pr-autopilot:review-spec` (DISPATCH-TIME FILESYSTEM CHECK)

In `skills/review-spec/SKILL.md`, just before "Step 2 — dispatch sync adapters in parallel":

```bash
# Filesystem check at dispatch time — NO state file in /review-spec
if [ -f "graphify-out/graph.json" ] && [ "${config_graphify_promptHint:-true}" = "true" ]; then
  _graphifyHintEnabled="true"
else
  _graphifyHintEnabled="false"
fi
```

### 5.2 Prompt hint injection (two sites; Mode Y `@copilot` comment body DROPPED)

#### A) `/review-spec` adapter prompt templates (REAL subagent dispatch)

When `_graphifyHintEnabled == "true"` (set in §5.1d), **prepend** to each adapter prompt in `skills/review-spec/SKILL.md` (claude-code-reviewer-subagent + claude-self-review templates):

```
**Code knowledge graph available:** This repo has a graphify-built knowledge graph at
`graphify-out/graph.json`. BEFORE grep'ing for symbols or reading source files, query
the graph: `graphify explain "<symbol>"` returns the node + connections + community
in ~1-3k tokens vs ~30-100k for a multi-file grep. Use `graphify path "A" "B"` for
dependency-trace. If `graphify` errors with "command not found" (CLI not installed
locally), fall back to grep + Read without retrying.
```

**Placement: prepend** — adapter prompts are ~100 tokens; primacy/recency effects are negligible at this scale. Empirical verification deferred to v0.5.4.

#### B) `/pr-autopilot:step` Mode X step 10 triage **preamble** (in-process main-loop driver)

**Critical fix from iter1 P0 #5 (in-process, not subagent dispatch).** **Placement APPEND, not prepend** (iter2 adversarial P1 #7 — long-context Anthropic recommendation).

When `state.graphifyAvailable == true` AND `config.graphify.promptHint == true` (iter2 P1 #9 fix — both injection sites honor `promptHint`), append to Step 10 triage section AFTER the existing rubric + unresolved-threads block, BEFORE the final decision section:

```
**Graphify reminder (v0.5.3+):** Before judging reviewer comments about symbol X,
query `graphify explain "X"` to see X's connections/community. Query
`graphify path "X" "Y"` for dependency-validity questions. Only `Read` source files
when graphify returns insufficient context.
```

### 5.3 Config schema

Add to `~/.claude/settings.json` `prAutopilot` block:

```json
"graphify": {
  "advisory": "auto",
  "promptHint": true
}
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `advisory` | enum `"auto" \| "always" \| "off"` | `"auto"` | `auto` = check + INFO once per repo if missing, continue. `always` = check + PAUSE if missing. `off` = skip the check entirely. |
| `promptHint` | bool | `true` | Whether to inject the graphify hint into `/review-spec` subagent prompts AND `/step` step 10 triage preamble. Set `false` to keep detection but disable instruction injection (e.g., for baseline measurement). |

**Pattern divergence from existing reviewer keys is intentional:** `cursor.enabled` / `copilot.mode` / `claudeSelf.enabled` are explicit declarations. `graphify.advisory` is a policy on filesystem auto-detection. Documented.

### 5.4 Sharing your graph (README pointer; **NOT a prescribed recipe**)

In `README.md`, add a paragraph under "How it works" or as a new subsection:

> **Sharing the graph across teammates:** `graphify-out/graph.json` is portable (relative paths only) but per-machine by default. Three approaches, ordered by simplicity:
>
> 1. **Commit to repo + git merge driver** — simplest for small teams. `graphify-out/graph.json` is committed; `.gitattributes` registers graphify's `merge-driver` for conflict resolution. **Hook pattern for auto-refresh on commit is intentionally not prescribed by v0.5.3** — iter2 testing showed naive post-commit auto-amend recurses infinitely (`--no-verify` doesn't skip post-commit hooks). v0.5.4 will ship a tested hook pattern. For now: refresh manually with `graphify update .` when needed.
> 2. **CI artifact + GitHub Release** — works at any team size. GH Action runs `graphify extract . --backend deepseek` on main merges, uploads as a release artifact. Teammates download via `gh release download`. ~3-5h CI setup.
> 3. **ExoVault or other vault** — long-term architectural option. Net-new vault feature; multi-day build. Best for organizations that already use a centralized vault and want unified code + decision memory.
>
> v0.5.3 doesn't prescribe an approach — pick what fits your team. Pre-flight `state.graphifyAvailable` detection works regardless of source.

### 5.5 Mode Y limitation

Mode Y (Copilot SWE Agent as primary fixer) dispatches via `@copilot` mention. **v0.5.3 does NOT modify the `@copilot` comment body** (iter2 P0 #6 — appending a P.S. could break Mode Y trigger; SWE Agent might parse it as user-injected instruction and refuse). Mode Y users get NO graphify hint via pr-autopilot in v0.5.3.

**Workaround for Mode Y users:** add the graphify hint to your repo's `AGENTS.md` or `CLAUDE.md` — SWE Agent reads those on PR-trigger (documented behavior). Example:

```
This repo has a graphify code knowledge graph at `graphify-out/graph.json`.
Prefer `graphify explain "<symbol>"` over grep when investigating symbols.
```

Direct `@copilot` comment body augmentation deferred to v0.5.4 after empirical measurement of SWE Agent's response.

### 5.6 Stop conditions (revised)

| Condition | Step | Outcome |
|---|---|---|
| `advisory=off` AND any filesystem state | §0.5a | PASS (no notification, `state.graphifyAvailable=false`) |
| `state.autoMergeQueued=true` (queued-merge wait) | §0.6 short-circuits BEFORE §0.5a fires | §5.1b never runs; merge wait proceeds normally |
| `advisory=auto` AND `graph.json` present | §0.5a | PASS (silent, `state.graphifyAvailable=true`) |
| `advisory=auto` AND `graph.json` absent (no folder) | §0.5a | INFO once per repo (notice flag), continue |
| `advisory=auto` AND broken folder | §0.5a | PAUSE (KEEP state, rebuild message) |
| `advisory=always` AND `graph.json` absent | §0.5a | PAUSE (KEEP state, strict-mode message) |
| `advisory=always` AND broken folder | §0.5a | PAUSE (KEEP state, rebuild message) |

Add these rows to "Stop conditions summary" in `skills/step/SKILL.md` lines 1029-1056.

### 5.7 README change

Add a paragraph under "How it works":

> **Code knowledge graph awareness (v0.5.3+):** If your repo has a graphify-built knowledge graph at `graphify-out/graph.json`, pr-autopilot's dispatched `/review-spec` subagents and the in-loop `/step` triage will prefer querying the graph (`graphify explain "<symbol>"`) over grep'ing source files for symbol-lookup questions. **Mode Y limitation:** Copilot SWE Agent's prompt is GitHub-controlled — v0.5.3 does not augment SWE Agent's context; add the graphify hint to your repo's `AGENTS.md` or `CLAUDE.md` instead. **Token reduction expected but not yet measured** — see EVAL scenario 52 baseline. **Sharing the graph across teammates:** see §"Sharing your graph" subsection below for 3 approaches.

---

## 6. Edge cases (reduced after scope drop)

### 6.1 Graph staleness vs HEAD

`state.graphifyBuiltAtCommit` is persisted in v0.5.3 state for forward-compat. v0.5.4 will add `graphify.minimumStaleness` config using `git merge-base --is-ancestor <built_at_commit> HEAD`. **v0.5.3 does not check staleness.**

### 6.2 Worktree + assign edge case

`/assign` creates worktree from `origin/main`. If `graphify-out/graph.json` is on main but the worktree was created at an older commit, the worktree won't have it. Pre-flight `_graphifyFsState=absent` triggers the INFO notification. Mitigation: refresh worktree from `git pull origin main` after `/assign`. Documented in §5.4 README pointer.

### 6.3 graphify CLI missing on user's machine

Subagent hint says `graphify explain X` — if CLI errors with exit 127, the hint explicitly says "fall back to grep + Read without retrying." EVAL scenario 52f tests this.

### 6.4 Mode Y limitation (now bounded)

v0.5.3 provides NO Mode Y hint path beyond the manual `AGENTS.md` recommendation in §5.5 workaround. Documented in README + §5.5.

---

## 7. Test plan (EVAL.md scenarios — RENUMBERED 52-52g per iter2 P0 #1)

**Critical fix from iter2 P0 #1:** EVAL.md already defines scenario 26 (v0.3 "Auto-trigger: draft skip"). v0.5.3 graphify scenarios renumber to 52-52g (next available after the existing 50b/51/variants). Update EVAL.md counter at bottom (e.g., "54 total" → "61 total" — implementer verifies exact starting count).

**Scenario 52 — happy path, graph present**
- Setup: Asistel-like repo with `graphify-out/graph.json` committed. Config defaults.
- Expected: §0.4b sets `_graphifyFsState=present`; §0.5a sets `state.graphifyAvailable=true`, silent; subagent prompts in `/review-spec` include hint; `/step` step 10 triage preamble includes hint.

**Scenario 52b — `advisory=auto` (default), graph missing, first PR in repo**
- Setup: PR in repo without `graphify-out/`. Config defaults.
- Expected: §0.5a sets `state.graphifyAvailable=false`; per-repo notice flag created; INFO notification fires ONCE; loop continues; subagent prompts do NOT include hint.

**Scenario 52b-bis — same repo, second PR (flag already exists)**
- Setup: same repo as 52b, second PR opened, flag from 52b present.
- Expected: §0.5a does NOT re-notify; loop continues normally.

**Scenario 52c — `advisory=always`, graph missing**
- Setup: PR in repo without `graphify-out/`. Config: `graphify.advisory=always`.
- Expected: §0.5a PAUSEs with actionable message; KEEP state.

**Scenario 52d — broken folder, in `/step`**
- Setup: PR in repo with `graphify-out/cache/` but no `graphify-out/graph.json`. Config: any advisory.
- Expected: §0.5a PAUSEs with rebuild message (regardless of `auto`/`always`; only `off` skips).

**Scenario 52e — `advisory=off`**
- Setup: PR in repo WITHOUT `graphify-out/`. Config: `graphify.advisory=off`.
- Expected: §0.5a short-circuits at top, no notification, loop continues. Subagent prompts do NOT include hint.

**Scenario 52e-bis — `advisory=off` + broken folder (iter2 P0 #2 regression test)**
- Setup: PR in repo with `graphify-out/cache/` but no `graphify-out/graph.json`. Config: `graphify.advisory=off`.
- Expected: §0.5a short-circuits at top (advisory=off branch FIRST); broken folder is NOT checked; loop continues silently. **Validates the iter2 P0 #2 fix — advisory=off does NOT PAUSE on broken folder.**

**Scenario 52f — graph committed, CLI not installed locally**
- Setup: PR in repo with `graphify-out/graph.json` but teammate hasn't installed graphify CLI.
- Expected: §0.5a passes (file present); subagent gets hint; subagent's `graphify explain X` errors with exit 127; subagent falls back to grep + Read; review proceeds.

**Scenario 52g — `/assign` with broken folder (iter1 P0 #1 regression test)**
- Setup: Run `/pr-autopilot:assign <id>` in repo with `graphify-out/cache/` but no `graphify-out/graph.json`.
- Expected: INFO message echoed (NOT PAUSE), claim file created normally. **Validates the iter1 P0 #1 fix — `/assign` is always advisory.**

**Scenario 52h — queued-merge wait + graphify state change (iter2 adversarial P0 #5 regression test)**
- Setup: PR with `state.autoMergeQueued=true` (queued by prior tick); user breaks `graphify-out/` between ticks.
- Expected: §0.6 merge-wait short-circuit fires BEFORE §5.1b is reached; merge wait proceeds normally; no graphify notification interrupts the queued-merge resume. **Validates §0.5a placement AFTER §0.6.**

Each scenario gated for v0.5.3 release.

---

## 8. Risks + open questions for review (revised after scope drop)

| # | Risk | Mitigation in spec | Open? |
|---|---|---|---|
| R1 | Subagent ignores hint, still greps | Hint includes explicit fall-back; EVAL 52f tests it | Low |
| R2 | Graphify CLI not on teammate's PATH | Subagent fallback (R1) covers; v0.5.4 may add detection | Low |
| R3 | Mode Y users get no benefit | Documented in §5.5 + README; manual `AGENTS.md` workaround | Open — v0.5.4 measurement |
| R4 | Anthropic prepend-vs-append empirical uncertainty | A) short adapter prompts: prepend OK. B) long triage preamble: APPEND per Anthropic recommendation | Mitigated |
| R5 | Recipe-related risks (auto-amend, gitleaks, etc.) | **Out of scope — recipe dropped from v0.5.3** | N/A |
| R6 | Mode Y `@copilot` augmentation broke trigger | **Out of scope — augmentation dropped from v0.5.3** | N/A |

---

## 9. Open questions for the reviewer

1. **§5.1b placement AFTER §0.6 merge-wait** — confirm that §5.1b runs at "post-merge-wait but pre-Mode-dispatch" position. Should it be its own §0.6a or labeled differently to make placement unambiguous?
2. **State schema bump documentation** — §5.1b shows the new bullet text but not the exact diff position in `skills/step/SKILL.md`. Acceptable as "between v0.4 auto-merge bullet and resolvedMode bullet" or should the spec show the full patched block?
3. **Triage preamble APPEND position** — between "rubric + threads" and "final decision," explicitly. Should the spec call out the marker line / paragraph break the implementer should look for?

---

## 10. Implementation order

1. **iter3 spec review** — `/pr-autopilot:review-spec --bootstrap` (2 free Claude subagents only, NO cursor cloud per token-cost concern).
2. **Skill changes** — apply edits per §5 to `skills/step/SKILL.md`, `skills/review-spec/SKILL.md`, `skills/assign/SKILL.md`. (No recipe doc, no `@copilot` augmentation — both deferred.)
3. **EVAL scenarios** — add §7 scenarios 52-52h to EVAL.md; update counter.
4. **README + plugin.json** — bump version, add §5.4 "Sharing your graph" pointer + §5.7 awareness paragraph + Mode Y carve-out.
5. **Self-verify** — read each modified SKILL.md end-to-end checking §5.1a placement (before §0.5) and §5.1b placement (after §0.6).
6. **Commit** — single conventional commit: `feat(v0.5.3): graphify awareness (scope-reduced, recipe deferred)`.
7. **PR** — open against main.
8. **Dogfood** — run `/pr-autopilot:step <PR#>` on the PR (pr-autopilot has no graphify graph yet, tests `advisory=auto absent` path).
9. **Asistel adoption** — separately, decide on sharing model (see §5.4 README pointer); apply to Asistel as a separate concern.

---

## 11. References

- ExoVault memory `a9df909c` — original v0.5.3 graphify candidate
- ExoVault memory `fb285a18` — Marcin verbatim "yes do it for 0.5.3"
- ExoVault memory `ca13f9dd` — Asistel graphify build evidence
- [ADR 0002](../../decisions/0002-v0.5.3-cso-final-pass-deferred.md) — cso deferral pattern
- graphify repo: <https://github.com/safishamsi/graphify> (MIT, pinned v0.8.22 verified against source)
- Local Asistel CLAUDE.md §"Code Knowledge Graph (graphify)"

---

## §A. Iter2 audit log + scope-reduction disposition

**iter2 review (2 channels, no cursor per token-cost concern):**

| Channel | Model | Time | Findings |
|---|---|---|---|
| feature-dev:code-reviewer | claude-opus-4-7 | 184s | 3 P0 / 6 P1 / 2 P2 |
| general-purpose adversarial | claude-opus-4-7 | 302s | 7 P0 / 9 P1 / 0 P2 |

**Aggregate (deduplicated): ~8 P0 / ~13 P1 / 2 P2.**

iter3 disposition by P0:

| Iter2 P0 | Source | Iter3 disposition |
|---|---|---|
| EVAL scenario collision (26 already exists) | feature-dev | **FIXED** — renumbered to 52-52h |
| `advisory=off` doesn't short-circuit broken folder | feature-dev | **FIXED** — `advisory=off` now branches at TOP of §5.1b (§5.1b first line) |
| `--no-verify` doesn't stop post-commit recursion (empirically verified by adversarial in tmp) | feature-dev + adversarial (both, independently) | **DROPPED FROM SCOPE** — recipe removed entirely from v0.5.3 |
| Amend changes commit SHA → breaks pr-autopilot's own flow | adversarial | **DROPPED FROM SCOPE** — no auto-amend in v0.5.3 |
| §0.5a placement vs auto-merge wait | feature-dev + adversarial (both) | **FIXED** — §5.1b moved AFTER §0.6 merge-wait short-circuit |
| `built_at_commit` confabulated "empty" claim | adversarial | **FIXED** — hardened jq with `type` check; removed false claim |
| `graphify update` not free for non-code commits | adversarial | **DROPPED FROM SCOPE** — no auto-update hook in v0.5.3 |
| `@copilot` comment body P.S. speculation could break Mode Y | adversarial | **DROPPED FROM SCOPE** — Mode Y augmentation removed; documented manual `AGENTS.md` workaround |
| gitleaks "MANDATORY" without integration | adversarial | **DROPPED FROM SCOPE** — no recipe = no gitleaks question |
| §5.2 C targets wrong step (5.5 is multi-case) | feature-dev | **DROPPED FROM SCOPE** — §5.2 C removed |
| §4 vs §7 scenario count mismatch | feature-dev | **FIXED** — §4 row enumerates all scenarios; aligned with §7 |
| `promptHint` not honored in §5.2 B | feature-dev | **FIXED** — §5.2 B now checks `config.graphify.promptHint == true` |

**Net result:** 6 of ~8 P0s resolved by scope drop (recipe + Mode Y augmentation). 4 mechanical fixes in §5.1b pseudocode. Surface area dramatically reduced.

iter2 P1 dispositions (selected):

- `gh repo view` runs 3x per tick → **FIXED** — `GRAPHIFY_OWNER`/`GRAPHIFY_REPO` cached at top of §5.1a
- merge-driver advisory leaks for `advisory=off` → **N/A** (merge-driver advisory dropped with recipe)
- Triage preamble uses prepend on long context → **FIXED** — §5.2 B is APPEND, not prepend
- State schema bump position undocumented → **FIXED** — explicit bullet between v0.4 auto-merge and resolvedMode
- Per-PR vs per-repo flag inconsistency → **FIXED** — both notice and merge-driver advisory use per-repo flag pattern (the latter dropped anyway)
- `linguist-generated=true` doesn't actually collapse PR diffs → **N/A** (recipe dropped)

**Lesson learned (saving to memory after iter3):** specs that include recipes need to be **empirically tested end-to-end in a tmp repo BEFORE review-spec dispatch**. The adversarial reviewer running my iter2 recipe in `/tmp/gtest3` and observing 6 hook fires was decisive evidence; spec-only review by Claude subagents would never have caught it. Future v0.5.4 recipe spec MUST include a verification step.
