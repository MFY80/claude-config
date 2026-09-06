# claude-config

Claude Code 用户配置的跨设备同步仓库（私有）。本机配置位于 `~/.claude`，通过 `sync.ps1` 与本仓库双向同步。

## 同步内容

| 仓库路径 | 来源（~/.claude 下） | 说明 |
|---|---|---|
| `settings.json` | `settings.json` | 核心配置（模型、hooks、状态栏）。**Token 已脱敏** |
| `.claude.json` | `.claude.json` | 主状态文件（MCP、项目列表、界面偏好） |
| `cc-*.ps1` / `claude-*.ps1` | 同名文件 | 自写脚本（状态栏、通知、token 扫描、用量统计） |
| `skills/` | `skills/` | 自定义技能 |
| `plugins/*.json` | `plugins/installed_plugins.json`、`known_marketplaces.json` | 插件清单（缓存本体不同步，新设备自动重新下载） |
| `memory/<项目slug>/` | `projects/<slug>/memory/` | 各项目的持久记忆 |

不同步：会话记录（`projects/` 正文）、`history.jsonl`、缓存、快照等运行时数据。

## 日常使用

```powershell
cd ~\claude-config
.\sync.ps1 status   # 查看本机与仓库的差异
.\sync.ps1 push     # 上传本机改动（自动脱敏 token，git commit + push）
.\sync.ps1 pull     # 下载仓库改动并还原到 ~/.claude（自动还原 token）
```

语义为 last-write-wins：push/pull 直接覆盖目标侧文件，没有合并。拉取前会备份将被覆盖的 `settings.json` 和 `.claude.json` 到 `~/.claude/backups/sync-<时间戳>/`。

## 新设备部署

```powershell
git clone https://github.com/MFY80/claude-config.git ~\claude-config
cd ~\claude-config
.\sync.ps1 pull     # 首次运行会提示粘贴 ANTHROPIC_AUTH_TOKEN
```

Token 会缓存到 `~/.claude/.sync-token`（在本仓库之外、不进 git），之后 pull 不再询问。

## 安全说明

- **API Token 不入仓库**：仓库中 `settings.json` 的 `ANTHROPIC_AUTH_TOKEN` 是占位符 `__CLAUDE_API_TOKEN__`，由脚本在 push 时脱敏、pull 时还原。请勿手动把真实 token 写进本仓库的任何文件。
- `.claude.json` 含有 token 的审批指纹片段（非完整密钥，无法反推）。
- 本仓库为私有，请勿改为公开。
