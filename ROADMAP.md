# Roadmap

Snapshot date: 2026-05-23. Revisit after each release to re-prioritise.

## v0.1.0 (pre-release)

Manual `/loop /pr-autopilot:step <PR#>` after `/ship`. Default config: Cursor primary + Copilot final-only.

Phase 1 EVAL gating scenarios (1, 4, 8, 11, 17Y, 22, 23, 24 — see EVAL.md) **must pass on a real exo-vault PR before bumping to v1.0.0**.

## v0.2 — Two-mode rotation (shipped)

First-class Mode X (Claude fixes, agent reviews) AND Mode Y (Copilot SWE Agent
fixes, Claude reviews against PUSHBACK.md). Mode-aware pre-flight, primaryFixer
config. Spec: docs/superpowers/specs/2026-05-23-pr-autopilot-v0.2-rotation-design.md.

## v0.3 — Auto-trigger (shipped)
Plugin-shipped PostToolUse hook (`if:Bash(gh pr create)`) + `/pr-autopilot:allow` allowlist + `/pause`/`/resume`. In-session best-effort nudge. (Mode Y final-pass is NOT here — deferred to its own later spec.)

## v0.4 — Safe auto-merge to dev (current)
Opt-in `/pr-autopilot:automerge` allowlist (separate from v0.3's `allowed-repos`) → `gh pr merge --auto --squash`
to **dev only**, never master/main/production (positive `allowedTargetBranches` allowlist + `neverMergeToBranches`
blocklist), CI-gated, queued-vs-merged handled by a merge-wait short-circuit (step 0.6). Falls back to a direct
squash when a repo lacks GitHub auto-merge. Never auto-invokes `/land-and-deploy` (notify + recommend only).
Spec: docs/superpowers/specs/2026-05-24-pr-autopilot-v0.4-auto-merge-design.md.

## v0.5.2 — Per-reviewer summary table + Gap E probe fix + v0.6 rejection ADR (this patch)
Patch release on top of v0.5.1. Three changes in a 3-commit-in-1-PR bundle:

- **Gap E (commit 1)** — new probe case 400 → exit 45 with actionable message for
  Cursor Privacy Mode (Legacy) blocker. Defense in depth: detect via both
  `error.code` field AND case-insensitive `error.message` grep. Discovered live
  2026-05-28 when Marcin upgraded to Cursor Pro and Cloud Agent returned 400 with
  "Cloud agent is not supported in Privacy Mode (Legacy)". v0.5.1 classified as
  generic exit 44; v0.5.2 surfaces the specific fix (Cursor Settings → Privacy).
- **Per-reviewer summary table (commit 2)** — Step 4 final status table grows
  from 4 columns to 6: Reviewer · Model · Score (DERIVED from P0/P1/P2) · Time ·
  Findings · Verdict. Outlier footer fires when any reviewer's derived Score ≤ 2,
  surfacing blockers that the aggregate mean would otherwise hide. Bootstrap
  mode (B-Step 5) uses identical table. Tokens column deliberately dropped
  (empirical: Cursor API returns null for usage/credits/tokensUsed fields).
- **v0.6 MCP rejection ADR (commit 3)** — new `docs/decisions/` directory with
  ADR pattern. ADR 0001 captures the v0.6 MCP server proposal + rejection + 6
  prerequisites for re-proposal. ROADMAP Anti-roadmap section gains a one-line
  link (canonical reasoning lives in the ADR, not duplicated here).

Spec: `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.2-per-reviewer-summary.md`.
Test coverage: 16/16 in `hooks/tests/test-review-spec-helpers.sh` (T1-T11 +
T7b + T8b + T12 + T12b + T13). Three review iterations completed pre-merge
(2 Claude subagents iter1 + Composer 2.5 iter3 paste-back) — see spec §A audit log.

ROADMAP.md is the release log for this project — no separate CHANGELOG.md.

## v0.5.1 — Review-spec improvements
Patch release on top of v0.5.0. Four gaps fixed in `/pr-autopilot:review-spec`,
all discovered during the real onboarding of pr-autopilot into MarcinSufa/asistel:

- **Gap A** — new `--bootstrap <path>` mode for spec review without a claim file
  (bootstrap PRs that introduce pr-autopilot have no assignment yet). Includes
  explicit Mode-detection section, argument parsing protocol (`=` and whitespace
  forms, ENOENT refusal, single-dash refusal, duplicate-flag refusal), and a
  technical enforcement guard that refuses `--bootstrap` in repos with active
  assignments (`assignments.yaml` + non-empty `.claude/assignment-claims/`)
  unless `--force` is appended (with `[BOOTSTRAP_FORCE]` audit signal).
- **Gap B** — Composer 2.5 manual prompt is now a single triple-backtick fenced
  code block with the spec path baked in at skill runtime (no `<path>` placeholder).
  One-click copy from most terminals/editors.
- **Gap C** — new `hooks/cursor-cloud-agent-probe.sh` pre-flight that distinguishes
  exit codes 0 (Pro)/42 (Free plan_required)/43 (invalid key)/44 (network/parse).
  `CURSOR_API_URL` env override gated behind `PR_AUTOPILOT_TEST_MODE=1` sentinel.
  Dispatch always hits production `api.cursor.com`.
- **Gap D.1** — progress visibility: status table printed at dispatch + final
  aggregated table at completion + TodoWrite mirror for sticky chat-side
  persistence. NOT TRUE incremental (atomic update at Step 4); D.2 in v0.6.

Spec: `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.1-review-spec-improvements.md`.
Test coverage: `hooks/tests/test-review-spec-helpers.sh` (8 tests T1–T8) + EVAL
scenarios 48 + 48-NEG-A/B/C + 49 + 50 + 50-NEG + 48b (Marcin-local dogfood).

Note: this version was developed on branch `feat/v0.6-review-spec-improvements`,
named before the semver decision finalized to v0.5.1 (PATCH for additive
backwards-compatible bug fixes; v0.6 stays reserved for the runtime adapter below).

ROADMAP.md is also the release log for this project — no separate CHANGELOG.md
by design.

## v0.5 — Pre-PR lifecycle (current)
Adds the **complete pre-PR layer** on top of v0.4's post-PR loop. Atomic assignment claim
via `git worktree add -b origin/main` (filesystem-atomic via git refs), spec drafting,
multi-channel pre-PR review (2 free Claude subagents always; codex-exec + cursor-cloud-agent
opt-in via env keys; composer-2.5 manual paste-back fallback), AskUserQuestion-gated TDD
approval enforced by a PreToolUse hook (`enforce-spec-gate.sh`), SessionStart safety net
that prevents stale-main planning waste, post-merge cleanup with `assignments.yaml` truth
on `main` only. Five new skills (`assign`, `review-spec`, `approve-spec`, `pr-opened`,
`finish`) + one housekeeping skill (`unassign`) + two hooks + four templates. Backward
compat: v0.4 skills (`allow`, `automerge`, `pause`, `resume`, `step`) unchanged.
Spec: `docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5-pre-pr-lifecycle-design.md`.

## v0.6 / Future — Cursor-native runtime adapter (Path C) + progress D.2 + cross-skill E/F
Port the loop layer to Cursor primitives. Algorithm unchanged; only the loop driver moves.
(Previously tentatively numbered v0.5; pushed to v0.6 to make room for pre-PR lifecycle.)

v0.6 also picks up the progress-visibility items deferred from v0.5.1:

- **D.2 — TRUE incremental progress** (Gap D.2). Each reviewer completion updates
  the status table mid-flight, not just at aggregation. Two architectures
  under evaluation (decision deferred to v0.6 design phase):
  1. **Hooks-based** — extend `settings.json` PostToolUse to match Agent calls;
     hook writes per-reviewer status to `~/.pr-autopilot/<claim-id>/progress.jsonl`;
     skill polls the file via `/review-spec --status` or `--watch`.
     Limitation: still between-turn; no live mid-turn UI updates.
  2. **MCP-server-based** — new `pr-autopilot-status` MCP server exposes
     `track_review_progress(claim_id)` as a streaming tool. Reviewer completions
     publish events to the stream; Claude/Cursor UI subscribes and re-renders
     incrementally. SOLVES TRUE-incremental properly but adds new infrastructure
     (MCP server + tests + registration in settings.json) — work suitable for
     a minor version bump.
- **E — Progress in implementation phase** (cross-skill). Apply D.1's table+TodoWrite
  pattern to `/assign` + `/approve-spec` TDD cycle. Status rows: current file,
  test pass/fail, lint, build.
- **F — Progress in PR review phase** (cross-skill). Apply same pattern to
  `/pr-opened` + `/step` loop. Status rows: per-iteration reviewer
  (Cursor/Copilot/Codex), score, threads to triage, fix-commit pushed.
- **Cross-skill template extraction** — once 3 of 5 skills implement D.1's
  pattern (rule-of-three), extract a shared status-table helper into
  `skills/_shared/progress-table.md`.

These extend the D.1 pattern shipped in v0.5.1; do not replace it.

## v1.0.0 (stability gate)

Declares the manual API stable — no new features beyond v0.2. Gated on EVAL scenarios
**1, 4, 8, 11, 17Y, 22, 23, 24** all passing on real exo-vault PRs (Phase 1 set + the
v0.2 Mode Y scenarios). See EVAL.md.

## Future (no version target)

Ranked by leverage:

| # | Item | Effort | Why it matters |
|---|---|---|---|
| A | **Real-PR demo run + asciinema** embedded in README | ~30 min | Single biggest credibility move once gates pass |
| B | **Submit to Anthropic marketplace** (`docs/marketplace-submission.md` + Anthropic form) | ~1 hr | Distribution; gets the first 100 users |
| C | **Multi-PR mode** — `/pr-autopilot` with no arg iterates over all open PRs | ~4 hrs | Useful when returning from a day off with multiple PRs in flight |
| D | **Per-repo `.pr-autopilot.json` override** | ~2 hrs | Repo-specific rubric tuning (e.g., exo-vault's RLS-mandatory rule) |
| E | **Greptile / CodeRabbit adapters** | ~6 hrs each | Other reviewer ecosystems; copy-paste pattern from cursor/copilot adapters |
| F | **Cloud-routine variant via `/schedule`** | ~4 hrs | Survives laptop sleep; requires plan-tier verification |
| G | **Codex CLI adapter EVAL gating (scenario 20b)** | ~2 hrs | If user actually subscribes to Codex Pro CLI |
| H | **Webhook PUSH model** (smee.io tunnel + local listener) | ~6 hrs | Replace polling; worth it only if 90s latency becomes friction |

## Anti-roadmap (explicit "not doing this")

- **Automatic merge to master/production after 5/5** — user always eyeballs the final merge to master. Auto-merge to dev (v0.4) is guarded by `neverMergeToBranches`; production merges stay manual. Safety > speed.
- **Reviewer-less mode** — pre-flight config validator ABORTs if no per-iter reviewer enabled. Nothing would drive the loop.
- **Claude-self as primary loop reviewer** — Claude grading Claude converges in one step. Final-pass only by design.
- **MCP server for review dispatch** — proposed and rejected 2026-05-28. See [ADR 0001](docs/decisions/0001-v0.6-mcp-server-rejected.md).
- **`/cso` security audit as final-pass reviewer (in-process)** — v0.5.3 proposed and deferred 2026-05-28. Blocked on upstream gstack `/cso --non-interactive` flag (Phase 8 + Phase 13 both call `AskUserQuestion`). See [ADR 0002](docs/decisions/0002-v0.5.3-cso-final-pass-deferred.md) + original spec at [`docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.3-cso-final-pass.md`](docs/superpowers/specs/2026-05-28-pr-autopilot-v0.5.3-cso-final-pass.md).

See [`docs/DESIGN.md`](docs/DESIGN.md) for full architecture rationale.
