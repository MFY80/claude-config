---
name: claude-config-sync-repo
description: Claude Code 用户配置通过 ~/claude-config/sync.ps1 同步到私有 GitHub 仓库 MFY80/claude-config，token 永不入库
metadata: 
  node_type: memory
  type: project
  originSessionId: 8a71f533-1471-4041-b135-76ac68d4b0cf
  modified: 2026-09-06T07:48:54.417Z
---

2026-09-06 建立了 Claude Code 用户配置的跨设备同步：

- 远端：https://github.com/MFY80/claude-config （**私有**，勿改公开）
- 本地仓库：`%USERPROFILE%\claude-config`，同步脚本 `sync.ps1`（`push` / `pull` / `status`，语义为 last-write-wins，pull 前自动备份将被覆盖的 settings.json 和 .claude.json）
- 同步范围：`settings.json`、`~/.claude.json`（注意它在 home 根目录而非 ~/.claude 内，脚本里是路径 override）、4 个自写 .ps1 脚本、`skills/`、插件清单 JSON、各项目 `memory/`
- **Token 安全约定**：真实 `ANTHROPIC_AUTH_TOKEN` 只存在于本机 `~/.claude/settings.json`；仓库副本是占位符 `__CLAUDE_API_TOKEN__`，push 时脱敏、pull 时从 `~/.claude/.sync-token`（git-ignored，仅 pull 时才创建）还原。任何情况下不得把真实 token 写进该仓库的文件
- 新设备部署：`git clone` 到 `~/claude-config` → `sync.ps1 pull` → 按提示粘贴一次 token

**Why:** 用户要求配置跨设备继承，且明确选择了脱敏方案，token 泄露到 GitHub 是不可接受的。
**How to apply:** 用户提到同步/备份 Claude 配置、或在新设备恢复配置时，用 `sync.ps1` 而不是手动复制；改动了 settings.json、skills、脚本后提醒 push 一次。
