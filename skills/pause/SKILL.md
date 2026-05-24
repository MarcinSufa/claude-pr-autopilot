---
name: pause
description: Temporarily suppress pr-autopilot auto-trigger without changing the allowlist. Use /pr-autopilot:pause. Re-enable with /pr-autopilot:resume.
---

# /pr-autopilot:pause

Suppresses the auto-trigger hook globally (the allowlist is preserved).

## Steps

1. `mkdir -p ~/.pr-autopilot && touch ~/.pr-autopilot/paused`
2. Confirm: "Auto-trigger paused. PR creation will not start autopilot until /pr-autopilot:resume. (Allowlist unchanged.)"
