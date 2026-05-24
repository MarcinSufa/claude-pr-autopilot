---
name: allow
description: Add a repo to the pr-autopilot auto-trigger allowlist. Use /pr-autopilot:allow <owner/repo> (or no arg for the current repo). The auto-trigger hook only fires for allowlisted repos.
---

# /pr-autopilot:allow [owner/repo]

Adds a repository to `~/.pr-autopilot/allowed-repos` so the auto-trigger hook will nudge autopilot on PRs created there.

## Steps

1. Determine the target repo:
   - If an argument `<owner/repo>` was given, use it.
   - Else resolve the current repo: `git remote get-url origin` → parse `owner/repo` (strip `github.com[:/]` prefix and `.git` suffix). If no origin remote, STOP: "Not in a git repo with a github origin — pass an explicit owner/repo."
2. Validate it exists: `gh repo view <owner/repo> --json nameWithOwner -q .nameWithOwner`. If it fails, STOP: "Repo <owner/repo> not found or not accessible — check the name / your gh auth."
3. Ensure the file and dedupe:
   ```bash
   mkdir -p ~/.pr-autopilot
   touch ~/.pr-autopilot/allowed-repos
   grep -qxF "<owner/repo>" ~/.pr-autopilot/allowed-repos || echo "<owner/repo>" >> ~/.pr-autopilot/allowed-repos
   ```
4. Confirm to the user: "Auto-trigger enabled for <owner/repo>. New PRs there will auto-start autopilot (skip with /pr-autopilot:pause; drafts are ignored)." Show the current allowlist: `cat ~/.pr-autopilot/allowed-repos`.

Idempotent: re-running for an already-listed repo is a no-op.
