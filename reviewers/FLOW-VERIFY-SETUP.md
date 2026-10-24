# Flow verification leg setup (v0.5.4)

Every other leg in the autopilot loop reads the diff. This one drives the running application and
answers a different question: **do the user flows this PR touches still work?**

It is opt-in, off by default, and a repo without the harness is unaffected by its existence.

## What it needs from your repo

Three things. Miss any one and the leg reports `SKIPPED`, never a false pass.

1. **A flow catalog** — a markdown file (default `flows.md`) with one row per user flow. Minimum
   useful columns: an id, the route or area it covers, a status, and the spec that covers it. The
   leg uses it to map changed files onto flows worth re-running.
2. **A runner script** — a command (default `npm run verify:flow`) that runs flow specs against a
   locally serving app and writes a machine-readable summary.
3. **A results file** — default `test-results-verify/results.json`, containing per-run counters.
   Playwright's `json` reporter produces this shape out of the box:
   ```json
   { "stats": { "expected": 1, "unexpected": 0, "skipped": 1, "flaky": 0 } }
   ```

## Enable it

In `~/.claude/settings.json`:

```json
{
  "prAutopilot": {
    "flowVerify": {
      "mode": "final-only",
      "catalog": "flows.md",
      "command": "npm run verify:flow",
      "resultsJson": "test-results-verify/results.json",
      "baseUrl": "http://localhost:3000"
    }
  }
}
```

`mode` takes `"off"` (default) or `"final-only"`. There is deliberately no `each-iter`: driving a
browser on every iteration would dominate the loop's wall-clock, and the reading reviewers already
cover diff-level problems each time round.

## The app must already be running

The leg **never starts, restarts, or kills a process.** If `baseUrl` does not respond within five
seconds it reports `BLOCKED` and the loop pauses.

That is a deliberate constraint. A leg that spawned a dev server would leave it running after the
loop ended, and one that freed a busy port would destroy whatever the human had running there. Both
failure modes are worse than pausing and saying so.

For unattended runs, start the app yourself before launching the loop, or point `baseUrl` at a
preview deployment that is already up.

## Why the exit code is ignored

Test runners exit `0` when tests skip. A flow that never executed — a missing credential, a guarded
`test.skip` — would read as green to any wrapper that trusts the exit code.

So the leg parses `results.json` and treats four outcomes as genuinely different:

| Outcome | When | Loop action |
|---|---|---|
| `SKIPPED` | mode off, no catalog, no runner, or the diff touches no catalogued flow | falls through, no noise |
| `PASS` | at least one flow ran and none failed | falls through to the auto-merge gate |
| `FAIL` | `unexpected > 0` | comment on the PR, PAUSE |
| `BLOCKED` | app not serving, no results file, `flaky > 0`, or `expected == 0` | PAUSE |

`BLOCKED` exists because "could not run" and "ran and passed" are different facts. Collapsing them
is how a verification harness starts lying to you. A flake is also `BLOCKED`, not a pass: an
unreliable answer to a yes/no question is not an answer.

When some flows ran and others were skipped, the leg passes but posts what was skipped. Partial
coverage is fine; silent partial coverage is not.

## What it will not do

- Start or stop servers, or free a port.
- Merge, approve, or dismiss anything. It gates the auto-merge step; it cannot trigger it.
- Sweep the whole catalog. Only flows the diff can plausibly have broken. A full sweep is a separate,
  deliberate run.
- Fail a repo that has not adopted the harness.

## Writing the harness itself

This leg is a consumer, not an implementation. It assumes something in your repo already knows how
to run one flow and report the outcome. If you are starting from nothing, the shape that works:

1. Inventory your routes and existing specs, and write the catalog. Expect the honest number to be
   worse than the felt one — a spec asserting "the page rendered" is not evidence the feature works.
2. Pick the flow whose breakage hurts most and write one real spec for it, recording video.
3. Before trusting that spec, break the behaviour it guards on purpose and confirm it goes red. An
   assertion that cannot fail is decoration, and string assertions are usually case-sensitive.
4. Only then wire this leg in.
