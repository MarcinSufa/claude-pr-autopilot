# Spec — claude-pr-autopilot v0.5.3 — `/cso` security audit as final-pass reviewer

> ## 🛑 STATUS: DEFERRED (2026-05-28)
>
> **This spec is NOT a live implementation target.** Iter1 `/pr-autopilot:review-spec --bootstrap` review surfaced **7 P0 + 11 P1 + 3 P2 findings**, including 2 P0s that are demonstrably false architectural assumptions verified against the actual cso skill source (Phase 13 *is* the findings report; Phase 8 *also* calls AskUserQuestion). The integration cannot ship without upstream gstack changes.
>
> **Decision:** see [`docs/decisions/0002-v0.5.3-cso-final-pass-deferred.md`](../../decisions/0002-v0.5.3-cso-final-pass-deferred.md) for the full rationale, alternatives considered, and the 7 prerequisites that must be met before this spec can be revived.
>
> **Why kept in tree:** the design exploration (config schema, derivation table extension, severity gate, PR-comment format) is reusable when the upstream prerequisite lands. Deleting would discard institutional memory of why we tried and what reviewers found.
>
> ---

**Data:** 2026-05-28
**Branch:** `feat/cso-final-pass`
**Worktree:** `c:\Users\sufam\IdeaProjects\claude-pr-autopilot-cso` (off `origin/main@f4bafa6`, post v0.5.2)
**Spec autor:** claude_code (Opus 4.7 1M)
**Iteracja:** v1 (pre-review) — **superseded by ADR 0002 deferral**

---

## 1. Cel (1 zdanie)

Dodać `/cso` (Chief Security Officer audit z gstack plugin) jako **opt-in final-pass reviewer** w Step 9a (Mode X) — runs *after* primary reviewers green, *before* `safeAutoMerge`, parses `.gstack/security-reports/*.json`, blokuje merge przy znalezieniu findings ≥ configured severity (`blockSeverity: critical` default).

---

## 2. Wersjonowanie

**v0.5.2 → v0.5.3 (PATCH).** Strictly additive:

- Nowy reviewer adapter `cso` w config — **default `enabled: false`** → behavior identical for existing users.
- Nowa pre-flight check (skill availability) — gated on `cso.enabled=true`.
- Nowy case w final-pass switch (step 9a) — same shape jako istniejące `claudeSelf` / `codex` / `copilot` final-pass cases.
- Nowy stop condition row (PAUSE on critical findings).
- Nowa EVAL scenario.

Single commit (no commit-split needed — one cohesive feature, no granular revert value).

---

## 3. Główna zmiana

`pr-autopilot` invokes `/cso --diff origin/{baseRef}..HEAD` via the Claude Code Skill mechanism (in-process, no external CLI). The skill writes its standard JSON report to `.gstack/security-reports/{date}-{HHMMSS}.json`. `pr-autopilot` reads the newest report, filters by `blockSeverity`, posts a summary PR comment, and PAUSEs the loop if blockers exist.

**Soft dep:** gstack plugin's `/cso` skill must be installed (detected via `~/.claude/skills/cso/SKILL.md` file existence). If `cso.enabled=true` but skill missing → ABORT in pre-flight z actionable install message. Default `enabled: false` so users without gstack are unaffected.

**Mode Y exclusion (v0.5.3):** Mode Y v0.2 already explicitly defers final-pass (skills/step/SKILL.md §"Why no final-pass in Mode Y v0.2"). v0.5.3 preserves that — `cso.enabled=true` + resolved `mode=Y` → ABORT w pre-flight. Mode Y `/cso` integration deferred to v0.6+ alongside the rest of Mode Y final-pass work.

---

## 4. Co dodajemy

