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

## v0.5 / Future — Cursor-native runtime adapter (Path C)
Port the loop layer to Cursor primitives. Algorithm unchanged; only the loop driver moves.

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

See [`docs/DESIGN.md`](docs/DESIGN.md) for full architecture rationale.
