# Workdesk · 工作进度台

轻量 macOS 菜单栏与置顶悬浮窗，汇总个人任务、智能体进度和会议待办。

状态：原生项目/阶段编辑、五种独立项目与任务状态、完成任务归档、签名事件收件箱与 CLI、来源映射和事件审计、Hermes 会议识别与证据审核、本机 stdio MCP 四工具、持久化首次授权与多客户端连接中心已实现。QQ 需额外配置与独立验证；Hermes 有历史客户端发现记录，Codex 有用户环境接入记录，各客户端四工具发现与实际调用仍需在当前会话验证。

**使用入口：[离线图文 HTML 手册](docs/manual/workdesk-user-manual.html) · [完整中文用户指南](docs/user-guide.md)** — 从菜单栏操作、状态管理到智能体连接、会议审核、归档和备份。

## 编译与运行

要求 macOS 13+、Swift 5.9+。无第三方运行时依赖，使用系统 SQLite。

```sh
swift build # 同时更新检查会启动的 WorkdeskCLI 子进程
swift run CoreChecks
bash scripts/build-app.sh
open dist/Workdesk.app
```

完整 Xcode 环境还可执行 `swift test`；仅 Command Line Tools 的机器可能缺少 XCTest，使用 `CoreChecks` 验证核心行为。

已实现中文管理窗口、菜单栏、置顶窗、项目名称与阶段编辑、任务改名、手动项目与任务状态和版本冲突保护。项目与任务由授权智能体创建，界面不提供手动新增。删除项目会先确认，再级联删除任务；任务删除确认因窗口而异，详见用户指南。完成状态由本机手动选择触发。

默认数据在 `~/Library/Application Support/Workdesk/workdesk.sqlite`。设置 `WORKDESK_DATA_DIR` 可指定隔离样例目录。关闭窗口后可从菜单栏重新打开；退出菜单结束应用。打包脚本生成本机架构的 Release `.app` 并作 ad-hoc 本地签名，未进行公证。

项目和任务由登记并授权的智能体通过 MCP 或签名协议创建；首次在连接中心保存范围后，可持续使用，创建新项目默认关闭，待办需单独授权；本机保留改名、阶段、状态和删除操作。日历、截止与提醒流程已撤回，旧数据库字段原样保留。会议文字可交给 Hermes 识别证据草稿，用户审核后通过现有身份与项目 MCP 权限确认写入。接入步骤见 [事件协议](docs/event-protocol.md)。

当前限制：QQ 不自动接通，需按使用环境独立验证；无音频转写，会议识别依赖兼容的已安装 Hermes 与既有模型配置；自动归档在启动或数据刷新时检查，无到点后台定时器；无统一手动操作审计；性能预算尚未按规定数据量与 10 分钟流程验收。Hermes 历史客户端发现过三工具，本版四工具已有隔离 stdio 验证，会话需刷新；Codex 有用户环境接入记录，本次未重测，Claude Code、OpenCode、Cursor、Cline、Roo 的真实客户端未验证，WorkBuddy 可按通用 stdio 配置尝试，需其自身信任确认和 MCP 重载；专用发现与自动配置未实现，真实客户端未验证。可运行 `python3 scripts/check-launch.py` 隔离验证真实 app 和 CLI。

- [外部智能体接入操作指南（含可复制提示词）](docs/agent-integration-guide.md)
- [多智能体连接中心与 MCP](docs/mcp-connections.md)
- [首次点击授权与连接](docs/click-onboarding.md)

- [简要需求](docs/requirements.md)
- [轻量架构](docs/architecture.md)
- [开发计划](docs/roadmap.md)

界面：简体中文、扁平、低干扰。技术方向：SwiftUI + AppKit + SQLite。

## 版本管理

本项目必须使用 Git；不以复制文件作为代码版本管理方式。main 保持可用，功能使用 feat/*、修复使用 fix/* 分支；提交应说明目的与验证。密钥、录音、聊天记录、用户数据库和构建产物不提交。

## 开源参考

- https://github.com/swiftbar/SwiftBar ：菜单栏摘要与展开交互。
- https://github.com/felixhageloh/uebersicht ：桌面信息呈现。
- https://github.com/BUG-gao/floating-todo ：置顶待办窗口形态。

目前只参考交互思路，未复制上述项目代码。复用前核对具体文件及许可证。
