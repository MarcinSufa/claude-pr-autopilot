# Claude self-review setup (experimental — not gated in v0.1.0)

The `claudeSelf` adapter is **final-pass only by design**. Claude grading its own diff converges in one iteration (no useful disagreement), so it cannot drive the loop. Its value is as a final rubric-driven pass before the SUCCESS_STOP.

## Status

Spec'd in [`../docs/DESIGN.md`](../docs/DESIGN.md) but NOT GATED in v0.1.0 EVAL scenarios. Implementation deferred to v0.2+.

## To use experimentally in v0.1.0

Set in `~/.claude/settings.json`:

```json
"reviewers": {
  "claudeSelf": { "enabled": true, "rubricFile": "SELF-REVIEW-RUBRIC.md" }
}
```

Author your repo-specific rubric in `SELF-REVIEW-RUBRIC.md` (currently a stub). When `claudeSelf` runs as final-pass, Claude reads the PR diff vs the rubric and emits a 1-5 score.

If `score < 5`: loop PAUSES with the rubric finding for the user to address.

Not officially supported in v0.1.0. File issues if you try this.
