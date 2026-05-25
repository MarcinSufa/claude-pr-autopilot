---
name: automerge
description: Opt a repo into pr-autopilot safe auto-merge. Use /pr-autopilot:automerge <owner/repo> (or no arg for the current repo). When the loop reaches SUCCESS, autopilot queues a squash merge to the integration branch (dev) — never to master/main/production, always CI-gated. Separate from /pr-autopilot:allow.
---

# /pr-autopilot:automerge [owner/repo]

Adds a repository to `~/.pr-autopilot/automerge-repos` so that when the review loop reaches SUCCESS on a PR there, autopilot queues a **safe auto-merge** to the integration branch instead of just notifying.

**This is a standing "explicit ask" to auto-merge.** It is opt-in, **dev-only**, **CI-gated**, and **never merges to `master`/`main`/`production`** (those stay manual via `/land-and-deploy`). Default (repo not listed) = auto-merge OFF, behavior identical to v0.3 (notify-and-stop). This allowlist is **separate** from v0.3's `~/.pr-autopilot/allowed-repos` (auto-trigger). For a fully hands-off repo you need BOTH `/pr-autopilot:allow` (auto-start the loop) AND `/pr-autopilot:automerge` (auto-merge at the end).

## Steps

1. Determine the target repo:
   - If an argument `<owner/repo>` was given, use it.
   - Else resolve the current repo: `git remote get-url origin` → parse `owner/repo` (strip `github.com[:/]` prefix and `.git` suffix). If no origin remote, STOP: "Not in a git repo with a github origin — pass an explicit owner/repo."
2. Validate it exists AND get the canonical-cased name: `gh repo view <owner/repo> --json nameWithOwner -q .nameWithOwner`. If it fails, STOP: "Repo <owner/repo> not found or not accessible — check the name / your gh auth." **Use the returned `nameWithOwner` (GitHub's canonical casing) as the value to store** — NOT the raw user-typed argument. The auto-merge Gate 1 matches the allowlist **case-insensitively** (same matching as `/pr-autopilot:allow`), so casing differences are tolerated; storing the canonical `nameWithOwner` keeps the file clean.
3. Ensure the file and dedupe (write the canonical `nameWithOwner` from step 2):
   ```bash
   mkdir -p ~/.pr-autopilot
   touch ~/.pr-autopilot/automerge-repos
   # $CANON is the nameWithOwner from step 2 (e.g. MarcinSufa/exo-vault), not the raw input
   grep -qxF "$CANON" ~/.pr-autopilot/automerge-repos || echo "$CANON" >> ~/.pr-autopilot/automerge-repos
   ```
4. Confirm to the user: "Auto-merge enabled for <owner/repo>. When the loop reaches SUCCESS on a PR targeting `dev`, autopilot will queue a squash merge (never to master/main/production; CI-gated). Pause anytime with /pr-autopilot:pause." Show the current allowlist: `cat ~/.pr-autopilot/automerge-repos`.

Idempotent: re-running for an already-listed repo is a no-op.

**Removal** is a documented manual edit: `$EDITOR ~/.pr-autopilot/automerge-repos` (delete the line). Add-only by design, mirroring `/pr-autopilot:allow`.
