# 多智能体连接中心与 MCP

Workdesk 内置一个本机 stdio MCP 服务（`WorkdeskCLI mcp`），让 Hermes、Codex、Claude Code、OpenCode 等支持 MCP 的客户端在**已授权项目**内查询项目并上报进度。它不监听网络端口、不常驻后台、不运行 Node；客户端按需启动子进程，进程随客户端会话结束。

## 已验证能力

- MCP 生命周期：`initialize` / `notifications/initialized` / `tools/list` / `tools/call`，逐行 JSON-RPC（MCP 2025-11-25 标准）。
- 工具面固定为三个：
  - `workdesk_projects`：只返回当前身份经本机授予 MCP 的项目；绑定项目本身不等于授权。
  - `workdesk_progress`：签名后写入项目动态，返回 `accepted|rejected|conflict` 真实回执；只记录，不改变任务状态。
  - `workdesk_task_create`：仅在“另外允许创建待办任务”时可用；不能完成任务、改状态或创建项目。
- 事件使用稳定 `event_id`；同一 ID 重试幂等，同 ID 不同内容返回 `conflict`。`transport=mcp` 纳入签名，剥离标记无法绕过更严格的 MCP 许可。
- 撤销 MCP 许可、撤销项目绑定后，旧 `event_id` 重放会被拒绝；重新绑定不会复活旧许可。
- 私钥只在 Workdesk 管理的 0600 文件中读取，不写入 MCP 响应、日志或 UI。
- 回执文件触发目录通知，普通项目视图直接刷新；无需额外轮询或常驻服务。

## 支持矩阵

| 客户端 | 配置方式 | 本机实测 |
|---|---|---|
| Hermes | 官方 `hermes mcp add`，可撤销 | 已用真实 Hermes MCP 客户端连接，3 个工具发现成功 |
| Codex | 官方 `codex mcp add`（`~/.codex/config.toml`） | 本机未安装，未实测 |
| Claude Code | 官方 `claude mcp add`（用户级 `~/.claude.json`） | 本机未安装，未实测 |
| OpenCode | 写入全局 `~/.config/opencode/opencode.json` 的 `mcp` 字段 | 本机未安装，未实测 |
| 通用 MCP | 预览/复制 `mcpServers` JSON，手动导入 | 协议与子进程已实测 |
| Cursor / Cline / Roo | 可导入通用 MCP 配置 | 未实测，UI 明确标注 |
| WorkBuddy | 官方接口待核实 | 未接入，不宣称支持 |

“已发现”只表示找到可执行文件；“已配置”要求本应用写入内容与记录的哈希一致；“项目授权”是另一道本机操作；“accepted 已验证”来自真实子进程回执。四者互不自动推导。

## 配置安全

- 修改第三方配置只在用户点击“确认添加配置”后执行；预览先展示目标路径和等价配置。
- 写入前备份原文件；撤销仅当配置文件仍是本应用写入的版本时执行，检测到用户修改会停止，不覆盖。
- 已存在同名 `workdesk` 条目、JSONC 注释配置或自定义 Claude 配置目录时拒绝自动写入，改用通用导入。
- 发现工具不会自动登记身份、授权项目或安装软件；首次使用由用户在连接中心点击完成。

## 开发验证

- `swift run CoreChecks`：MCP 握手、工具面、授权过滤、accepted 与普通界面查询、任务权限、去重/冲突、撤销重放、无效入参、私钥不输出、隔离配置备份撤销、真实 stdio 子进程。
- `WORKDESK_DATA_DIR=$(mktemp -d) WORKDESK_MCP_CHECK=1 dist/Workdesk.app/Contents/MacOS/Workdesk`：打包应用内真实 MCP 写入 → 回执通知 → 正常 Model 项目进展，并输出连接中心原生快照。
- `python3 scripts/check-launch.py`：打包应用迁移、启动扫描、实时目录事件、CLI 回执。
