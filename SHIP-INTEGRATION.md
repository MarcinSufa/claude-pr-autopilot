# /ship integration via Stop hook (Phase 2 — NOT IN v0.1.0 or v0.2)

This file is a placeholder. The Phase 2 Stop hook auto-chain is documented in [`docs/DESIGN.md`](docs/DESIGN.md) but NOT IMPLEMENTED in v0.1.0 or v0.2 — it is targeted for v0.3+.

## v0.1.0 behavior

After running `/ship`, the user manually invokes:

```
/loop /pr-autopilot:step <PR#>
```

No Stop hook, no auto-chain.

## v0.3 behavior (auto-trigger — shipped)

A plugin-shipped `PostToolUse` hook (`if: "Bash(gh pr create)"`) runs a gate script that
nudges Claude to auto-start the loop after a PR is created in an allowlisted repo. It does
NOT scan Bash output (hooks can't see output) — Claude supplies the PR number from context.
Gates: is-pr-create / draft-skip / allowlist / paused. Kill switch: `/pr-autopilot:pause`
(touches `~/.pr-autopilot/paused`); re-enable with `/pr-autopilot:resume`. The paused
sentinel is the sole kill switch — no env-var disable. Spec:
`docs/superpowers/specs/2026-05-24-pr-autopilot-v0.3-auto-trigger-design.md`.

## Why deferred

Per Composer's review: the Stop hook is the highest-risk integration (unattended commits firing without user present). Phase 1 EVAL gating scenarios (1, 4, 8, 11, 17Y, 22, 23, 24) must pass on real PRs first to prove the core loop is safe before adding the automation layer.
