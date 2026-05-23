# PUSHBACK Rubric — when to apply vs push back vs ask user

This file is read by `/pr-autopilot-step` during algorithm step 10 (triage). For each unresolved reviewer comment, Claude must classify the action: **apply the fix**, **push back with reasoning**, or **PAUSE for user input**.

This rubric is reviewer-agnostic — applies whether the comment came from Cursor, Copilot, Codex, or any future reviewer.

## Always APPLY (no exception)

- **Security issues**: SQL injection, XSS, unsafe deserialization, exposed secrets, missing auth checks, missing RLS policies on new tables
- **Correctness bugs**: null-pointer, off-by-one, race conditions, broken Promise chains, missing await, unreachable code, type errors
- **Test gaps**: reviewer points out a code path with no test coverage that's reachable in production
- **CLAUDE.md rule violations**: anything the target repo's `CLAUDE.md` explicitly mandates (e.g., exo-vault: "RLS enabled on all new tables", "use pnpm not npm")
- **Stale references**: comments pointing to functions/types/files that were renamed/removed and the reviewer caught it
- **Migration safety issues**: comments about non-additive schema changes, backfill ordering, lock acquisition risk

## Always PUSH BACK (post Tier 1 reply, resolve thread)

- **Style nits when no linter rule enforces it**: e.g., "consider using arrow function" when there's no ESLint rule for it
- **Suggestions that would weaken types**: e.g., "use `any` here for simplicity" — never accept type-safety regressions
- **Misreads of the diff**: reviewer comments on logic that doesn't exist in the file, or misidentifies what changed
- **Already-handled cases**: e.g., "consider null check" when null is already handled upstream/downstream; reply with a code reference to the existing handling
- **Requests for unrelated refactors**: out-of-scope cleanup, "while you're here" suggestions that expand the PR beyond its purpose
- **Comments asking for features outside the PR title's scope**: scope creep; user should open a separate issue

## Always PAUSE (return PAUSE outcome to algorithm step 10; user resumes manually)

- **Architectural disagreements**: reviewer suggests "consider refactoring X" where X is a structural choice (e.g., "extract this to a separate service", "convert this to a state machine"). Not appropriate for unattended fixing.
- **Anything that would change feature behavior**: e.g., "this endpoint should return 404 instead of 401" — semantic change, needs user decision
- **Conflicting reviewer comments**: two reviewers disagree on the same issue (one says "use X", another says "don't use X")
- **Comments requiring information not in the diff**: e.g., "what's the migration plan for existing data?" — needs domain knowledge user has and Claude doesn't

## Tier 1 reply template (for push-backs)

When pushing back on a comment, post a reply on the thread (line-level: `gh api repos/$REPO/pulls/$PR/comments/$COMMENT_ID/replies`; top-level: `gh api repos/$REPO/issues/$PR/comments`) with:

```
**Not a bug.** <1-sentence reason this isn't an issue>

**Evidence:**
- <file:line reference showing the safe pattern or existing handling>
- <link to relevant CLAUDE.md rule or test, if applicable>
```

After posting, resolve the thread via GraphQL `resolveReviewThread` mutation. The thread will not be re-fetched in subsequent iterations because of the `isResolved=true` filter, but ALSO record the threadId in `state.pushbackReplies` so it survives any future un-resolve.

## Tier 2 reply template (when reviewer re-flags after our Tier 1)

If a previous iteration already posted a Tier 1 reply on this thread AND the same reviewer re-raised the same category of concern, escalate to Tier 2:

```
**This has been reviewed and confirmed as [intentional / already-fixed / not-a-bug].**

\`\`\`diff
<full relevant diff showing the change or safe pattern>
\`\`\`

**Evidence chain:**
1. <file:line permalink showing safe pattern>
2. <commit SHA where addressed, if applicable>
3. <architecture rationale or CLAUDE.md link>

**Suggested re-rank:** This is a `<actual category>` issue, not `<claimed category>`.
```

Then resolve the thread. If the reviewer re-raises a third time on the same issue, the no-progress stall counter (algorithm step 11.5) will eventually PAUSE the loop.

## Default when ambiguous

If a comment doesn't clearly fit APPLY / PUSH BACK / PAUSE — default to PAUSE. Better to bring the user back in than apply a wrong fix or push back on a real issue. The 5-iteration cap and stall guard make conservative defaults safe.
