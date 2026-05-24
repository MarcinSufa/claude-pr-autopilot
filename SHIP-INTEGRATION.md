# /ship integration via Stop hook (Phase 2 — NOT IN v0.1.0 or v0.2)

This file is a placeholder. The Phase 2 Stop hook auto-chain is documented in [`docs/DESIGN.md`](docs/DESIGN.md) but NOT IMPLEMENTED in v0.1.0 or v0.2 — it is targeted for v0.3+.

## v0.1.0 behavior

After running `/ship`, the user manually invokes:

```
/loop /pr-autopilot:step <PR#>
```

No Stop hook, no auto-chain.

## v0.3+ planned behavior (Phase 2)

A Stop hook in `~/.claude/settings.json` will detect when `/ship` (or any Claude turn) ends with a `gh pr create` and auto-invoke `/loop /pr-autopilot:step <PR#>` with the just-created PR number.

Per-session disable: `PR_AUTOPILOT_DISABLE=1` env var before running `/ship`.

Hook mechanism (Stop vs PostToolUse) will be decided in the v0.3 spec; the v0.2 rotation work does not add any hook.

Concrete hook JSON template will be added to this file when v0.3 ships. Until then: manual invocation only.

## Why deferred

Per Composer's review: the Stop hook is the highest-risk integration (unattended commits firing without user present). Phase 1 EVAL gating scenarios (1, 4, 8, 11, 17Y, 22, 23, 24) must pass on real PRs first to prove the core loop is safe before adding the automation layer.
