# Flow verification: `flowVerifyLeg(prNumber, baseRef)` (v0.5.4)

Moved from `skills/step/SKILL.md`. Read this when running the behavioural verification leg from either mode.

Shared by Mode X and Mode Y. Returns `{status, reason, failedFlows, comment}` where `status` is
one of `SKIPPED` / `PASS` / `FAIL` / `BLOCKED`.

Every other leg in this loop reads the diff. This one drives the running application and asks a
different question: do the user flows this PR touches still work? Setup and adoption:
[`reviewers/FLOW-VERIFY-SETUP.md`](../../../reviewers/FLOW-VERIFY-SETUP.md).

```
cfg = config.flowVerify

# Gate 1 — opt-in. Absent config or mode "off" ⇒ SKIPPED. Repos without the harness
#          must be unaffected by this leg existing.
if cfg == null OR cfg.mode == "off":
  return {status: "SKIPPED", reason: "flowVerify.mode is off"}

# Gate 2 — adoption. Both the catalog and the runner must exist in THIS repo.
#          A missing harness is not a failure; it means the repo never opted in.
if NOT file_exists(cfg.catalog):
  return {status: "SKIPPED", reason: "no ${cfg.catalog} in this repo"}
if NOT run_command_defined(cfg.command):
  return {status: "SKIPPED", reason: "${cfg.command} is not defined in this repo"}

# Gate 3 — the app must ALREADY be serving. Do NOT start it.
#          Starting a server here would leave a process running after the loop ends,
#          and killing a port the human is using loses their work. A missing app is
#          BLOCKED, never PASS.
if NOT http_reachable(cfg.baseUrl, timeout=5s):
  return {status: "BLOCKED",
          reason: "${cfg.baseUrl} is not responding; start the app, then re-run this step"}

# Gate 4 — scope. Only the flows this PR can plausibly have broken.
#          A full catalog sweep is not a per-PR job (see "Cost discipline" in the
#          verify-flow skill); it needs a deliberate, separate run.
changed_files = git diff --name-only origin/${baseRef}...HEAD
touched_flows = flows in cfg.catalog whose route or spec path matches any changed file
if touched_flows.length == 0:
  return {status: "SKIPPED", reason: "diff touches no catalogued flow"}

# Gate 5 — run it, then judge results.json. NOT the exit code: test runners exit 0
#          when tests skip, so a flow that never executed would read as green.
run: ${cfg.command}
if NOT file_exists(cfg.resultsJson):
  return {status: "BLOCKED", reason: "runner produced no ${cfg.resultsJson}"}

stats = read_json(cfg.resultsJson).stats   # {expected, unexpected, skipped, flaky}

if stats.unexpected > 0:
  failed = names of failing flows from resultsJson
  return {status: "FAIL", failedFlows: failed,
          comment: "Flow verification failed for: ${failed}. Evidence in the runner's output
                    directory. This leg drives the app, so a failure here means a user-visible
                    behaviour changed, not a style nit."}

if stats.flaky > 0:
  # A flake is not a pass. It is an unreliable answer to a yes/no question.
  return {status: "BLOCKED", reason: "flaky flows: ${flaky names}; stabilise before merging"}

if stats.expected == 0:
  # Everything skipped — usually a missing credential. Reporting PASS here is the
  # exact failure mode this leg exists to prevent.
  return {status: "BLOCKED",
          reason: "no flow actually ran (${stats.skipped} skipped) — missing credentials?"}

if stats.skipped > 0:
  # Partial coverage: what ran, passed. Report it, do not hide it.
  gh pr comment ${prNumber} --body "Flow verification: ${stats.expected} passed,
    ${stats.skipped} skipped (blocked, not passing). Verified: ${touched_flows}."

return {status: "PASS", reason: "${stats.expected} flows passed, 0 failed"}
```

Design notes:

- **Final-only by design.** Driving a browser per iteration would dominate loop wall-clock. The
  reading reviewers catch diff-level problems each iteration; this leg answers the behavioural
  question once, at the end.
- **Four outcomes, not two.** `BLOCKED` exists because "could not run" and "ran and passed" are
  different facts. Collapsing them is how a harness starts lying.
- **No server lifecycle.** This leg never starts, restarts, or kills a process. That is a
  deliberate constraint, not an omission.
- **Never merges.** It gates `safeAutoMerge`; it cannot approve or merge anything itself.
