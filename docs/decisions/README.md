# Architecture Decision Records (ADRs)

This directory captures the **why** behind architectural decisions in claude-pr-autopilot. Format follows the lightweight ADR template by Michael Nygard.

## When to write an ADR

Use ADRs for:

- Architectural choices that aren't obvious from code
- Proposals that were considered and rejected (so we don't re-derive them)
- Trade-off rationale that future contributors might question
- Decisions that span multiple versions or affect long-term direction

**Skip ADRs for:**

- Routine bug fixes (commit message is enough)
- New features that follow established patterns (spec doc is enough)
- Implementation details (docstrings / code comments are enough)

## File naming

Numbered sequentially: `0001-<title-slug>.md`, `0002-<title-slug>.md`, ...

Numbers never reused — even if an ADR is superseded, its file stays. The superseder gets a new number and links back via the `Status: Superseded by ...` line in the original.

## Template

Every ADR includes these sections at minimum:

```markdown
# ADR NNNN: <title>

- Date: YYYY-MM-DD
- Status: Proposed | Accepted | Rejected | Superseded
- Deciders: <who made the call>
- Reviewers: <who reviewed>

## Context

What's the situation that calls for a decision?

## Decision

What was decided? One short paragraph.

## Reasoning

Why this choice? Detailed rationale, including data / evidence.

## Alternatives considered

What else was on the table? Why not them?

## Consequences

What follows from this decision? What does it constrain or enable?

## References

Links to memories, specs, issues, prior ADRs.

## Supersession history

If/when this ADR is superseded, append a line linking forward.
```

## Anti-roadmap mirror

`ROADMAP.md` has an "Anti-roadmap" section listing things explicitly not being done. Each Anti-roadmap entry should be a **one-line link** to its corresponding ADR — the ADR is canonical; ROADMAP is the index.

Do not duplicate ADR reasoning in ROADMAP. If the ADR changes, ROADMAP automatically stays in sync.

## Current ADRs

- [`0001-v0.6-mcp-server-rejected.md`](0001-v0.6-mcp-server-rejected.md) — MCP server proposal for review-spec dispatch was reviewed and rejected 2026-05-28. Includes 6-prerequisite gate for re-proposal.
