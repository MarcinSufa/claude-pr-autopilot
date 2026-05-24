# PUSHBACK Rubric — when to apply vs push back vs ask user

This file is read by `/pr-autopilot:step` during algorithm step 10 (triage). For each unresolved reviewer comment, Claude must classify the action: **apply the fix**, **push back with reasoning**, or **PAUSE for user input**.

This rubric is reviewer-agnostic — applies whether the comment came from Cursor, Copilot, Codex, or any future reviewer.

In **Mode Y** (SWE Agent fixes, Claude reviews commits), the same rubric applies per hunk rather than per reviewer comment. Where a rule is Mode Y-relevant, a `**Mode Y example:**` line shows how to apply it against a commit hunk.

## Always APPLY (no exception) **(Mode X & Y)**

- **Security issues**: SQL injection, XSS, unsafe deserialization, exposed secrets, missing auth checks, missing RLS policies on new tables
- **Correctness bugs**: null-pointer, off-by-one, race conditions, broken Promise chains, missing await, unreachable code, type errors

  **Mode Y example:** SWE Agent's hunk removes an `await` from a DB call that previously returned a Promise — this is a correctness bug; verdict is PUSHBACK (and trigger re-fix), not APPROVE.

- **Test gaps**: reviewer points out a code path with no test coverage that's reachable in production
- **CLAUDE.md rule violations**: anything the target repo's `CLAUDE.md` explicitly mandates (e.g., exo-vault: "RLS enabled on all new tables", "use pnpm not npm")

  **Mode Y example:** SWE Agent adds a new table migration but omits `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` — exo-vault CLAUDE.md mandates RLS on all new tables; PUSHBACK.

- **Stale references**: comments pointing to functions/types/files that were renamed/removed and the reviewer caught it
- **Migration safety issues**: comments about non-additive schema changes, backfill ordering, lock acquisition risk

## Always PUSH BACK (post Tier 1 reply, resolve thread) **(Mode X & Y)**

- **Style nits when no linter rule enforces it**: e.g., "consider using arrow function" when there's no ESLint rule for it
- **Suggestions that would weaken types**: e.g., "use `any` here for simplicity" — never accept type-safety regressions

  **Mode Y example:** SWE Agent's hunk changes a typed parameter from `userId: string` to `userId: any` — this weakens the type contract; PUSHBACK even if it "simplifies" the immediate call site.

- **Misreads of the diff** **(Mode X only — review threads)**: reviewer comments on logic that doesn't exist in the file, or misidentifies what changed
- **Already-handled cases**: e.g., "consider null check" when null is already handled upstream/downstream; reply with a code reference to the existing handling
- **Requests for unrelated refactors**: out-of-scope cleanup, "while you're here" suggestions that expand the PR beyond its purpose

  **Mode Y example:** SWE Agent's commit extracts a utility function into a new shared module unrelated to the PR's stated goal — this is scope creep outside the PR title; PUSHBACK and call it out in the re-trigger comment.

- **Comments asking for features outside the PR title's scope** **(Mode X only — review threads)**: scope creep; user should open a separate issue

## Always PAUSE (return PAUSE outcome to algorithm step 10; user resumes manually)

- **Architectural disagreements** **(Mode X only — review threads)**: reviewer suggests "consider refactoring X" where X is a structural choice (e.g., "extract this to a separate service", "convert this to a state machine"). Not appropriate for unattended fixing.
- **Anything that would change feature behavior** **(Mode X & Y)**: e.g., "this endpoint should return 404 instead of 401" — semantic change, needs user decision
- **Conflicting reviewer comments** **(Mode X only — review threads)**: two reviewers disagree on the same issue (one says "use X", another says "don't use X")
- **Comments requiring information not in the diff** **(Mode X only — review threads)**: e.g., "what's the migration plan for existing data?" — needs domain knowledge user has and Claude doesn't

## Behavior change without intent signal → PAUSE (Mode Y)

When reviewing a SWE Agent commit, if a hunk changes user-visible behavior
(comparison operators on eligibility/limits, default values, error vs success
paths, removed validation) AND the PR description / linked issue does not
explicitly call for that change, return **PAUSE**, not APPROVE.

Example (exo-vault PR #128): SWE Agent changed `age > 18` to `age >= 18`.
Defensible as a bug fix, but it shifts an eligibility cutoff. No issue asked
for it → PAUSE for human confirmation rather than silently approving.

Counter-example: SWE Agent renames a variable, fixes a typo, extracts a magic
number, adds a return-type annotation → APPROVE (no behavior change).

## Tier 1 reply template (for push-backs) **(Mode X only — review threads)**

When pushing back on a comment, post a reply on the thread (line-level: `gh api repos/$REPO/pulls/$PR/comments/$COMMENT_ID/replies`; top-level: `gh api repos/$REPO/issues/$PR/comments`) with:

```
**Not a bug.** <1-sentence reason this isn't an issue>

**Evidence:**
- <file:line reference showing the safe pattern or existing handling>
- <link to relevant CLAUDE.md rule or test, if applicable>
```

After posting, resolve the thread via GraphQL `resolveReviewThread` mutation. The thread will not be re-fetched in subsequent iterations because of the `isResolved=true` filter, but ALSO record the threadId in `state.pushbackReplies` so it survives any future un-resolve.

## Tier 2 reply template (when reviewer re-flags after our Tier 1) **(Mode X only — review threads)**

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

## Default when ambiguous **(Mode X & Y)**

If a comment doesn't clearly fit APPLY / PUSH BACK / PAUSE — default to PAUSE. Better to bring the user back in than apply a wrong fix or push back on a real issue. The 5-iteration cap and stall guard make conservative defaults safe.
