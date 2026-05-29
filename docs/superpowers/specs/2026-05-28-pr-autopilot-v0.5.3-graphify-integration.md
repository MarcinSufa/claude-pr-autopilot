# Spec — claude-pr-autopilot v0.5.3 — graphify code knowledge graph integration

**Data:** 2026-05-29 (iter2 revision after iter1 review)
**Branch:** `feat/v0.5.3-graphify-integration`
**Worktree:** `c:\Users\sufam\IdeaProjects\claude-pr-autopilot-graphify` (off `origin/main@a93a69f`)
**Spec autor:** claude_code (Opus 4.7 1M)
**Iteracja:** v2 (post 3-reviewer iter1 — 9 P0 / 15 P1 / 10 P2 → addressed in this revision; see §A iter1 audit log)
**Prior art:** ExoVault memories `a9df909c` (original v0.5.3 candidate), `fb285a18` ("yes do it for 0.5.3"), `ca13f9dd` (Asistel build evidence)
**Slot freed by:** [ADR 0002](../../decisions/0002-v0.5.3-cso-final-pass-deferred.md) (cso deferred)

---

## 1. Cel (1 zdanie)

Dodać **opt-in graphify code knowledge graph awareness** w `/pr-autopilot:assign`, `/pr-autopilot:step` (Mode X), oraz `/pr-autopilot:review-spec` — filesystem-only pre-check sprawdza czy `graphify-out/graph.json` istnieje, **default `advisory=auto` = INFO + continue, opt-in `advisory=always` = PAUSE**, dispatched subagents w `/review-spec` + main-loop triage w `/step` otrzymują hint o graf-query-first pattern. Cel: redukcja tokenów na symbol-lookup pytaniach w pr-autopilot loop (zmierzona empirycznie po v0.5.3 ship; nie obiecujemy konkretnego procentu).

---

## 2. Wersjonowanie

**v0.5.2 → v0.5.3 (PATCH).** Strictly additive + state schema bump v3 → v4 (purely additive fields with safe defaults):

- Nowy pre-flight check 0.4b (named anchor, NOT renumbered — per ADR 0002 lesson)
- Modyfikacje subagent prompts w `/review-spec` (FREE Claude subagents) + main-loop triage preamble w `/step` step 10
- New repo-setup recipe in `docs/recipes/graphify-team-setup.md`
- State schema v3 → v4 with additive fields + migration block (matches v0.4 auto-merge fields pattern from existing SKILL.md)

Single commit (cohesive feature, no granular revert value).

**v0.5.3 NIE wprowadza** (deferred to v0.5.4+ or skipped):

- `--force-graphify` flag (Option A sharing — graph committed to repo, always present after `git pull`)
- Auto-build of missing graph by pr-autopilot (cost surprise = bad UX; user runs `/graphify .` themselves)
- Subagent graph-excerpt injection (hint only; subagent decides what to query)
- `graphify.minimumStaleness` config (defer to v0.5.4 — needs `built_at_commit` ancestry check infrastructure)
- Mode Y SWE Agent automatic hint injection beyond the `@copilot` comment body (limited by GitHub-controlled prompt)

---

## 3. Główna zmiana

Pr-autopilot becomes **graph-aware**:

- **Default behavior (`advisory=auto`):** Pre-check looks for `graphify-out/graph.json`. If present → silent pass; subagents get the hint. If missing → ONE-TIME INFO notification ("this repo has no knowledge graph — `/graphify .` would reduce subagent tokens"), loop continues normally. Notification flag is **per-repo, not per-PR** (stored in `~/.pr-autopilot/<owner>-<repo>-graphify-notice.flag`) so it doesn't re-fire on every new PR.
- **Strict mode (`advisory=always`):** PAUSE with actionable message if graph missing. Opt-in for teams that have decided "graph is mandatory."
- **Off (`advisory=off`):** Skip the check entirely. For repos that explicitly don't want graphify.

No auto-build. No cost surprises. pr-autopilot doesn't query the graph itself; it nudges Claude (the loop driver) and dispatched subagents to use it.

**Sharing model (Option A, decided 2026-05-28):**

Recipe `docs/recipes/graphify-team-setup.md` documents the canonical sharing pattern:

1. Commit `graphify-out/graph.json` to the repo (portable per Asistel 2026-05-28 verification — relative paths only, no `*_API_KEY` patterns detected by recipe step 4 scan)
2. `.gitignore` uses **whitelist pattern** (per iter1 P0-4): `graphify-out/*` + `!graphify-out/graph.json` — defends against future graphify version adding new artifacts
3. `.gitattributes`: `graphify-out/graph.json merge=graphify-merge linguist-generated=true` — registers merge driver + hides diff in GitHub PRs (lockfile-style; per iter1 P1-6)
4. **Manual setup per clone** (graphify v0.8.22 `hook install` does NOT auto-register merge driver per iter1 P1-2; verified against `safishamsi/graphify@v0.8.22` source): `git config merge.graphify-merge.driver "graphify merge-driver %O %A %B"`
5. **Post-commit hook** (matches upstream graphify hook model per iter1 P1-1, NOT pre-commit): `graphify update . 2>/dev/null || true; git add graphify-out/graph.json 2>/dev/null || true`. Graceful degrade by design — never blocks user's commit.
6. Mandatory pre-commit secret scan (per iter1 P1-6): added to recipe for ongoing protection beyond initial portability check

