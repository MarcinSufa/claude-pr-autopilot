# Spec — claude-pr-autopilot v0.5.3 — graphify code knowledge graph integration

**Data:** 2026-05-28 (post-midnight; cso-deferral PR #8 merged at `a93a69f`)
**Branch:** `feat/v0.5.3-graphify-integration`
**Worktree:** `c:\Users\sufam\IdeaProjects\claude-pr-autopilot-graphify` (off `origin/main@a93a69f`)
**Spec autor:** claude_code (Opus 4.7 1M)
**Iteracja:** v1 (pre-review)
**Prior art:** ExoVault memories `a9df909c` (original v0.5.3 graphify candidate, deferred from v0.5.2), `fb285a18` (Marcin verbatim "yes do it for 0.5.3"), `ca13f9dd` (Asistel graphify build evidence 2026-05-28)
**Slot freed by:** [ADR 0002](../../decisions/0002-v0.5.3-cso-final-pass-deferred.md) (cso v0.5.3 deferred pending upstream gstack `--non-interactive` flag)

---

## 1. Cel (1 zdanie)

Dodać **opt-in graphify code knowledge graph awareness** w `/pr-autopilot:assign` i `/pr-autopilot:step` — pre-flight check sprawdza czy `graphify-out/graph.json` istnieje w repo, PAUSE z actionable message jeśli nie; subagent prompts w step 10 (triage) i `/review-spec` dispatch wzbogacone o "use `graphify explain <symbol>` before grep" instruction. Cel: 50-70% redukcja tokenów na symbol-lookup pytaniach w pr-autopilot loop.

---

## 2. Wersjonowanie

**v0.5.2 → v0.5.3 (PATCH).** Strictly additive:

- Nowy pre-flight check 0.4b (`graphify-out/` advisory) — gated on `graphify.enabled=true` config (default: **auto-detect** — enabled if `graphify-out/graph.json` exists in current repo)
- Modyfikacje subagent prompts w `/review-spec` (FREE Claude subagents) i `/step` triage (Mode X) — additive instruction lines, no behavior change for repos without graph
- New repo-setup recipe in `docs/recipes/graphify-team-setup.md` covering Option A sharing model (committed graph.json + git merge driver + pre-commit hook) — adoption guide for any pr-autopilot user

Single commit (cohesive feature, no granular revert value).

**v0.5.3 nie wprowadza:**
- `--force-graphify` flag (skreślony post-Marcin decyzja 2026-05-28 — graph committed to repo per Option A, więc zawsze obecny po `git pull`, brak potrzeby in-loop auto-build)
- Auto-build of missing graph by pr-autopilot (cost surprise = bad UX; user opt-in via `/graphify .` is clearer)
- Subagent graph-excerpt injection (just hint that graph exists; subagent decides what to query — avoids bloating prompts with full graph)

---

## 3. Główna zmiana

Pr-autopilot becomes **graph-aware**: if `graphify-out/graph.json` exists at repo root, the pre-flight passes silently and dispatched subagents are told "this repo has a knowledge graph — query it via `graphify explain <symbol>` before grep'ing files." If the file is missing, pre-flight PAUSEs (KEEP state) with an actionable message: "this repo has no knowledge graph — run `/graphify .` first (one-time, ~$0.05-0.15 via DeepSeek). Then re-run `/pr-autopilot:step <PR>`."

No auto-build. No cost surprises. The integration is **purely advisory awareness** — pr-autopilot doesn't query the graph itself; it just nudges Claude (the loop driver) and dispatched subagents to use it.

**Sharing model (Option A, decided 2026-05-28):**

The recipe `docs/recipes/graphify-team-setup.md` documents the canonical sharing pattern:
1. Commit `graphify-out/graph.json` to the repo (it's portable — relative paths only, verified secret-clean for Asistel 2026-05-28)
2. `.gitignore` excludes only `graphify-out/cache/` (per-machine AST cache) and `graphify-out/manifest.json` (mtime-sensitive)
3. `.gitattributes`: `graphify-out/graph.json merge=graphify-merge` — registers graphify's union-merge driver for graph.json conflicts
4. Local `git config merge.graphify-merge.driver "graphify merge-driver %O %A %B"` — installs the merge driver per-clone (also pre-commit hook installs it if missing)
5. Pre-commit hook (`.husky/pre-commit` or `.git/hooks/pre-commit`): `graphify update .` (free, no LLM, ~1-5s) refreshes the graph automatically on every code commit

Result: teammates pull → graph current. Commit code → graph updated by hook → captured in same commit. Merge conflicts on graph.json → resolved by union-merge driver automatically.

---

## 4. Co dodajemy

| Plik | Status | Cel |
|---|---|---|
| `skills/step/SKILL.md` | MODIFY | Nowy pre-flight check 0.4b (graphify advisory), §10 triage prompt enhancement, derivation table extension. |
| `skills/review-spec/SKILL.md` | MODIFY | Adapter prompt templates (Step 2 "Dispatch sync adapters") gain a graphify hint line; no behavior change if graph absent. |
| `skills/assign/SKILL.md` | MODIFY | Pre-flight equivalent: notify user "no graphify graph found, suggest running `/graphify .`" — advisory only, doesn't block claim file creation. |
| `docs/recipes/graphify-team-setup.md` | NEW | Recipe for adopting Option A sharing model on any repo: gitignore + gitattributes + merge driver + pre-commit hook + initial commit. |
| `EVAL.md` | MODIFY | Scenario 26: graph present → pre-flight passes, prompts include hint. Scenario 26b: graph missing → PAUSE with actionable message. Scenario 26c: graph stale (older than HEAD by N commits) → still passes (advisory only, freshness is the recipe's job). |
| `README.md` | MODIFY | One-paragraph "Code knowledge graph awareness" subsection under "How it works"; link to the recipe; note soft dep on graphify CLI. |
| `.claude-plugin/plugin.json` | MODIFY | Bump `"version": "0.5.2"` → `"0.5.3"`. |
| `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.3-graphify-integration.md` | NEW (this file) | Spec. |

**Out of scope (v0.5.3):**

- Auto-build of missing graph by pr-autopilot (cost surprise; users opt in via `/graphify .` themselves)
- Subagent graph-excerpt injection (just hint; subagent decides what to query)
- Integration with `/pr-autopilot:approve-spec`, `/pause`, `/resume`, etc. — only the high-traffic skills (`/step`, `/review-spec`, `/assign`) get the awareness
- Mode Y integration in `/step` — Mode Y subagent dispatch happens inside SWE Agent (Copilot), out of our control; we can't pass graphify hints to Copilot's SWE Agent
- Validation of graph freshness (e.g. "graph older than HEAD by 100 commits → warn") — relies on the recipe's pre-commit hook keeping it fresh; if hook isn't installed, that's a recipe-adoption issue, not pr-autopilot's job
- Multi-repo graph merging (`graphify merge-graphs`) — single-repo focus for v0.5.3
- ExoVault integration to store graphs centrally — Option C from sharing-model decision; deferred indefinitely

---

## 5. Wymagania funkcjonalne

### 5.1 Pre-flight check 0.4b (Mode X step + assign)

Insert AFTER existing 0.4 (PR exists) and BEFORE 0.5 (Load state) in `skills/step/SKILL.md`. Using suffix `0.4b` (not renumbering existing 0.5/0.6) per the lesson from ADR 0002 — renumbering creates downstream-reference drift.

```bash
# 0.4b — graphify code knowledge graph advisory (opt-in via auto-detection)
if [ -f "graphify-out/graph.json" ]; then
  state.graphifyAvailable = true
  # graphifyVersion captured for telemetry; not used to gate behavior
  state.graphifyVersion = $(jq -r '.metadata.version // "unknown"' graphify-out/graph.json 2>/dev/null || echo "unknown")
elif [ -d "graphify-out" ]; then
  # Folder exists but graph.json missing — cache from a failed build
  state.graphifyAvailable = false
  PushNotification("ADVISORY", "graphify-out/ exists but no graph.json — last build may have failed. Run `graphify extract . --backend deepseek` to rebuild, then re-run /pr-autopilot:step ${prNumber}.")
  saveState($STATE_FILE)
  return  # PAUSE (terminate; KEEP state for user to resume after fixing)
else
  state.graphifyAvailable = false
  # Don't PAUSE — graphify is genuinely optional; just inform on first occurrence
  if NOT state.graphifyNoticeShown:
    PushNotification("INFO", "This repo has no graphify code knowledge graph. Subagents will fall back to grep + file reads. To enable token-cost reduction, run `/graphify .` once (~$0.05-0.15 via DeepSeek), commit graphify-out/graph.json, re-run /pr-autopilot:step.")
    state.graphifyNoticeShown = true  # don't re-notify on every tick
    saveState($STATE_FILE)
  # Fall through — loop continues normally
fi
```

**Same check in `/pr-autopilot:assign`** — advisory notification only, NEVER blocks claim file creation (consistent with v0.5.0 assign behavior).

### 5.2 Subagent prompt enhancement (Mode X step 10 triage + /review-spec adapter prompts)

When `state.graphifyAvailable == true`, prepend the following line to every subagent's prompt (in `skills/step/SKILL.md` triage step 10 and `skills/review-spec/SKILL.md` "Adapter prompts" subsection):

```
**Code knowledge graph available:** This repo has a graphify-built knowledge graph at
`graphify-out/graph.json`. BEFORE grep'ing for symbols or reading source files, query
the graph: `graphify explain "<symbol>"` returns the node + its connections (callers,
callees, contained items, community) in ~1k tokens vs ~30-100k for a multi-file grep.
Use `graphify path "A" "B"` for dependency-trace questions. Use grep + Read only when
graphify returns insufficient context.
```

When `state.graphifyAvailable == false`, the line is omitted entirely (no instruction to the subagent).

**Why prepend, not append:** Claude tends to follow the first instruction in a prompt more reliably than the last. The hint must shape the exploration strategy from the start.

**Why no graph excerpt injection:** Injecting graph-derived context (e.g. "here are the top-10 symbols related to your task") would require pr-autopilot to itself query the graph and pick relevant slices — adds complexity, risks injecting wrong slices, bloats prompts. Letting the subagent decide what to query is simpler and more flexible.

### 5.3 Config schema

Add to `~/.claude/settings.json` `prAutopilot` block (all optional; defaults are sensible):

```json
"graphify": {
  "advisory": "auto",
  "minimumStaleness": null,
  "promptHint": true
}
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `advisory` | enum `"auto" \| "always" \| "off"` | `"auto"` | `auto` = check for `graphify-out/graph.json` per repo (current spec behavior). `always` = check + PAUSE if missing (stricter). `off` = skip the check entirely. |
| `minimumStaleness` | int (commits) \| null | `null` | If set, warns when `graph.json` mtime is older than HEAD by ≥N commits. Disabled by default — staleness handling is the recipe's job, not pr-autopilot's. |
| `promptHint` | bool | `true` | Whether to prepend the graphify hint to subagent prompts. Set `false` to disable instruction injection but keep the pre-flight check. |

### 5.4 Recipe doc: `docs/recipes/graphify-team-setup.md`

Step-by-step adoption guide. Outline:

1. **Install graphify CLI** (uv tool install graphifyy + DEEPSEEK_API_KEY in user env)
2. **First-time build**: `graphify extract . --backend deepseek` (~$0.05-0.15, ~90s)
3. **Verify portability**: `jq '.. | strings? | select(test("C:\\\\Users|/home/"))' graphify-out/graph.json | head -3` (should be empty — confirms no absolute path leakage before committing)
4. **Verify secret-cleanness**: `jq -r '.. | strings? | select(test("^(sk-|ghp_|gho_|AKIA|eyJ)"))' graphify-out/graph.json | head -3` (should be empty)
5. **Update `.gitignore`**: `graphify-out/cache/` + `graphify-out/manifest.json` only; remove `graphify-out/` blanket if present.
6. **Set up `.gitattributes`**: `graphify-out/graph.json merge=graphify-merge`
7. **Install local merge driver**: `git config merge.graphify-merge.driver "graphify merge-driver %O %A %B"` (per-clone, not committed)
8. **Pre-commit hook** (husky or raw `.git/hooks/pre-commit`): `graphify update .` + `git add graphify-out/graph.json` (free, no LLM)
9. **Initial commit**: `git add graphify-out/graph.json .gitignore .gitattributes && git commit -m "chore: add graphify code knowledge graph (initial build)"`
10. **Teammate onboarding**: documented one-time setup (uv install + DEEPSEEK_API_KEY for the rare case they trigger a full re-extract themselves; otherwise pre-commit hook keeps things current).

The recipe is **decoupled from pr-autopilot** — useful for any team that wants to share graphs even if they don't use pr-autopilot.

### 5.5 Mode Y / SWE Agent fixer

Mode Y (Copilot SWE Agent as primary fixer) dispatches via top-level `@copilot please review` comment. We cannot inject graphify hints into SWE Agent's prompt — it's controlled by GitHub. **Decision:** v0.5.3 only integrates Mode X. Mode Y graphify awareness deferred indefinitely; would require Copilot SDK changes we don't control.

Document this limitation in the spec (§6.4) and recipe.

### 5.6 Stop conditions

Add to "Stop conditions summary" in `skills/step/SKILL.md`:

| Condition | Step | Outcome |
|---|---|---|
| `graphify.advisory=always` AND `graphify-out/graph.json` missing | pre-flight 0.4b | PAUSE (KEEP state, actionable message) |
| `graphify-out/` exists but `graph.json` missing (last build failed) | pre-flight 0.4b | PAUSE (KEEP state, actionable rebuild message) |
| `graphify-out/graph.json` exists | pre-flight 0.4b | PASS (set `state.graphifyAvailable = true`) |
| `graphify-out/graph.json` missing AND `graphify.advisory=auto` | pre-flight 0.4b | INFO notification (once), continue normally |

### 5.7 README change

Add a paragraph under "How it works":

> **Code knowledge graph awareness (v0.5.3+):** if your repo has a graphify-built knowledge graph at `graphify-out/graph.json`, pr-autopilot's dispatched subagents (code-reviewer, adversarial, triage, etc.) will prefer querying the graph over grep'ing source files — estimated 50-70% token reduction on symbol-lookup questions. See [Graphify team setup](docs/recipes/graphify-team-setup.md) for the recommended way to share the graph across teammates.

---

## 6. Edge cases + open questions

### 6.1 Graph staleness vs HEAD

If the recipe's pre-commit hook is installed, `graph.json` updates with every commit. If not, the graph can drift. pr-autopilot v0.5.3 does NOT detect staleness by default (`minimumStaleness=null`). Rationale: false positives (graph "stale" relative to a feature branch that hasn't merged yet) would generate noise. Power users can opt in via `graphify.minimumStaleness=20` etc.

### 6.2 What if the user runs `/pr-autopilot:step` from a worktree?

pr-autopilot's pre-flight 0.2 already checks `git rev-parse --is-inside-work-tree`. Worktree CWD inherits `graphify-out/` only if the worktree was created AFTER `graphify-out/` was committed. For freshly created worktrees from PRs that pre-date the graphify-out commit, the graph won't be in the worktree but WILL be in the main repo. Edge case worth documenting in recipe ("create your worktree from a commit that includes graphify-out/").

### 6.3 graphify CLI missing on user's machine

The subagent hint refers to `graphify explain` — if the CLI isn't installed locally, the hint is useless. But the subagent runs IN THE USER'S SHELL (it's Claude dispatching via Bash tool), so the user's PATH applies. If `graphify` isn't installed, the subagent's `graphify explain X` call will error and the subagent should fall back to grep.

**Decision:** trust the subagent to handle the fallback. Don't pre-check `command -v graphify` in pr-autopilot — that would gate the prompt injection on a tool that subagent can already test for itself.

### 6.4 Mode Y limitation

Per §5.5: Mode Y can't be made graphify-aware in v0.5.3 because we don't control Copilot SWE Agent's prompt. If a user is on Mode Y (`copilotSwe.mode=each-iter`), `state.graphifyAvailable` is still set correctly but the subagent hint never reaches SWE Agent. **No code change needed** — just document the limitation in README + recipe.

### 6.5 graph.json grows over time — Asistel is 855KB now

Asistel at 241 code files = 855KB graph.json. Linear extrapolation: a 2,500-file repo (10x Asistel) = ~8.5MB. Still fine for git. At 25,000 files = 85MB → git LFS territory. For Asistel's scale + foreseeable team-size, plain git is fine. Note in recipe: "if your repo grows past ~5,000 source files, evaluate git LFS for graphify-out/graph.json."

### 6.6 Pre-commit hook conflicts with existing hooks

If a repo already has husky or other pre-commit infra, the recipe's `.husky/pre-commit` line needs to APPEND to the existing hook, not replace. Recipe covers both fresh-install and append-to-existing patterns.

### 6.7 graphify merge driver requires graphify CLI installed locally

The merge driver `graphify merge-driver %O %A %B` is invoked by git automatically during merges; if the user doesn't have graphify installed, the merge fails. Recipe step 1 (CLI install) is a hard prereq for teammates pulling the repo. Document loudly.

### 6.8 What if `graphify-out/graph.json` is committed but the user hasn't installed graphify?

Pre-flight 0.4b passes (file exists). Subagent gets the hint. Subagent's `graphify explain X` errors with "command not found." Subagent should fall back to grep — same behavior as 6.3.

**Stronger version (consider for v0.5.4):** check `command -v graphify` in pre-flight 0.4b. If file exists but CLI missing → ADVISORY notification "your repo has a committed graph but you don't have graphify installed locally — run `uv tool install graphifyy` for token savings." For v0.5.3, defer to keep scope tight.

---

## 7. Test plan (EVAL.md scenarios)

Add 3 new scenarios:

**Scenario 26 — graphify-aware happy path**

- Setup: PR in Asistel (which has `graphify-out/graph.json` committed). Config: defaults.
- Run `/pr-autopilot:step <N>`.
- Expected: pre-flight 0.4b sets `state.graphifyAvailable=true`, no notification, loop proceeds. When triage step 10 dispatches subagents to read review threads, the subagent prompt includes the graphify hint.

**Scenario 26b — graphify missing, advisory mode (default)**

- Setup: PR in a repo WITHOUT `graphify-out/graph.json`. Config: defaults (`advisory=auto`).
- Run `/pr-autopilot:step <N>`.
- Expected: pre-flight 0.4b sets `state.graphifyAvailable=false`, INFO notification on first tick only, loop proceeds normally. Subagent prompts do NOT include the graphify hint.

**Scenario 26c — graphify required, missing**

- Setup: PR in a repo WITHOUT `graphify-out/graph.json`. Config: `graphify.advisory=always`.
- Run `/pr-autopilot:step <N>`.
- Expected: pre-flight 0.4b PAUSEs with actionable message ("run `/graphify .` first"), no further dispatch, state preserved.

**Scenario 26d — broken graphify build (cache present, graph.json missing)**

- Setup: PR in a repo with `graphify-out/cache/` but no `graphify-out/graph.json`. Config: defaults.
- Expected: pre-flight 0.4b PAUSEs with rebuild message, regardless of `advisory` setting (broken state is always bad).

Each scenario gated for v0.5.3 release.

---

## 8. Risks + open questions for review

| # | Risk | Mitigation in spec | Open question? |
|---|---|---|---|
| R1 | Subagent ignores the prompt hint and still greps | Hint is prepended (Claude follows opening instructions more reliably). Acceptable degradation if ignored — same as no-graphify baseline. | Low — worst case = no savings, not regression |
| R2 | Recipe steps drift from upstream graphify (e.g. merge-driver command changes) | Recipe links to graphify version; pinning to ≥0.8.22 known-good | Low — graphify is stable |
| R3 | Asistel teammates pull but don't install graphify CLI → merge driver fails on conflicts | Recipe step 1 (CLI install) marked HARD PREREQ; document the merge failure mode | Medium — affects daily teammate workflow |
| R4 | Pre-commit hook slows commits too much (graphify update >5s) | Empirical: Asistel `graphify update .` is 1-3s (AST-only). For larger repos: recipe documents how to skip the hook on docs-only commits via `git diff --cached --name-only \| grep -qE '^src/'` guard | Low |
| R5 | Subagent's `graphify explain` call fails silently and subagent reports "no findings" without actually grep'ing | Subagent's intelligence handles this — same fallback pattern as any tool error | Low |
| R6 | Pre-flight 0.4b adds friction for repos that explicitly opt out (`advisory=off`) | Config defaults are auto-detect; off is explicit | None |
| R7 | graph.json diff noise on every code commit clutters PR reviews | Real concern, no clean mitigation. Document expectation: "graphify-out/graph.json is auto-managed by the pre-commit hook; treat the diff as you would a lockfile." | Open — see §9 Q1 |

---

## 9. Open questions for the reviewer

1. **R7 graph.json PR diff noise** — Lockfile-style "click to hide" works for package-lock.json on GitHub. Does the same work for graphify-out/graph.json? Verify before recommending the pattern.
2. **§5.1 `graphifyNoticeShown` flag** — Lives in state file. Cleared when state is deleted (success_stop, abort_no_driver, etc.). Reasonable? Or should it persist longer (e.g. per-repo flag in ~/.pr-autopilot/)?
3. **§6.5 graph.json size threshold for LFS** — I picked 5,000 source files as the heuristic. Should there be a hard recommendation, or just "evaluate yourself"?
4. **Mode Y limitation (§5.5)** — Worth a roadmap entry (v0.7+ "graphify-aware SWE Agent prompts via Copilot Extensions API"), or close as won't-do?

---

## 10. Implementation order

1. **Spec review** — `/pr-autopilot:review-spec --bootstrap` on this file (next step, tonight).
2. **Skill changes** — apply edits per §5 to `skills/step/SKILL.md`, `skills/review-spec/SKILL.md`, `skills/assign/SKILL.md`.
3. **Recipe doc** — write `docs/recipes/graphify-team-setup.md` per §5.4.
4. **EVAL scenarios** — add §7 scenarios to EVAL.md.
5. **README + plugin.json** — bump version, add subsection.
6. **Self-verify** — read each modified SKILL.md end-to-end.
7. **Commit** — single conventional commit: `feat(v0.5.3): graphify code knowledge graph awareness`.
8. **PR** — open against main.
9. **Dogfood** — run `/pr-autopilot:step <PR#>` on the PR (pr-autopilot has no graphify graph itself yet, so this tests the `advisory=auto` "missing" path).
10. **Asistel adoption** — apply recipe steps to Asistel repo separately, commit + push the initial graphify-out/graph.json there.

---

## 11. References

- ExoVault memory `a9df909c` — original v0.5.3 graphify candidate (proposed 2026-05-28)
- ExoVault memory `fb285a18` — Marcin verbatim approval ("yes do it for 0.5.3")
- ExoVault memory `ca13f9dd` — Asistel graphify build evidence (2026-05-28, $0.14 DeepSeek, portability + secret-cleanness verified)
- [ADR 0002](../../decisions/0002-v0.5.3-cso-final-pass-deferred.md) — cso v0.5.3 deferral that freed this slot
- [ADR 0001](../../decisions/0001-v0.6-mcp-server-rejected.md) — earlier ADR pattern reference
- graphify repo: <https://github.com/safishamsi/graphify> (MIT)
- graphify version pinned: `0.8.22` (current install on Marcin's machine, verified 2026-05-28)
- Local Asistel CLAUDE.md §"Code Knowledge Graph (graphify)" — adoption pattern documented for Asistel agents
