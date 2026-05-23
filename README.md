# claude-pr-autopilot

> **Open a PR, walk away, come back when it's merge-ready.**

[![smoketest](https://github.com/MarcinSufa/claude-pr-autopilot/actions/workflows/smoketest.yml/badge.svg)](https://github.com/MarcinSufa/claude-pr-autopilot/actions/workflows/smoketest.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-purple.svg)](https://docs.claude.com/en/docs/claude-code/plugins)
[![Status: v0.1.0 (pre-release)](https://img.shields.io/badge/status-v0.1.0%20pre--release-yellow.svg)](docs/DESIGN.md)

A Claude Code marketplace plugin that closes the PR review→fix loop. Cursor reviews your PR (or Copilot / Codex / Claude-self — configurable), Claude reads each review and either fixes the issue or pushes back with reasoning, then pushes the fix and waits for the next round. Stops when all enabled reviewers report success — or hits one of ten independent safety guards.

## Install

```bash
/plugin marketplace add MarcinSufa/claude-pr-autopilot
/plugin install pr-autopilot@claude-pr-autopilot
```

## Usage (Phase 1)

After creating a PR (via `/ship` or `gh pr create`):

```
/loop /pr-autopilot-step <PR_NUMBER>
```

The loop runs unattended until success or a safety guard fires. See [`SKILL.md`](SKILL.md) for the full algorithm and [`docs/DESIGN.md`](docs/DESIGN.md) for the architecture spec (8 review rounds; CLEARED by Composer 2.5).

## Status

**v0.1.0 — pre-release.** Phase 1 EVAL gating scenarios (1, 4, 8, 11, 17) not yet verified on real PR. Will bump to **v1.0.0** after all five gates pass. Phase 2 (Stop hook auto-chain from `/ship`) deferred until then.

## Setup

One-time setup per reviewer you want to enable. See `reviewers/`:

- [`reviewers/CURSOR-SETUP.md`](reviewers/CURSOR-SETUP.md) — default; requires Cursor Pro $20/mo for Background Agents
- [`reviewers/COPILOT-SETUP.md`](reviewers/COPILOT-SETUP.md) — final-pass by default; uses your existing Copilot seat
- `reviewers/CODEX-SETUP.md` — experimental (Codex Pro CLI sub required); stub in v0.1.0
- `reviewers/CLAUDE-SELF-SETUP.md` — experimental (uses Claude Code sub); stub in v0.1.0

## License

MIT. See [LICENSE](LICENSE).