Result: teammates pull → graph current. Commit code → post-commit hook updates graph for next commit. Merge conflicts on graph.json → resolved by union-merge driver if both clones have driver configured; otherwise teammate sees explicit guidance from pre-flight 0.4b warning.

---

## 4. Co dodajemy

| Plik | Status | Cel |
|---|---|---|
| `skills/step/SKILL.md` | MODIFY | Pre-flight check 0.4b (filesystem-only); §0.5 Load State migration v3→v4 + new state fields; §10 triage **preamble** hint (NOT subagent prompt — corrects iter1 P0-5); stop conditions table extension; Mode X step 5.5 `@copilot` comment body augmentation. |
| `skills/review-spec/SKILL.md` | MODIFY | Adapter prompt templates (Step 2) gain a graphify hint line via **dispatch-time filesystem check** (NOT state lookup — bootstrap mode has no PR state per iter1 P0-4). |
| `skills/assign/SKILL.md` | MODIFY | Pre-flight equivalent: **always advisory, never PAUSE** (per iter1 P0 #1) — even broken-folder case generates INFO, not PAUSE. Filesystem-only check, no claim file state interaction. |
| `docs/recipes/graphify-team-setup.md` | NEW | Recipe for Option A sharing model: gitignore whitelist + gitattributes (merge + linguist-generated) + manual merge driver config + **post-commit** hook + secret scan + Windows PowerShell variant for portability regex. |
| `EVAL.md` | MODIFY | Scenario 26 (happy path, graph present), 26b (auto + missing → INFO once + continue), 26c (always + missing → PAUSE), 26d (broken folder + step → PAUSE with rebuild message), 26e (always + broken → PAUSE; `advisory=off` + missing → silent pass), 26f (graphify CLI installed but absent from PATH at subagent invocation → subagent falls back to grep gracefully). |
| `README.md` | MODIFY | One-paragraph "Code knowledge graph awareness" subsection; **explicit Mode Y carve-out** (per iter1 P1-8: hint reaches subagents + `@copilot` comment body, but SWE Agent's internal prompt can't be modified). Token-reduction claim labeled "expected; not yet measured." |
| `.claude-plugin/plugin.json` | MODIFY | Bump `"version": "0.5.2"` → `"0.5.3"`. |
| `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.3-graphify-integration.md` | NEW (this file) | Spec, iter2. |

**Out of scope (v0.5.3):**

- `--force-graphify` flag
- Auto-build of missing graph by pr-autopilot
- Subagent graph-excerpt injection (hint only)
- `graphify.minimumStaleness` (defer to v0.5.4; placeholder in §6.1)
- SWE Agent direct prompt injection (Mode Y limitation; v0.5.3 only adds `@copilot` comment body augmentation)
- Multi-repo graph merging
- ExoVault integration to store graphs centrally

---

## 5. Wymagania funkcjonalne

### 5.1 Pre-flight check 0.4b (Mode X step)

**Critical fix from iter1 P0 #3** (pseudocode placed before state load but used state): the check is split into two parts that run in different positions:

- **§5.1a (pre-state-load filesystem check, runs at position 0.4b)** — touches NO state, only sets a local variable `_graphifyFsState`.
- **§5.1b (post-state-load state setting + notifications, runs immediately after §0.5 Load State, as new §0.5a)** — reads `_graphifyFsState`, applies migration, sets state, emits notifications.

#### §5.1a — at 0.4b, BEFORE §0.5 Load State

```bash
# 0.4b — graphify filesystem detection (NO state interaction)
if [ -f "graphify-out/graph.json" ]; then
  _graphifyFsState="present"
elif [ -d "graphify-out" ]; then
  _graphifyFsState="broken"   # folder exists but no graph.json — last build failed
else
  _graphifyFsState="absent"
fi

# Detect merge driver gap (iter1 P0 #5 — proactive warning)
# Only check if .gitattributes references graphify-merge AND driver isn't locally configured
if [ -f .gitattributes ] && grep -q 'graphify-merge' .gitattributes 2>/dev/null; then
  if ! git config --get merge.graphify-merge.driver >/dev/null 2>&1; then
    _graphifyMergeDriverMissing="true"
  fi
fi
```

#### §5.1b — at new §0.5a, AFTER §0.5 Load State

```python
# 0.5a — graphify state setting + advisory notifications (REQUIRES state to be loaded)

cfg_advisory = config.graphify.advisory  # "auto" (default) | "always" | "off"

# advisory=off — short-circuit, NO state interaction beyond ensuring no stale flag persists
if cfg_advisory == "off":
  state.graphifyAvailable = false
  # fall through to next pre-flight step; nothing else to do
else:
  # advisory in {auto, always} — apply filesystem state

  if _graphifyFsState == "present":
    state.graphifyAvailable = true
    state.graphifyBuiltAtCommit = jq -r '.built_at_commit // empty' graphify-out/graph.json
    # graphifyBuiltAtCommit MAY be empty in v0.5.3 — graphify writes it but value is empty {} on some builds (iter1 verification)
    # v0.5.4 will add `minimumStaleness` config that uses this field; v0.5.3 only persists for forward-compat

  elif _graphifyFsState == "broken":
    state.graphifyAvailable = false
    PushNotification("PR #${prNumber} PAUSED — graphify build incomplete", "graphify-out/ exists but graph.json is missing (last `graphify extract` may have failed). Run `graphify extract . --backend deepseek` to rebuild, then re-run /pr-autopilot:step ${prNumber}.")
    saveState($STATE_FILE)
    return  # PAUSE; KEEP state

  else:  # _graphifyFsState == "absent"
    state.graphifyAvailable = false
    if cfg_advisory == "always":
      PushNotification("PR #${prNumber} PAUSED — graphify required but missing", "graphify.advisory=always but no graphify-out/graph.json found. Run `/graphify .` first (~$0.05-0.15 via DeepSeek), commit graphify-out/graph.json, re-run /pr-autopilot:step ${prNumber}. To disable strict mode set graphify.advisory=auto in ~/.claude/settings.json.")
      saveState($STATE_FILE)
      return  # PAUSE; KEEP state
    else:  # advisory == "auto"
      # Per-repo notice flag (NOT per-PR — fixes iter1 P1-12 "scope is wrong")
      OWNER=$(gh repo view --json owner --jq '.owner.login')
      REPO=$(gh repo view --json name --jq '.name')
      NOTICE_FLAG="$HOME/.pr-autopilot/${OWNER}-${REPO}-graphify-notice.flag"
      if [ ! -f "$NOTICE_FLAG" ]; then
        PushNotification("INFO: graphify recommendation", "This repo has no graphify code knowledge graph. Subagents will fall back to grep + file reads. To enable token reduction: run `/graphify .` once (~$0.05-0.15 via DeepSeek), commit graphify-out/graph.json + .gitattributes. See https://github.com/MarcinSufa/claude-pr-autopilot/blob/main/docs/recipes/graphify-team-setup.md")
        touch "$NOTICE_FLAG"
      fi
      # fall through; loop continues normally

# Merge driver detection (independent advisory — applies even when graphify is enabled+present)
if _graphifyMergeDriverMissing == "true" AND NOT state.graphifyMergeDriverWarningShown:
  PushNotification("ADVISORY: graphify merge driver not configured", ".gitattributes references graphify-merge but `git config --get merge.graphify-merge.driver` is empty. Future merge conflicts on graph.json will fail cryptically. Run: git config merge.graphify-merge.driver \"graphify merge-driver %O %A %B\"")
  state.graphifyMergeDriverWarningShown = true
  saveState($STATE_FILE)
```

**State schema bump v3 → v4** (per iter1 P0 #2 + iter1 P1-5):

Add to the "Key changes" subsection of `skills/step/SKILL.md` (line ~261-271):

> - `stateSchemaVersion: 4` (v0.5.3) — additive fields: `graphifyAvailable: false`, `graphifyBuiltAtCommit: ""`, `graphifyMergeDriverWarningShown: false`. Migration: a v3 state file loads with all four fields defaulted (`false`/`""`); no fresh start needed. Per-repo notice flag at `$HOME/.pr-autopilot/<owner>-<repo>-graphify-notice.flag` is independent of per-PR state. The `state.stateSchemaVersion is None` Mode-Y ABORT guard (Y.0.5) is unaffected since v3→v4 is additive only.

### 5.1c — Variant for `/pr-autopilot:assign` (ALWAYS ADVISORY, NEVER PAUSE)

**Critical fix from iter1 P0 #1** (assign violates "never blocks claim file creation" contract):

In `skills/assign/SKILL.md`, BEFORE creating the claim file:

```bash
# Filesystem check only — assign uses an INFO notification for ANY graphify state, never PAUSE
if [ -f "graphify-out/graph.json" ]; then
  : # silent; no notification
elif [ -d "graphify-out" ]; then
  echo "[INFO] graphify-out/ exists but graph.json missing. Run 'graphify extract .' to rebuild for token-reduction benefits during /pr-autopilot:step. (advisory only; claim file will be created.)"
else
  # Honor per-repo notice flag (same flag as /step uses; if /step already INFO'd, /assign stays silent)
  OWNER=$(gh repo view --json owner --jq '.owner.login')
  REPO=$(gh repo view --json name --jq '.name')
  NOTICE_FLAG="$HOME/.pr-autopilot/${OWNER}-${REPO}-graphify-notice.flag"
  if [ ! -f "$NOTICE_FLAG" ]; then
    echo "[INFO] This repo has no graphify code knowledge graph. Run /graphify . once for token reduction during PR review loops. (advisory only.)"
    touch "$NOTICE_FLAG"
  fi
fi

# Continue claim file creation regardless — graphify state never blocks /assign
```

### 5.1d — Variant for `/pr-autopilot:review-spec` (DISPATCH-TIME FILESYSTEM CHECK, NO STATE)

**Critical fix from iter1 P0 #4** (`/review-spec` bootstrap has no per-PR state file):

In `skills/review-spec/SKILL.md`, just before "Step 2 — dispatch sync adapters in parallel":

```bash
# Filesystem check at dispatch time — NO state file in /review-spec
if [ -f "graphify-out/graph.json" ] && [ "${config_graphify_promptHint:-true}" = "true" ]; then
  _graphifyHintEnabled="true"
else
  _graphifyHintEnabled="false"
fi
```

This `_graphifyHintEnabled` is consumed by the prompt templates in §5.2.

### 5.2 Subagent prompt + main-loop hint injection

**Critical fix from iter1 P0 #5** (Step 10 triage is in-process loop driver, NOT subagent dispatch). Hint goes into THREE distinct injection points:

#### A) `/review-spec` adapter prompt templates (REAL subagent dispatch)

When `_graphifyHintEnabled == "true"` (set in §5.1d), prepend the following to each adapter prompt in `skills/review-spec/SKILL.md` (claude-code-reviewer-subagent + claude-self-review templates):

```
**Code knowledge graph available:** This repo has a graphify-built knowledge graph at
`graphify-out/graph.json`. BEFORE grep'ing for symbols or reading source files, query
the graph: `graphify explain "<symbol>"` returns the node + connections + community
in ~1-3k tokens vs ~30-100k for a multi-file grep. Use `graphify path "A" "B"` for
dependency-trace. If `graphify` errors with "command not found" (CLI not installed
locally), fall back to grep + Read without retrying graphify.
```

**Placement note (per iter1 P1-7 "prepend > append" critique):** The hint is placed BEFORE the task description, not at the end. Anthropic's documented recommendation for long contexts is to place instructions at the END (recency); for short subagent prompts (~150 tokens), placement effect is empirically uncertain. We use prepend by default; if iter3+ A/B testing shows append is more reliable for this prompt shape, swap via `graphify.promptHintPosition` config (added in that revision).

#### B) `/pr-autopilot:step` Mode X step 10 triage **preamble** (in-process main-loop driver)

When `state.graphifyAvailable == true`, modify Step 10 in `skills/step/SKILL.md` to insert a preamble line at the start of the triage section, BEFORE invoking `REVIEW-TRIAGE-COPY.md`:

```
**Pre-triage note (v0.5.3+):** This repo has a graphify code knowledge graph at
`graphify-out/graph.json`. When judging whether a reviewer comment about symbol X is
valid, query `graphify explain "X"` first to see X's connections/community; query
`graphify path "X" "Y"` for dependency-validity questions. Only `Read` source files
when graphify returns insufficient context.
```

This is consumed by Claude (the loop driver), NOT a dispatched subagent.

#### C) Mode X step 5.5 `@copilot` comment body augmentation (Mode Y fixer hint via Copilot SWE Agent)

**Critical fix from iter1 P1-8** (Mode Y was abandoned; SWE Agent reads PR comments). When `state.graphifyAvailable == true` and triggering `@copilot please review`, append the following to the comment body posted via `gh pr comment`:

```
P.S. This repo has a code knowledge graph at `graphify-out/graph.json`. Prefer
`graphify explain "<symbol>"` over grep when investigating symbols.
```

Three sentences, ~30 tokens. If SWE Agent reads PR comments (documented behavior for issue-comment-triggered runs), the hint reaches Copilot's primary fixer path.

### 5.3 Config schema (revised per iter1)

Add to `~/.claude/settings.json` `prAutopilot` block:

```json
"graphify": {
  "advisory": "auto",
  "promptHint": true
}
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `advisory` | enum `"auto" \| "always" \| "off"` | `"auto"` | Three explicit modes. `auto` = check + INFO once per repo if missing, continue. `always` = check + PAUSE if missing. `off` = skip the check entirely (no notifications, no state interaction beyond ensuring `state.graphifyAvailable=false`). |
| `promptHint` | bool | `true` | Whether to prepend the graphify hint to `/review-spec` subagent prompts AND to `/step` step 10 preamble. Set `false` to disable instruction injection but keep the pre-flight detection (mainly useful for power users measuring baseline-vs-hinted behavior). |

**Per iter1 P1-4:** `minimumStaleness` is REMOVED from v0.5.3. Defer to v0.5.4 when staleness-checking infrastructure is designed (requires git ancestry checks against `built_at_commit`, which can be empty `""` in current graphify builds).

**Per iter1 P1 (config inconsistency with cursor/copilot):** The `enabled=true|false` pattern used by other reviewers doesn't fit here — graphify is detected from filesystem (`graph.json` exists or doesn't), not declared in config. The `advisory` enum names the policy applied to that detection. Documented intentional deviation.

### 5.4 Recipe doc: `docs/recipes/graphify-team-setup.md`

**Revised per iter1 P0 #4 (gitignore), P0 #5 (hook failure handling), P1-1 (post-commit upstream alignment), P1-2 (merge driver NOT auto-installed), P1-6 (security), P1-9 (regex portability), P1-11 (husky append).**

Step-by-step adoption guide. Outline (numbers reused for traceability):

1. **Install graphify CLI** (uv tool install graphifyy + DEEPSEEK_API_KEY or other supported backend in user env)
2. **First-time build**: `graphify extract . --backend deepseek` (~$0.05-0.15, ~90s for ~200-file repo)
3. **Verify portability (bash):**
   ```bash
   jq -r '.. | strings? | select(test("^[A-Z]:\\\\|^/home/|^/Users/"))' graphify-out/graph.json | head -3
   ```
   **Expected: no output.** If any line prints, your graph contains absolute paths — file an issue at graphify repo.

   **Windows PowerShell variant:**
   ```powershell
   jq -r '.. | strings? | select(test(\"^[A-Z]:\\\\\\\\|^/home/|^/Users/\"))' graphify-out/graph.json | Select-Object -First 3
   ```

4. **Verify secret-cleanness (initial portability check, NOT a substitute for ongoing scans):**
   ```bash
   jq -r '.. | strings? | select(test("^(sk-|ghp_|gho_|github_pat_|AKIA|eyJ[A-Za-z0-9_-]+)"))' graphify-out/graph.json | head -3
   ```
   **Expected: no output.** Note: this regex is a coarse first pass. It does NOT detect JWT without `eyJ` prefix, raw Bearer tokens, connection strings, or PEM blocks. ADD a mandatory git-secrets / gitleaks pre-commit scan per step 8.

5. **Update `.gitignore`** — use **WHITELIST pattern** (defensive against future graphify version adding new artifact types):
   ```gitignore
   graphify-out/*
   !graphify-out/graph.json
   ```
   This excludes `graphify-out/cache/`, `graphify-out/manifest.json`, `graphify-out/.graphify_analysis.json`, `graphify-out/.graphify_semantic_marker`, `graphify-out/2026-*/`, and any future per-machine artifacts — only `graph.json` itself is committed.

6. **`.gitattributes`** — register both the merge driver and lockfile-style diff hiding:
   ```gitattributes
   graphify-out/graph.json merge=graphify-merge linguist-generated=true
   ```
   The `linguist-generated=true` directive tells GitHub to auto-collapse the diff in PR reviews (same mechanism as `package-lock.json`).

7. **Install local merge driver** (REQUIRED per clone; graphify v0.8.22 `hook install` does NOT do this — verified against safishamsi/graphify@v0.8.22 source):
   ```bash
   git config merge.graphify-merge.driver "graphify merge-driver %O %A %B"
   ```
   **Onboarding note for teammates:** include this in your repo's onboarding checklist. pr-autopilot v0.5.3+ detects this gap via §5.1a `_graphifyMergeDriverMissing` check and warns proactively.

8. **Post-commit hook** (matches upstream graphify hook model per iter1 P1-1):

   **Fresh install** (no existing hook):
   ```bash
   # .git/hooks/post-commit (chmod +x)
   #!/usr/bin/env bash
   # Refresh graphify graph after every commit (incremental, no LLM, ~1-3s)
   # Graceful degrade: never block the commit flow (post-commit can't anyway)
   graphify update . >/dev/null 2>&1 || true
   if ! git diff --quiet HEAD -- graphify-out/graph.json 2>/dev/null; then
     # graph.json changed — stage + amend to include it in the current commit
     # (post-commit amend; teammate sees one combined commit, not a fixup)
     git add graphify-out/graph.json && git commit --amend --no-edit --no-verify >/dev/null 2>&1 || true
   fi
   ```

   **Husky append** (existing husky setup with `.husky/post-commit`):
   ```bash
   # Append to .husky/post-commit
   cat >> .husky/post-commit <<'EOF'
   graphify update . >/dev/null 2>&1 || true
   if ! git diff --quiet HEAD -- graphify-out/graph.json 2>/dev/null; then
     git add graphify-out/graph.json && git commit --amend --no-edit --no-verify >/dev/null 2>&1 || true
   fi
   EOF
   ```

   **Why post-commit not pre-commit:** Upstream graphify v0.8.22 uses post-commit hook (verified in `safishamsi/graphify` source). Post-commit is decoupled — never blocks the user's commit. Pre-commit would block on graphify CLI errors / parse errors / PATH issues.

   **Why `--no-verify` on the amend:** prevents recursive post-commit hook firing on the amend itself.

   **MANDATORY security companion** (per iter1 P1-6): add a SEPARATE pre-commit hook that scans the staged diff for secrets using `gitleaks` or `git-secrets`. The graphify hook updates graph.json AFTER the user's content commits; secret scanning must happen BEFORE that content lands. Document both hooks together; never bundle them.

9. **Initial commit**:
   ```bash
   git add graphify-out/graph.json .gitignore .gitattributes
   git commit -m "chore: add graphify code knowledge graph (initial build)"
   ```

10. **Teammate onboarding** — one-time per clone:
    - `uv tool install graphifyy` (CLI; needed for merge driver + post-commit hook)
    - `git config merge.graphify-merge.driver "graphify merge-driver %O %A %B"` (manual; not in `.gitattributes`)
    - Set `DEEPSEEK_API_KEY` (or other supported backend) in user env scope — only needed for explicit full re-extract via `graphify extract . --backend deepseek`; `graphify update .` (post-commit hook) is free.

The recipe is **decoupled from pr-autopilot** — useful for any team adopting graphify even without pr-autopilot.

### 5.5 Mode Y / Copilot SWE Agent integration

**Revised per iter1 P1-8:** Mode Y is NOT abandoned. SWE Agent reads PR comments (documented behavior). v0.5.3 adds two Mode-Y-applicable hints:

1. **Repo `AGENTS.md` recommendation** — recipe (§5.4) Step 11 (new): "If your repo uses Copilot SWE Agent (Mode Y in pr-autopilot config OR direct GitHub Copilot usage), add to your repo's `AGENTS.md` or `CLAUDE.md`: `'This repo has a graphify code knowledge graph at graphify-out/graph.json. Prefer `graphify explain "<symbol>"` over grep when investigating symbols.'`" — SWE Agent will read this on PR-trigger.

2. **`@copilot` comment body augmentation** — pr-autopilot Mode X step 5.5 + Mode Y trigger comments append a P.S. hint when `state.graphifyAvailable == true` (per §5.2 part C).

**True SWE Agent internal-prompt modification remains out-of-control** (GitHub's SDK; v0.5.3 cannot directly inject into SWE Agent's reasoning). README explicit Mode Y carve-out (per iter1 P1-8 README oversell).

### 5.6 Stop conditions (revised)

| Condition | Step | Outcome |
|---|---|---|
| `advisory=off` AND any filesystem state | 0.4b/0.5a | PASS (no notification, `state.graphifyAvailable=false`) |
| `advisory=auto` AND `graph.json` present | 0.4b/0.5a | PASS (silent, `state.graphifyAvailable=true`) |
| `advisory=auto` AND `graph.json` absent (no folder) | 0.5a | INFO once per repo (notice flag), continue |
| `advisory=auto` AND `graphify-out/` exists but no `graph.json` (broken) | 0.5a | PAUSE (KEEP state, rebuild message) |
| `advisory=always` AND `graph.json` absent | 0.5a | PAUSE (KEEP state, strict-mode message) |
| `advisory=always` AND broken folder | 0.5a | PAUSE (KEEP state, rebuild message) |
| `.gitattributes` has graphify-merge AND driver not configured | 0.5a | ADVISORY once per repo (via separate flag), continue |

**Update existing "Stop conditions summary" table** in `skills/step/SKILL.md` line 1029-1056 with the rows above.

### 5.7 README change (revised — Mode Y carve-out + claim toned down)

Add a paragraph under "How it works":

> **Code knowledge graph awareness (v0.5.3+):** If your repo has a graphify-built knowledge graph at `graphify-out/graph.json`, pr-autopilot's dispatched `/review-spec` subagents and the in-loop `/step` triage will prefer querying the graph over grep'ing source files for symbol-lookup questions. When Mode X triggers Copilot Code Review (step 5.5), the `@copilot` comment includes a graphify P.S. hint. **Mode Y limitation:** Copilot SWE Agent's internal prompt is GitHub-controlled — pr-autopilot can only nudge it via the `@copilot` comment body and the recipe's `AGENTS.md` snippet, not directly modify SWE Agent's reasoning. Token reduction is **expected; not yet measured** — see EVAL scenario 26 for the planned baseline measurement. Setup recipe: [Graphify team setup](docs/recipes/graphify-team-setup.md).

---

## 6. Edge cases + open questions (revised)

### 6.1 Graph staleness vs HEAD

`state.graphifyBuiltAtCommit` is persisted in v0.5.3 state for forward-compat. v0.5.4 will add `graphify.minimumStaleness` config that uses `git merge-base --is-ancestor <built_at_commit> HEAD` for real ancestry checks. **In v0.5.3, staleness is not checked.** Recipe's post-commit hook is the freshness mechanism.

### 6.2 Worktree + assign edge case (iter1 P1-9)

`/assign` creates worktree from `origin/main`. If `graphify-out/graph.json` was committed AFTER the worktree-base commit, the worktree won't have it. Pre-flight 0.5a checks the WORKTREE root (current CWD). Mitigation: recipe step 9 ("initial commit") MUST be done before `/assign` workflows; if not, the assign worktree will INFO ("no graph") but main has one — minor UX confusion, acceptable for v0.5.3. Documented in recipe.

### 6.3 graphify CLI missing on user's machine

Subagent hint says `graphify explain X` — if CLI not installed, errors with exit 127. The hint explicitly says "fall back to grep + Read without retrying graphify." EVAL scenario 26f tests this fallback.

### 6.4 Mode Y limitation (revised — now partial)

v0.5.3 provides TWO Mode Y hint paths (`AGENTS.md` snippet via recipe + `@copilot` comment body augmentation via §5.2 C). Neither modifies SWE Agent's internal prompt — that remains out of scope. Documented in README + recipe.

### 6.5 graph.json grows over time

Recipe documents `linguist-generated=true` in `.gitattributes` for GitHub PR diff collapsing. Per iter1 P2 #8 + adversarial P1-10 critique: **no hard file-count threshold given**. Recommend: `ls -lh graphify-out/graph.json` periodically; consider LFS if it exceeds ~50MB (real measurement, not extrapolation).

### 6.6 Pre-commit hook conflicts with existing hooks

Recipe step 8 shows BOTH fresh-install AND husky-append patterns explicitly (iter1 P1-11 fix). The recipe uses **post-commit** (not pre-commit) per iter1 P1-1, matching upstream graphify v0.8.22 hook model.

### 6.7 graphify merge driver requires graphify CLI installed locally

Recipe step 7 marks merge driver setup as REQUIRED PER CLONE. Pre-flight 0.5a detects the gap (`_graphifyMergeDriverMissing`) and warns ONCE per repo via separate flag `state.graphifyMergeDriverWarningShown`.

### 6.8 graph.json security across versions (iter1 P1-6 NEW)

Future graphify versions may add fields (semantic enrichment text from comments/docstrings, MCP config labels, etc.) that could leak content. Recipe MANDATES:
- One-time pre-commit secret scan (recipe step 4 regex is a coarse first pass, NOT exhaustive)
- ONGOING gitleaks/git-secrets pre-commit hook (separate from graphify hook; documented in recipe step 8)
- "Rotate if leaked" playbook in recipe step 12 (new — link to your team's secret-rotation runbook)

The spec does NOT claim "perpetually secret-clean" — the user's secret-scanning hygiene is the load-bearing defense, not the spec.

---

## 7. Test plan (EVAL.md scenarios — revised + expanded per iter1 P1-7)

**Scenario 26 — happy path, graph present**
- Setup: Asistel-like repo with `graphify-out/graph.json` committed. Config defaults.
- Expected: 0.4b sets `_graphifyFsState=present`; 0.5a sets `state.graphifyAvailable=true`, silent; subagent prompts include hint; Mode X step 5.5 `@copilot` comment includes P.S.

**Scenario 26b — `advisory=auto` (default), graph missing**
- Setup: PR in repo without `graphify-out/`. Config defaults.
- Expected: 0.5a sets `state.graphifyAvailable=false`; per-repo notice flag created at `$HOME/.pr-autopilot/<owner>-<repo>-graphify-notice.flag`; INFO notification fires ONCE; loop continues; subagent prompts do NOT include hint.

**Scenario 26b-bis — `advisory=auto`, graph missing, second PR same repo**
- Setup: same repo as 26b, second PR opened, flag exists from 26b.
- Expected: 0.5a does NOT re-notify (flag present); loop continues; subagent prompts do NOT include hint.

**Scenario 26c — `advisory=always`, graph missing**
- Setup: PR in repo without `graphify-out/`. Config: `graphify.advisory=always`.
- Expected: 0.5a PAUSEs with actionable message; KEEP state.

**Scenario 26d — broken folder (graphify-out/ exists, no graph.json), in /step**
- Setup: PR in repo with `graphify-out/cache/` but no `graphify-out/graph.json`.
- Expected: 0.5a PAUSEs with rebuild message regardless of `advisory` setting.

**Scenario 26e — `advisory=off`**
- Setup: PR in repo WITHOUT `graphify-out/`. Config: `graphify.advisory=off`.
- Expected: 0.5a sets `state.graphifyAvailable=false`, no notification, loop continues normally, subagent prompts do NOT include hint.

**Scenario 26f — graph committed, CLI not installed locally**
- Setup: PR in repo with `graphify-out/graph.json` but teammate hasn't run `uv tool install graphifyy`.
- Expected: 0.5a passes (file present); subagent gets hint; subagent's `graphify explain X` call errors with exit 127; subagent falls back to grep + Read; review proceeds.

**Scenario 26g — merge driver gap detection**
- Setup: PR in repo with `.gitattributes` containing `graphify-merge` but `git config merge.graphify-merge.driver` not set.
- Expected: 0.5a sets `state.graphifyMergeDriverWarningShown=true`, ADVISORY notification fires ONCE; loop continues.

**Scenario 26h — `/assign` with broken folder**
- Setup: Run `/pr-autopilot:assign <id>` in repo with `graphify-out/cache/` but no `graphify-out/graph.json`.
- Expected: INFO message printed (NOT PAUSE), claim file created normally. Per iter1 P0 #1 ("assign never blocks").

Each scenario gated for v0.5.3 release.

---

## 8. Risks + open questions for review (revised)

| # | Risk | Mitigation in spec | Open question? |
|---|---|---|---|
| R1 | Subagent ignores hint, still greps | EVAL scenario 26f tests fallback explicitly; hint also gives explicit fall-back instruction | Low |
| R2 | Recipe drifts from upstream graphify | Pinned to v0.8.22 verified against source (NOT just changelog per iter1 P1-2) | Low |
| R3 | Teammate-without-CLI hits merge driver gap | Pre-flight 0.5a detects + warns proactively (§5.1b) per iter1 P0 #5 | Mitigated |
| R4 | Post-commit hook is silent on graphify CLI errors | `|| true` graceful degrade is intentional; recipe documents the trade-off | Low |
| R5 | Subagent's graphify call fails silently | EVAL 26f explicit; hint includes fall-back instruction | Mitigated |
| R6 | graph.json diff noise in PR reviews | `linguist-generated=true` in `.gitattributes` (recipe step 6) — GitHub auto-collapses | Resolved |
| R7 | graph.json secrets across versions | Recipe MANDATES ongoing gitleaks/git-secrets pre-commit + initial portability scan (§6.8) | Open — depends on user's secret hygiene |
| R8 | Mode Y SWE Agent ignores `@copilot` comment hint | Empirically unverified; v0.5.4 will measure by counting graphify invocations in SWE Agent comments | Open |
| R9 | iter1 cursor cloud token cost (1.5M) | v0.5.3 itself doesn't fix; logged as v0.5.4 candidate ("cursor cost reduction in `/review-spec`") | Open — separate spec |
| R10 | "Prepend > append" empirical uncertainty | §5.2 explicitly labels as default-with-future-flag; v0.5.4 may add `graphify.promptHintPosition` | Open — measurement plan in EVAL 26 baseline |

---

## 9. Open questions for the reviewer

1. **§5.1b state schema bump v3 → v4** — additive-only migration. Should the migration block be inserted inline at "Key changes from v0.1 state" subsection, or as a new "Migration v3 → v4" subsection mirroring how v0.4 documented its bump?
2. **§5.2 C `@copilot` comment body augmentation** — is appending a P.S. acceptable in the existing comment flow, or does it risk SWE Agent misinterpreting the augmentation as part of the trigger directive? Recommend low-risk; verify empirically in EVAL.
3. **§5.4 step 8 post-commit `--amend`** — the auto-amend pattern is contentious. Alternative: emit a "graphify update available; run `git commit --amend` to include" message and let user opt in. Recommend auto-amend with `--no-verify` for minimum friction; reviewer should validate.
4. **§6.8 security boundary** — is "user's gitleaks hygiene is the load-bearing defense" an acceptable shipped position, or should v0.5.3 ship its own pre-commit secret scan as part of the recipe?

---

## 10. Implementation order (unchanged from iter1)

1. **Iter2 spec review** — `/pr-autopilot:review-spec --bootstrap` (2 free Claude subagents only, skip cursor per token-cost concern).
2. **Skill changes** — apply edits per §5 to `skills/step/SKILL.md`, `skills/review-spec/SKILL.md`, `skills/assign/SKILL.md`.
3. **Recipe doc** — write `docs/recipes/graphify-team-setup.md` per §5.4 (8 steps + onboarding).
4. **EVAL scenarios** — add §7 scenarios (26 through 26h) to EVAL.md.
5. **README + plugin.json** — bump version, add subsection with Mode Y carve-out.
6. **Self-verify** — read each modified SKILL.md end-to-end checking the §5.1a (pre-load) vs §5.1b (post-load) split is consistent.
7. **Commit** — single conventional commit: `feat(v0.5.3): graphify code knowledge graph awareness`.
8. **PR** — open against main.
9. **Dogfood** — run `/pr-autopilot:step <PR#>` on the PR (pr-autopilot has no graphify graph yet, so this tests the `advisory=auto` "missing" path).
10. **Asistel adoption** — apply recipe steps to Asistel repo separately, commit + push the initial graphify-out/graph.json there.

---

## 11. References

- ExoVault memory `a9df909c` — original v0.5.3 graphify candidate
- ExoVault memory `fb285a18` — Marcin verbatim "yes do it for 0.5.3"
- ExoVault memory `ca13f9dd` — Asistel graphify build evidence
- [ADR 0002](../../decisions/0002-v0.5.3-cso-final-pass-deferred.md) — cso deferral pattern
- [ADR 0001](../../decisions/0001-v0.6-mcp-server-rejected.md) — MCP rejection
- graphify repo: <https://github.com/safishamsi/graphify> (MIT)
- graphify version pinned: `0.8.22` (verified against source at this tag, NOT just changelog)
- Local Asistel CLAUDE.md §"Code Knowledge Graph (graphify)" — adoption pattern documented
- **iter1 review findings (preserved as §A audit log below)**

---

## §A. Iter1 audit log

iter1 of this spec was reviewed by 3 channels on 2026-05-28 / 2026-05-29:

| Channel | Model | Time | Findings |
|---|---|---|---|
| feature-dev:code-reviewer | claude-opus-4-7 | 151s | 2 P0 / 5 P1 / 3 P2 |
| general-purpose adversarial | claude-opus-4-7 | 200s | 6 P0 / 6 P1 / 0 P2 |
| cursor-cloud-agent | composer-2.5 | ~5min, ~1.5M tokens | 5 P0 / 10 P1 / 7 P2 |

**Aggregate (deduplicated): 9 P0 / ~15 P1 / ~10 P2.**

iter2 addressed all 9 P0s and critical P1s:

| P0 | Source | Resolution |
|---|---|---|
| broken-folder PAUSE breaks /assign contract | feature-dev | §5.1c separated; /assign always advisory |
| state schema not bumped, fields undefined | feature-dev + adversarial (independent) | §5.1b explicit v3→v4 bump + migration block |
| §5.1 pseudocode placed before §0.5 Load State | cursor | Split into §5.1a (pre-load fs check) + §5.1b (post-load state setting) |
| §1/§3/§4/§5.1/§5.6/§7 contradictions on default | feature-dev + cursor | All references now align with `advisory=auto = INFO + continue` |
| §5.1 doesn't implement §5.3 config | cursor | §5.1b explicit pseudocode for all 3 advisory modes; promptHint applied in §5.2; minimumStaleness deferred to v0.5.4 |
| state.graphifyAvailable unusable in /review-spec + /assign | cursor | §5.1c (assign, fs-only) + §5.1d (review-spec, dispatch-time fs check) |
| Step 10 triage is in-process, not subagent | cursor | §5.2 B targets step 10 preamble (in-process); §5.2 A targets review-spec subagents |
| graphifyVersion field doesn't exist | adversarial | Replaced with `state.graphifyBuiltAtCommit` (real field per verification) |
| Recipe gitignore missing files | adversarial | Whitelist pattern: `graphify-out/*` + `!graphify-out/graph.json` |
| Merge driver no proactive detection | adversarial | §5.1a `_graphifyMergeDriverMissing` + 0.5a once-per-repo warning |

Critical P1 fixes applied: post-commit hook (matches upstream graphify v0.8.22), `linguist-generated=true` for diff hiding, hard `|| true` graceful degrade on hooks, husky-append shown explicitly, security recipe (initial + ongoing scans), Windows PowerShell regex variant, `@copilot` comment body Mode Y hint, 50-70% claim retracted.

Iter1 review outputs (full text) preserved in session transcript; this spec embodies the deltas.