| Plik | Status | Cel |
|---|---|---|
| `skills/step/SKILL.md` | MODIFY | Config block (§5.1), derivation table row (§5.2), pre-flight check (§5.3), final-pass `cso` case in step 9a (§5.4), stop conditions row (§5.7). |
| `EVAL.md` | MODIFY | New Scenario 25 — `cso` final-pass blocks merge on critical finding; Scenario 25b — `cso` clean + auto-merge proceeds; Scenario 25c — `cso` enabled but skill missing → pre-flight ABORT. |
| `README.md` | MODIFY | One-paragraph "Security audit (gstack `/cso`)" subsection under "Reviewers"; note soft dep + opt-in. |
| `.claude-plugin/plugin.json` | MODIFY | Bump `"version": "0.5.2"` → `"0.5.3"`. |
| `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.3-cso-final-pass.md` | NEW (this file) | Spec. |

**Out of scope (v0.5.3):**

- Mode Y integration — deferred to v0.6 (whole Mode Y final-pass mechanism is v0.6+ scope per existing deferral).
- Per-iteration cso (every-loop-tick audit) — too expensive, no demonstrated value; spec explicitly final-pass only.
- Auto-fix of cso findings — `/cso` is read-only by design; pr-autopilot relays findings + PAUSEs, never auto-fixes.
- Inline per-finding PR review comments — single summary comment only (avoids collision with step 6 thread fetch logic that filters by reviewer login).
- `cso` as primary fixer or per-iter reviewer (Mode X primary). Both invalid by design — `/cso` reports, doesn't propose code fixes.
- Configurable severity ordering — fixed `CRITICAL > HIGH > MEDIUM > TENTATIVE`. If user wants finer control, opens v0.6 issue.
- Caching `/cso` runs across loop iterations (would matter if cso ran per-iter; doesn't because final-pass).

---

## 5. Wymagania funkcjonalne

### 5.1 Config block

Add to `prAutopilot.reviewers` ([`skills/step/SKILL.md` §"Configuration"](../../../skills/step/SKILL.md#L23-L55)):

```json
"cso": {
  "enabled": false,
  "blockSeverity": "critical",
  "mode": "daily",
  "postPRComment": true,
  "timeoutSeconds": 300
}
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Opt-in. When false, cso pre-flight + step 9a case are skipped. |
| `blockSeverity` | enum `"critical" \| "high" \| "medium"` | `"critical"` | Findings at this severity or higher → PAUSE. Lower findings logged in comment but don't block. |
| `mode` | enum `"daily" \| "comprehensive"` | `"daily"` | Passed to `/cso` invocation. `daily` = 8/10 confidence gate (default). `comprehensive` = 2/10, longer runtime. |
| `postPRComment` | bool | `true` | When `true`, post summary comment to PR with findings table. When `false`, only PushNotification (no PR record). |
| `timeoutSeconds` | int | `300` | Hard cap on `/cso` runtime. If exceeded → PAUSE with notification "cso timed out — re-run /pr-autopilot:step after investigating". |

### 5.2 Derivation table row

Add to "Config → algorithm derivation" table ([`skills/step/SKILL.md` §62-72](../../../skills/step/SKILL.md#L62-L72)):

| Config field | `enabledForEachIter` | `enabledForFinal` | `requiresTrigger` | `postsThreads` | Score signal |
|---|---|---|---|---|---|
| `cso.enabled=true` | no | yes | no | no | findings JSON → severity filter (gate on `blockSeverity`) |

### 5.3 Pre-flight check

Insert AFTER existing 0.1-0.4 checks ([`skills/step/SKILL.md` §175-200](../../../skills/step/SKILL.md#L175-L200)), as new check 0.5:

```bash
# 0.5 cso reviewer prerequisites (only if enabled)
if config.reviewers.cso.enabled == true; then
  # 0.5a — skill installed
  if [ ! -f "$HOME/.claude/skills/cso/SKILL.md" ]; then
    PushNotification("ABORT", "cso.enabled=true but gstack /cso skill not found at ~/.claude/skills/cso/SKILL.md. Install gstack plugin or set cso.enabled=false.")
    return  # terminate, no ScheduleWakeup
  fi
  # 0.5b — Mode Y exclusion (resolved after mode derivation)
  if mode == "Y"; then
    PushNotification("ABORT", "cso.enabled=true is not supported in Mode Y (final-pass not yet implemented in Mode Y, see skills/step/SKILL.md §\"Why no final-pass in Mode Y v0.2\"). Either set cso.enabled=false or use Mode X (primaryFixer=claude).")
    return  # terminate
  fi
fi
```

**Numbering note:** existing pre-flight loads state at "0.5 Load state". Insertion is logically *between* check 0.4 (PR exists) and 0.5 (Load state). Rename existing 0.5 → 0.6, and the auto-merge short-circuit currently at "0.6 Merge-wait short-circuit" → "0.7". All downstream §-references in the same file updated atomically.

**Why Mode-Y check runs in pre-flight, not derivation:** `mode` is resolved at end of pre-flight (§"Mode derivation" produces it). The `cso.enabled + mode==Y` guard runs AFTER mode is resolved but BEFORE state load — ABORTs early without creating state file pollution.

### 5.4 Final-pass invocation (step 9a)

Add new case in step 9a final-pass switch ([`skills/step/SKILL.md` §489-503](../../../skills/step/SKILL.md#L489-L503)), positioned LAST in the final-pass loop (after `claudeSelf`, `codex`, `copilot`) — cso is the most expensive, runs only if cheaper reviewers all green:

```python
"cso":
  # 9a.cso.1 — Invoke /cso --diff against PR diff
  # Tell Claude to invoke the skill, SKIP Phase 13 (Remediation Roadmap — interactive),
  # and return when Phase 14 (Save Report) has written the JSON file.
  base = pr.baseRefName
  mode_flag = "--comprehensive" if config.reviewers.cso.mode == "comprehensive" else ""
  invoke_skill(
    "cso",
    args=f"--diff {mode_flag}",
    instructions=(
      f"Invoke /cso --diff origin/{base}..HEAD {mode_flag}. "
      "SKIP Phase 13 (Remediation Roadmap) — do NOT call AskUserQuestion. "
      "Run Phases 0-12 and 14 (Save Report). "
      f"Hard timeout: {config.reviewers.cso.timeoutSeconds}s. "
      "On completion, return the absolute path to the newest .gstack/security-reports/*.json file."
    )
  )

  # 9a.cso.2 — Locate report
  report_path = newest_file(".gstack/security-reports/*.json")
  if NOT report_path OR file_age(report_path) > 600s:  # paranoia: report must be from THIS invocation
    PushNotification("PAUSE", "cso final-pass: no recent report found at .gstack/security-reports/. Skill may have errored.")
    saveState($STATE_FILE)
    return  # PAUSE, KEEP state

  # 9a.cso.3 — Parse + filter by severity threshold
  report = json.load(report_path)
  severity_rank = {"CRITICAL": 3, "HIGH": 2, "MEDIUM": 1, "TENTATIVE": 0}
  threshold = severity_rank[config.reviewers.cso.blockSeverity.upper()]
  blockers = [f for f in report.findings
              if severity_rank.get(f.severity, 0) >= threshold]

  # 9a.cso.4 — PR comment (if enabled)
  if config.reviewers.cso.postPRComment == true:
    body = format_cso_pr_comment(
      report,
      blockers,
      blockSeverity=config.reviewers.cso.blockSeverity,
      mode=config.reviewers.cso.mode,
      report_path=report_path  # for local file pointer
    )
    gh.pr.comment(pr_number, body=body)

  # 9a.cso.5 — Gate
  if blockers:
    PushNotification(
      f"PR #{pr_number} PAUSED — /cso found {len(blockers)} {config.reviewers.cso.blockSeverity}+ finding(s)",
      f"See PR comment for CWE/OWASP details. Report: {report_path}"
    )
    saveState($STATE_FILE)
    return  # PAUSE, KEEP state — do NOT continue to safeAutoMerge
  # else: cso clean → fall through to next final-pass reviewer / safeAutoMerge
```

**Why "newest file + age check, not exact path":** /cso writes timestamped filenames (`{date}-{HHMMSS}.json`) and pr-autopilot can't predict the exact name. Glob-newest + 600s age window is the simplest robust signal that the skill ran THIS iteration. A skill error that left a stale report from yesterday would fail the age check → PAUSE rather than silently passing.

**Why "10 minutes" age window:** /cso daily mode runs typically <2 min; comprehensive can reach 5-8 min on large repos. 10 min gives slack for slow repos without false-accepting yesterday's report.

**Why "skip Phase 13" not "add --non-interactive to /cso":** modifying /cso is upstream gstack change. pr-autopilot's instructions to Claude can simply say "skip Phase 13" — Claude follows instructions in the skill prompt. If gstack later ships `--non-interactive`, pr-autopilot can switch to that without breaking change.

### 5.5 PR comment format

Single summary comment (no inline per-finding comments — see Out of scope). Format:

```markdown
## 🛡️ `/cso` security audit — {clean | blocked}

**Mode:** {daily | comprehensive} · **Block threshold:** {critical | high | medium}+
**Report:** `.gstack/security-reports/{date}-{HHMMSS}.json`

### Summary

| Severity | Count |
|---|---|
| CRITICAL | N |
| HIGH | N |
| MEDIUM | N |
| TENTATIVE | N (comprehensive mode only) |

{if blockers:}
### 🛑 Blocking findings ({blockSeverity}+)

| # | Severity | Category | File:Line | Title |
|---|---|---|---|---|
| 1 | CRITICAL | Secrets | `src/x.ts:42` | Hardcoded AWS key in source |
| ... |

<details><summary>Full finding details</summary>

#### Finding #1 — Hardcoded AWS key in source
- **CWE:** CWE-798
- **OWASP:** A07:2021
- **Confidence:** 9/10
- **Exploit scenario:** {from finding.exploit_scenario}
- **Recommendation:** {from finding.recommendation}

(repeat per finding)

</details>
{else:}
✅ No findings at or above `{blockSeverity}` severity. Continuing to merge gate.
{endif}

<details><summary>Non-blocking findings (info only)</summary>
(list MEDIUM / TENTATIVE in lower-severity table if blockers list exists, OR list all findings under HIGH if blockSeverity=HIGH, etc.)
</details>

---
*🤖 Posted by `/pr-autopilot:step` (v0.5.3) · cso v{report.version}*
```

**Why `<details>` for non-blocking + full details:** keeps the comment compact in PR feed; reviewers can expand. Avoids 20-finding walls of text in the conversation tab.

### 5.6 Stop conditions row

Add to "Stop conditions summary" ([`skills/step/SKILL.md` §1029-1056](../../../skills/step/SKILL.md#L1029-L1056)):

| Condition | Step | Outcome |
|---|---|---|
| `cso.enabled=true` but `~/.claude/skills/cso/SKILL.md` missing | pre-flight 0.5a | ABORT |
| `cso.enabled=true` + resolved mode == Y | pre-flight 0.5b | ABORT |
| `cso` final-pass: no recent report found (skill errored) | 9a.cso.2 | PAUSE |
| `cso` final-pass: report has ≥1 finding at `blockSeverity`+ | 9a.cso.5 | PAUSE (KEEP state, PR comment posted) |
| `cso` final-pass: timed out after `timeoutSeconds` | 9a.cso.1 wrapper | PAUSE |

### 5.7 Mode Y deferral note

Add as paragraph at end of existing "Mode Y design notes" subsection ([`skills/step/SKILL.md` §922-930](../../../skills/step/SKILL.md#L922-L930)):

> **`cso` final-pass not supported in Mode Y v0.5.3.** Same reasoning as the existing v0.2 deferral — Mode Y's SUCCESS_STOP path runs no final-pass reviewers. `cso` integration in Mode Y waits for the broader Mode Y final-pass work (v0.6+). Pre-flight 0.5b ABORTs cleanly if a user enables both.

---

## 6. Edge cases + open questions

### 6.1 What if `/cso` writes the report to a non-default location?

`/cso` skill hardcodes `.gstack/security-reports/{date}-{HHMMSS}.json` (per skill source line 846-849). Path is stable across gstack versions per the JSON schema. Risk = low.

**Mitigation:** Glob with explicit pattern `.gstack/security-reports/*.json`. If user runs pr-autopilot from a subdirectory of the repo where `/cso` is invoked, the relative path resolves from cwd — which by step 9a is the repo root (per pre-flight 0.2 "in a git repo"). No risk.

### 6.2 What if `/cso` produces no findings JSON at all (e.g. early exit)?

The newest-report+age check (9a.cso.2) catches this: no fresh file → PAUSE. Loop doesn't silently succeed on a non-running audit.

### 6.3 What about findings on files NOT in the PR diff?

`/cso --diff` constrains Phase 2+ to branch changes vs base (per cso skill line 357-358, 478). However, infrastructure findings (Phase 4 CI/CD) and secrets-archaeology (Phase 2) can surface findings on files outside the PR diff if those files exist on the branch. Those should still PAUSE — security issue is real regardless of PR scope.

**Decision:** trust `/cso --diff` semantics. No additional filtering in pr-autopilot.

### 6.4 What if `cso.blockSeverity=medium` (chatty) + 50 medium findings?

PR comment becomes huge. `<details>` keeps it collapsed; PushNotification body truncated to 200 chars. Loop PAUSEs cleanly. User decides whether to accept-and-merge-manually or fix.

### 6.5 Composition order with `claudeSelf`/`codex` in step 9a

Order matters: `cso` is the most expensive (Claude runs a full skill workflow internally). Run cheaper reviewers first; bail early on their PAUSE so we don't waste a /cso run.

**Proposed order in step 9a loop:** `claudeSelf` → `codex` → `copilot` → `cso`. Spec doesn't enforce order in config (existing step 9a iterates `final_pass_reviewers` per config), but the implementation should sort the iteration by an explicit `_finalPassOrder` constant in code. Add this in implementation, document briefly in comment.

### 6.6 Multiple `/cso` runs across iterations

Step 9a runs final-pass only when all per-iter reviewers green (`all_per_iter_happy AND unresolved_not_ours.length == 0`). On a typical PR this fires once near loop end. If a per-iter reviewer un-resolves (e.g. cursor.score drops back from 5), 9a doesn't re-run. So cso runs at most once per pr-autopilot loop in practice. No caching needed.

### 6.7 `.gstack/security-reports/` not in `.gitignore`

`/cso` itself flags this as a finding (skill line 902). pr-autopilot doesn't manage gitignore. Document in README that users should `.gitignore` `.gstack/` to avoid committing reports. **Add to plugin README under cso subsection.**

---

## 7. Test plan (EVAL.md scenarios)

Add 3 new scenarios:

**Scenario 25 — `cso` final-pass blocks merge on critical finding**

- Setup: PR with intentional hardcoded secret (e.g. `const AWS_KEY = "AKIA..."` in a non-test file).
- Config: `cursor.enabled=true, cso.enabled=true, cso.blockSeverity=critical`.
- Loop runs, cursor scores 5/5, step 9a starts final-pass.
- `cso` runs against diff, finds the hardcoded key as CRITICAL.
- Expected: PR comment posted with finding table + finding details. PushNotification "PR #N PAUSED — /cso found 1 critical finding". Loop terminates with KEEP state. No `safeAutoMerge` call.

**Scenario 25b — `cso` clean + auto-merge proceeds**

- Setup: PR with cosmetic change (e.g. doc typo fix). No security issues.
- Config: same as 25.
- Expected: PR comment "✅ No findings at or above critical". Loop continues to `safeAutoMerge`, hits the existing Gate-1 opt-in / Gate-3 base-safe gates as normal.

**Scenario 25c — `cso` enabled but skill missing → pre-flight ABORT**

- Setup: temporarily move `~/.claude/skills/cso/SKILL.md` → `.bak`.
- Config: `cso.enabled=true`.
- Run `/pr-autopilot:step <N>` on any open PR.
- Expected: pre-flight 0.5a ABORTs immediately. PushNotification mentions the missing skill path and "set cso.enabled=false" remediation. No state file created.

Each scenario gated for v0.5.3 release.

---

## 8. Risks + open questions for review

| # | Risk | Mitigation in spec | Open question? |
|---|---|---|---|
| R1 | `/cso` Phase 13 interactive prompt halts loop | Instructions to Claude say "SKIP Phase 13" | **Open:** does telling Claude in the invocation instructions reliably override a skill's `AskUserQuestion` step? May need upstream `--non-interactive` flag in gstack. |
| R2 | `/cso` writes report to unexpected path | Glob `.gstack/security-reports/*.json` + age check | low |
| R3 | Latency adds 2-8min to merge | Configurable `mode: daily` (faster) + `timeoutSeconds` cap | medium — but final-pass slot, runs once |
| R4 | False positives on dev-only secrets in fixtures | `/cso` skill has built-in FP filters (line 703-742) for dev/test paths | low — `/cso` is conservative by design |
| R5 | Composition with `claudeSelf` rubric — both score the diff | Explicit `_finalPassOrder` constant; both can run, both can PAUSE | low — orthogonal concerns (claudeSelf: correctness/style; cso: security) |
| R6 | `cso.enabled=true` + Mode Y user gets ABORT instead of feature | Pre-flight ABORT with clear message + escape hatch (`enabled=false`) | acceptable for v0.5.3; v0.6 lifts |

---

## 9. Open questions for the reviewer

Before implementation:

1. **Risk R1 — Phase 13 skip mechanism.** Is "Claude reads pr-autopilot's instructions in the SKILL.md and respects them when invoking the cso skill" reliable enough, or does gstack need a `--non-interactive` flag first? If reliable → ship v0.5.3 as spec'd. If not → defer v0.5.3 until gstack ships the flag (file issue upstream).
2. **Composition with existing `claudeSelf`.** Currently step 9a doesn't enforce final-pass ordering. Should v0.5.3 introduce explicit `_finalPassOrder = ["claudeSelf", "codex", "copilot", "cso"]`, or leave the iteration order to Python dict insertion order? (Recommend: explicit order; safer + documented.)
3. **PR comment scope when no PRs comment permission.** The integration assumes `gh pr comment` works. If a fork PR doesn't allow comments from the workflow, fall back to PushNotification only? Or PAUSE with an explicit "couldn't post PR comment" message? (Recommend: fall back to PushNotification with note "PR comment failed: <reason>".)

---

## 10. Implementation order

1. **Spec review** — `/pr-autopilot:review-spec` on this file (this step).
2. **Skill changes** — apply all SKILL.md edits per §5 (single commit).
3. **Self-verify** — read the modified SKILL.md end-to-end checking section numbering (0.5/0.6/0.7 renumber correctness).
4. **EVAL scenarios** — add §7 scenarios to EVAL.md.
5. **README + plugin.json** — bump version, add cso subsection.
6. **Commit** — single conventional commit: `feat(v0.5.3): /cso security audit as final-pass reviewer`.
7. **PR** — open against main.
8. **Dogfood** — run `/pr-autopilot:step <PR#>` on the PR (self-review via cursor; cso disabled on this PR since pr-autopilot has no prod secrets to find).

---

## 11. References

- gstack `/cso` skill: `~/.claude/skills/cso/SKILL.md` (v2.0.0, 927 lines).
- Existing `claudeSelf` final-pass: `skills/step/SKILL.md` §9a.
- Mode Y final-pass deferral: `skills/step/SKILL.md` §"Why no final-pass in Mode Y v0.2".
- `/cso` JSON schema: `~/.claude/skills/cso/SKILL.md` §"Phase 14: Save Report" (line 843-900).
