# Review Triage — multi-login fetch / classify / reply pattern

This file is a copy of `gstack/review/greptile-triage.md` (used by gstack's `/ship` and `/review`) with three parameterizations:

1. **Reviewer login is a LIST** (e.g., `["cursor[bot]"]` for default config; `["cursor[bot]", "copilot-pull-request-reviewer[bot]"]` when copilot.mode=each-iter). Comments are dispatched per-thread by matching `.comments.nodes[0].author.login` against the list.
2. **Mode `unattended: true`** — never `AskUserQuestion` per comment; instead emit ASK_USER outcome which the caller translates to PAUSE.
3. **History file path** is `~/.pr-autopilot/history/<slug>.md` — self-contained, no gstack dependency.

This file is invoked by `/pr-autopilot-step` at algorithm step 10. The caller passes `reviewerLogins` (the LIST) and `mode="unattended"`.

---

## Fetch

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
PR_NUMBER=$(gh pr view --json number --jq '.number' 2>/dev/null)
```

**If either fails or is empty:** return empty result — caller handles. The skill should not be invoked outside a repo with an open PR.

```bash
# Build the LOGINS_JQ filter dynamically from the list passed by caller
# Example for ["cursor[bot]","copilot-pull-request-reviewer[bot]"]:
LOGINS_JQ='(.user.login == "cursor[bot]" or .user.login == "copilot-pull-request-reviewer[bot]")'

# Fetch line-level review comments AND top-level PR comments in parallel
gh api repos/$REPO/pulls/$PR_NUMBER/comments \
  --jq ".[] | select($LOGINS_JQ) | select(.position != null) | {id: .id, path: .path, line: .line, body: .body, html_url: .html_url, source: \"line-level\", reviewer: .user.login}" > /tmp/triage_line.json &
gh api repos/$REPO/issues/$PR_NUMBER/comments \
  --jq ".[] | select($LOGINS_JQ) | {id: .id, body: .body, html_url: .html_url, source: \"top-level\", reviewer: .user.login}" > /tmp/triage_top.json &
wait
```

The `position != null` filter on line-level comments automatically skips outdated comments from force-pushed code.

---

## Suppressions Check

History file path:

```bash
REMOTE_SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
PROJECT_HISTORY="$HOME/.pr-autopilot/history/$REMOTE_SLUG.md"
```

Read `$PROJECT_HISTORY` if it exists (per-project suppressions). Each line:

```
<date> | <repo> | <type:fp|fix|already-fixed> | <file-pattern> | <category> | <reviewer-login>
```

(Same as gstack's format but with reviewer-login column added so we can suppress per-reviewer.)

**Categories** (fixed set): `race-condition`, `null-check`, `error-handling`, `style`, `type-safety`, `security`, `performance`, `correctness`, `other`

Match each fetched comment against entries where:

- `type == fp` (only suppress known false positives, not previously fixed real issues)
- `repo` matches the current repo
- `file-pattern` matches the comment's file path
- `category` matches the issue type in the comment
- `reviewer-login` matches the comment's reviewer (or is `*` for wildcard)

Skip matched comments as **SUPPRESSED**.

If the history file doesn't exist or has unparseable lines, skip those lines and continue — never fail on a malformed history file.

---

## Classify

For each non-suppressed comment:

1. **Line-level comments:** Read the file at `path:line` ± 10 lines surrounding context.
2. **Top-level comments:** Read the full comment body.
3. Cross-reference against the full diff (`git diff origin/<base>`).
4. Consult `PUSHBACK.md` rubric. Classify:
   - **VALID & ACTIONABLE** — real bug/security/correctness issue; APPLY the fix
   - **VALID BUT ALREADY FIXED** — addressed in a subsequent commit on the branch; reply with commit SHA, resolve thread
   - **FALSE POSITIVE** — push back per `PUSHBACK.md` Tier 1 template, resolve thread
   - **SUPPRESSED** — already filtered above; skip
   - **ASK_USER** (only in `mode="unattended"`) — comment matches a PAUSE rule in `PUSHBACK.md` (architectural, scope, conflicting reviewers); return ASK_USER outcome to caller

---

## Reply APIs

Different endpoints based on comment source:

**Line-level comments** (from `pulls/$PR/comments`):

```bash
gh api repos/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies \
  -f body="<reply text>"
```

**Top-level comments** (from `issues/$PR/comments`):

```bash
gh api repos/$REPO/issues/$PR_NUMBER/comments \
  -f body="<reply text>"
```

**Resolve the thread** after a reply (line-level only):

```bash
gh api graphql -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}) { thread { isResolved } } }' \
  -f id=$THREAD_ID
```

**If a reply POST or resolve mutation fails** (e.g., PR closed, no write permission): warn and continue. Do not stop the workflow for a failed reply.

---

## Reply templates

See `PUSHBACK.md` for Tier 1 (friendly) and Tier 2 (firm, after re-flag) templates.

**Escalation detection** (line-level only): before composing, fetch existing replies on the thread via `gh api repos/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies` and check for markers `**Fixed**`, `**Not a bug.**`, `**Already fixed**`, `**This has been reviewed**` in any prior reply body. If found AND the comment is on the same file+category — use Tier 2.

If escalation detection fails (API error, ambiguous): default to Tier 1.

---

## Severity re-ranking

When classifying:

- If reviewer flags as **security/correctness/race-condition** but it's actually **style/performance** → include `**Suggested re-rank:**` in reply
- If reviewer flags a low-severity style issue as if critical → push back firmly

Cite file:line, not opinions.

---

## History writes

Before writing, ensure dir exists:

```bash
mkdir -p "$HOME/.pr-autopilot/history"
```

Append one line per triage outcome:

```
<YYYY-MM-DD> | <owner/repo> | <type> | <file-pattern> | <category> | <reviewer-login>
```

Example:

```
2026-05-23 | MarcinSufa/exo-vault | fix | src/lib/db/index.ts | null-check | cursor[bot]
2026-05-23 | MarcinSufa/exo-vault | fp | tests/note-editor.test.tsx | style | copilot-pull-request-reviewer[bot]
```

---

## Output to caller

Return structured outcome to `/pr-autopilot-step`:

```json
{
  "editsApplied": 0,
  "pushbacks": 0,
  "suppressed": 0,
  "alreadyFixed": 0,
  "askUser": [],
  "threadsResolved": []
}
```

(`askUser` is a list of comment metadata; if non-empty, caller returns PAUSE.)
