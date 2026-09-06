---
name: claude-launcher-no-auto-mode
description: "User launches Claude Code via `cc` (bypass in Shift+Tab cycle); auto mode and model-mapping edits are off-limits"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 841b8a11-4250-479d-8894-08ef80bb0ce8
  modified: 2026-09-03T09:10:13.688Z
---

The user launches Claude Code with the `cc` wrapper (adds `--allow-dangerously-skip-permissions`, so bypassPermissions is in the Shift+Tab cycle without being the start mode). Implemented as: `cc` function in pwsh 7 profile, `cc()` in `~/.bashrc`, and `cc.cmd` in `%APPDATA%\npm`. The user has abandoned **auto permission mode** permanently.

**Why:** Their `ANTHROPIC_BASE_URL` is open.bigmodel.cn (GLM) with every model tier mapped to `glm-5.3-flash[1m]`; the auto-mode classifier then shares the same model and rate-limit pool as the main conversation, and its calls time out — an endpoint-side structural issue the user confirmed is unfixable. Repeated Write/Edit/Bash failures ("glm-5.3[1m] temporarily unavailable") came from this.

**How to apply:**
- Never edit the `env` model-mapping keys in `C:\Users\Administrator\.claude\settings.json` (`ANTHROPIC_DEFAULT_*_MODEL`, base URL, token) — the user explicitly forbade this (2026-09-03).
- Don't suggest re-enabling auto mode or rely on it; if permission-style write actions stall, remind the user to leave auto mode (Shift+Tab) rather than retry-spamming.
- bypassPermissions appears in the Shift+Tab rotation only for sessions started via `cc` (or with the flag directly); it slots in **after plan mode**, so cycle past plan to reach it.
