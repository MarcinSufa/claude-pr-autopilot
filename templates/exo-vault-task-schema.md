# pr-autopilot v0.5 — ExoVault task `description` schema

Every assignment is mirrored to an ExoVault task with `title = "assignment:<id>"`.
The task's `description` field carries fine-grained state that ExoVault's coarse
`status` enum (`backlog | todo | in_progress | done | blocked`) cannot express.

This schema is **the** contract — both `/pr-autopilot:assign` and `/pr-autopilot:review-spec`
and downstream skills parse and write this markdown structure.

## Format

```markdown
<!-- pr-autopilot-task-schema-v1 -->

## Assignment metadata
- **id:** <assignment-id>
- **subStatus:** spec_drafting | spec_review_requested | spec_revising | spec_review_complete | implementing | pr_review_requested | pr_revising | merged | awaiting_user_decision | awaiting_deps_merge
- **specFile:** specs/<YYYY-MM-DD>-<id>.md
- **branch:** <git-branch>
- **worktree:** .claude/worktrees/<id>
- **prNumber:** <int or null>
- **prUrl:** <url or null>
- **reviewIteration:** <int>
- **approvedAt:** <iso or null>
- **approvedBy:** <user-id or null>

## Done when
- [ ] <acceptance criterion 1 from assignments.yaml>
- [ ] <acceptance criterion 2>
- [ ] ...

## Depends on
- <dep-id> (status: merged | in_progress | todo)
- ...

## Blocks
- <reverse-dep-id>
- ...

## Reviewers requested
- claude-code-reviewer-subagent (always)
- claude-self-review (always)
- composer-2.5-manual (always — advisory only)
- codex-exec (if OPENAI_API_KEY or codex CLI present)
- cursor-cloud-agent (if CURSOR_API_KEY present)
- cursor-pr-bot (post-PR only)
- copilot-pr-bot (post-PR only)
- marcin (always — final approver)

## Review history
- 2026-05-28T16:00:00Z — v1 drafted by agent <agent-id>
- 2026-05-28T16:30:00Z — v1 review codex-exec: 3 findings (1 P0, 2 P1)
- 2026-05-28T16:35:00Z — v1 review claude-code-reviewer-subagent: 2 findings (0 P0, 2 P2)
- 2026-05-28T17:00:00Z — v2 drafted addressing v1 findings
- 2026-05-28T17:15:00Z — v2 review composer-2.5-manual: 1 finding (0 P0, 1 P1, advisory)
- 2026-05-28T17:30:00Z — v2 approved by marcin via AskUserQuestion (subStatus → implementing)
- 2026-05-28T18:00:00Z — PR #123 opened (subStatus → pr_review_requested)
- 2026-05-28T19:00:00Z — PR #123 merged in commit abc1234 (subStatus → merged)
```

## Field semantics

| Field | Source of truth | Updated by |
|---|---|---|
| `id`, `branch`, `worktree` | claim file | `/assign` once at claim time, never again |
| `subStatus` | claim file (`subStatus` field) | every transitioning skill |
| `specFile` | claim file | first `/review-spec` invocation (auto-detect if not pre-set) |
| `prNumber`, `prUrl` | claim file | `/pr-opened` |
| `reviewIteration` | claim file | incremented by each `/review-spec` |
| `approvedAt`, `approvedBy` | claim file | `/approve-spec` (only via AskUserQuestion) |
| `Done when` checklist | `assignments.yaml` `acceptance` field | `/assign` copies, agent marks complete as work progresses |
| `Depends on`, `Blocks` | `assignments.yaml` `deps` / `blocks` | `/assign` copies; updated by skills as deps merge |
| `Reviewers requested` | static list per command | `/review-spec` enumerates available channels |
| `Review history` | `/review-spec`, `/approve-spec`, `/pr-opened`, `/finish` | append-only, never edit historic entries |

## Why ExoVault is the **mirror**, not the truth

The claim file (`.claude/assignment-claims/<id>.json`, committed on the feature branch)
is the runtime **source of truth** for in-flight state. ExoVault is an **observable mirror**
that enables:

1. Cross-session listing (`mcp__exo-vault__list_tasks(status='in_progress')` reveals all in-flight assignments).
2. Other agents detecting claim conflicts (in addition to the git-branch atomic lock).
3. Async cross-session communication via `Review history` audit trail.

When ExoVault is unreachable, skills proceed with file-only state. When it returns,
re-syncing is idempotent — the canonical title `assignment:<id>` ensures no duplicates.

## Future: native field migration (vN+1)

The proposal (see spec §"ExoVault — extension proposal (vN+1)") is to add native fields
(`subStatus`, `doneWhen`, `dependencies`, `branch`, `prNumber`, `reviewers`, etc.) to the
ExoVault MCP schema. v0.5 uses this markdown structure as the migration path: tooling
that reads `description` markdown today will continue to work after native fields ship,
with skills updated to write both during the transition.
