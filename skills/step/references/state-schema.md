# State file schema

Moved from `skills/step/SKILL.md` §"0.5 Load state". Read this when creating a new state file (`createNew`), migrating an older one, or when unsure what a state field means. State lives in `~/.pr-autopilot/<owner>-<repo>-<PR#>.json`.

## Migration on load

**v1→v2 state migration (run immediately after load):** if a loaded state file predates the v2 schema, map the old `pushbackReplies` key onto `threadPushbacks` so Mode X does not lose pushback history. (Mode Y handles v1 state separately — it ABORTs; see Y.0.5.)

```
if state.pushbackReplies AND NOT state.threadPushbacks:
  state.threadPushbacks = state.pushbackReplies   # carry Mode X history forward
# `pushbackReplies` is no longer written; it is dropped entirely in v0.3
```

## Current schema (v4)

```json
{
  "stateSchemaVersion": 4,
  "prNumber": 0,
  "repo": "<owner>/<name>",
  "headRef": "<branch>",
  "resolvedMode": "X" | "Y",
  "createdAt": "<iso>",
  "updatedAt": "<iso>",

  "fixIterations": 0,
  "pollTicksWithoutReview": 0,
  "pollTicksWithoutActivity": 0,
  "ticksWithoutProgress": 0,

  "autoMergeQueued": false,
  "autoMergeAt": "<iso>",
  "pollTicksWhileQueued": 0,
  "lastHandledHeadOid": "<sha>",
  "lastSeenReviewId": "<gh-review-id>",
  "lastTriggerAt": "<iso>",

  "threadPushbacks": [
    {"threadId": "<id>", "iteration": 0, "reason": "..."}
  ],

  "commitPushbacks": [
    {
      "iteration": 1,
      "atOid": "<sha>",
      "pushbacks": [{"file": "...", "range": "...", "reason": "..."}]
    }
  ],

  "handledOids": ["<sha>", "..."],
  "handledCommentIds": [123456],
  "reviewIteration": 0,

  "graphifyAvailable": false,
  "graphifyBuiltAtCommit": ""
}
```

**Key changes from v0.1 state:**

- `stateSchemaVersion` history: 2 = v0.2 (Mode Y fields), 3 = v0.4 auto-merge fields, 4 = v0.5.3 graphify fields (see below). The v2→v3 bump: Migration is purely additive: a v2 file loads with `autoMergeQueued: false`, `pollTicksWhileQueued: 0` (defaults); no fresh start needed. The v1 handling below is unchanged.
- `stateSchemaVersion` absent (implicit v1) — treated as v1 (Mode X) and requires a fresh start if the user switches to Mode Y. The `state.stateSchemaVersion is None` Mode-Y ABORT guard (Y.0.5) still keys off "field absent", so the v2→v3 bump does not affect it.
- **Auto-merge fields (v0.4):** `autoMergeQueued` — set true once `gh pr merge` is called; read by **step 0.6** (short-circuit into merge-wait) and **gate 6** (avoid re-queue). `autoMergeAt` — ISO timestamp the merge was queued (telemetry). `pollTicksWhileQueued` — **dedicated** counter incremented ONLY in the step-0.6 merge-wait branch, compared to `pollTickCap` for stuck-queue detection; NOT `pollTicksWithoutReview` / `pollTicksWithoutActivity` (those drive the review lifecycle). State is deleted only when step 0.6 observes `MERGED`/`CLOSED`, never when the merge is merely queued — "queued" ≠ "merged".
- **Graphify awareness fields (v0.5.3, schema v4):** `graphifyAvailable: false`, `graphifyBuiltAtCommit: ""` — set by new §0.6a check (filesystem detection of `graphify-out/graph.json` + jq-typed `built_at_commit` extraction). Migration is purely additive: a v3 state file loads with both defaulted; no fresh start needed. The `state.stateSchemaVersion is None` Mode-Y ABORT guard (Y.0.5) is unaffected — v3→v4 is additive only, the guard fires on field absent, not on field value. `graphifyBuiltAtCommit` is NOT used to gate behavior in v0.5.3 (persisted for v0.5.4 `minimumStaleness` ancestry check).
- `resolvedMode` — persisted on first tick; mode-drift guard (Y.0.5) aborts if config-derived mode differs from stored mode.
- `pushbackReplies` (v0.1) → **split into** `threadPushbacks` (Mode X, was Mode X-only in practice anyway) and `commitPushbacks` (Mode Y new).
- `handledOids`, `handledCommentIds`, `lastTriggerAt`, `pollTicksWithoutActivity`, `reviewIteration` — all Mode Y additions.
- `handledOids` and `handledCommentIds` persist as JSON arrays but are loaded into sets at runtime (see Y.0 set-conversion lines).

**Backwards-compat:** Mode X reads/writes `threadPushbacks` (renamed from `pushbackReplies`). When a v1 state file is loaded, the migration step in §"Migration on load" above (run from SKILL.md §0.5) maps `pushbackReplies` onto `threadPushbacks` so no history is lost; `pushbackReplies` is no longer written and is dropped entirely in v0.3.

**Migration decision:** v1 state files (no `stateSchemaVersion` field) are treated as Mode X; if the current derived mode is Y, ABORT with a message telling the user to delete the stale state file to start fresh in Mode Y.
