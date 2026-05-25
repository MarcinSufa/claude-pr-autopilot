# /ship integration — auto-trigger (v0.3) + auto-merge to dev (v0.4) + Stop-hook auto-chain (Phase 2, not yet)

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

## v0.4 behavior (auto-merge to dev — shipped)

When a repo is opted into `/pr-autopilot:automerge`, the loop's SUCCESS_STOP queues a squash merge of
the PR into the integration branch (`dev`) — **dev-only, CI-gated, never master/main/production**. This
closes the last manual step *within* the feature→dev flow. The handoff stops there:

```
pr-autopilot: feature → dev   (auto, opt-in, v0.4)
you, manually:  dev → master + deploy   (/land-and-deploy)
```

**pr-autopilot does NOT promote to master or deploy.** After a dev auto-merge lands, run
`/land-and-deploy` for `dev`→master + deploy. Auto-merge never auto-invokes it — it notifies and
recommends only. Spec:
`docs/superpowers/specs/2026-05-24-pr-autopilot-v0.4-auto-merge-design.md`.

## Why deferred

Per Composer's review: the Stop hook is the highest-risk integration (unattended commits firing without user present). Phase 1 EVAL gating scenarios (1, 4, 8, 11, 17Y, 22, 23, 24) must pass on real PRs first to prove the core loop is safe before adding the automation layer.
