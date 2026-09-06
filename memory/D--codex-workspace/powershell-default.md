---
name: powershell-default
description: PowerShell commands default to pwsh 7 via psh wrapper; UTF-8 encoding is preconfigured
metadata: 
  node_type: memory
  type: user
  originSessionId: 841b8a11-4250-479d-8894-08ef80bb0ce8
  modified: 2026-09-03T05:15:15.962Z
---

On this Windows machine, run all PowerShell through **pwsh 7** (`pwsh.exe`, currently 7.6.5 via the stable WindowsApps execution alias). Do not re-detect installed versions each session — `powershell.exe` (5.1) exists but is only used if explicitly requested.

**Why:** Two PowerShell versions are installed; the user chose pwsh 7 as the standing default, and Chinese output garbles unless UTF-8 console encoding is forced (system codepage is GBK).

**How to apply:**
- Prefer `psh '<code>'` — a bash function defined in `~/.bashrc` that runs `pwsh.exe -NoProfile -NoLogo -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; <code>"`. Available in every Bash tool call (loaded via `~/.bash_profile`).
- Plain `pwsh.exe` / `-File` are also safe: `C:\Users\Administrator\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` sets UTF-8 console encoding globally.
