# Self-review rubric (stub — used by `claudeSelf` reviewer, experimental in v0.1.0)

This file is the rubric Claude evaluates the PR diff against in `claudeSelf` final-pass mode.

In v0.1.0 this is a stub. To use `claudeSelf` experimentally, populate this file with your repo-specific quality bar.

## Example structure (uncomment and customize)

<!--
## Required for score=5 (merge-ready)

- [ ] All new public functions have type annotations / signatures
- [ ] All new tables have RLS policies (project-specific — e.g., ExoVault rule)
- [ ] No `any` types added without justification comment
- [ ] No console.log / debug prints left in
- [ ] All new files have at least one test that exercises the happy path
- [ ] CHANGELOG updated for user-visible changes

## Score deductions

- -1: any rule above unmet
- -2: PR title doesn't match the actual diff scope (e.g., title says "fix typo" but added 200 lines)
- -3: PR introduces a known anti-pattern documented in CLAUDE.md
-->

When populated, Claude reads this file at the start of the `claudeSelf` final-pass, then evaluates the PR diff against each criterion and emits a 1-5 score plus a list of failing criteria.
