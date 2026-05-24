---
name: resume
description: Re-enable pr-autopilot auto-trigger after a pause. Use /pr-autopilot:resume.
---

# /pr-autopilot:resume

Removes the pause sentinel so the auto-trigger hook fires again for allowlisted repos.

## Steps

1. `rm -f ~/.pr-autopilot/paused`
2. Confirm: "Auto-trigger resumed for allowlisted repos."
