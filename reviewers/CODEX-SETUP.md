# Codex reviewer setup (experimental — not gated in v0.1.0)

The `codex` reviewer adapter has two distinct paths. Most users want **Path A**.

## Path A: Codex via Cursor (recommended, no extra sub)

If you have **Cursor Pro**, you can pick Codex as the underlying model for the Cursor Background Agent. Then use the **`cursor`** adapter (not `codex`) — same logic, model is invisible to the skill.

See [`CURSOR-SETUP.md`](CURSOR-SETUP.md) → "Choose the underlying model" section.

## Path B: Codex via standalone CLI (experimental)

For users with a **Codex Pro CLI subscription** (~$100/mo) who want Codex to run independently of Cursor — e.g., as a second opinion alongside Cursor's review.

**Status:** Spec'd in [`../docs/DESIGN.md`](../docs/DESIGN.md) but NOT GATED in v0.1.0 EVAL scenarios. Implementation deferred to v0.2+.

To use experimentally in v0.1.0:

- Set `reviewers.codex.mode = "each-iter"` or `"final-only"` in `~/.claude/settings.json`
- Set `reviewers.codex.postCommentsToPR = true` if you want Codex's findings visible to collaborators on the PR (false = processed internally only)
- Ensure `codex` CLI is on your PATH and authenticated

Not officially supported. File issues if you try this.
