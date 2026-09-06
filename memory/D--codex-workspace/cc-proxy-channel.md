---
name: cc-proxy-channel
description: "`ccp` launcher = cc + outbound proxy 127.0.0.1:7897 for external downloads; bigmodel.cn stays direct; proxyon/proxyoff toggle inside bash sessions"
metadata: 
  node_type: memory
  type: project
  originSessionId: f9e8c5e1-ea13-4687-bb6d-68c637f86e3c
  modified: 2026-09-03T10:45:20.204Z
---

The user's VPN proxy is `http://127.0.0.1:7897` (HTTP/CONNECT, Clash-style mixed port). Use it **only for external downloads** (git clone, npm/pip/curl, WebFetch), never for the GLM API endpoint.

Configured 2026-09-03, mirroring the [[claude-launcher-no-auto-mode]] pattern (three surfaces):
- `ccp` launcher = `cc` + proxy env, with a live port check that falls back to plain cc (warning) if 7897 is dead — in the pwsh 7 profile, `~/.bashrc`, and `%APPDATA%\npm\ccp.cmd`.
- `proxyon` / `proxyoff` bash functions in `~/.bashrc` toggle proxy per Bash-tool call (does not persist across calls, does not touch the cc process env).

**Why:** `NO_PROXY=localhost,127.0.0.1,::1,bigmodel.cn` keeps `open.bigmodel.cn` direct — the GLM endpoint ([[claude-launcher-no-auto-mode]]) is a Chinese service that must not route through the VPN; proxying it risks the timeouts it already suffers from. Both upper- and lowercase `HTTP_PROXY`/`http_proxy` are set because libcurl (git/curl) only reads lowercase `http_proxy`.

**How to apply:** For a download that fails or is slow, prefix the command with `proxyon &&` in bash (e.g. `proxyon && git clone ...`) instead of asking the user to relaunch. Launch the whole session as `ccp` only when the task is download-heavy; use `cc` otherwise.
