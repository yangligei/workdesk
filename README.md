# Workdesk · 工作进度台

轻量 macOS 菜单栏与置顶悬浮窗，汇总个人任务、智能体进度和会议待办。

状态：原生项目/阶段编辑、原子文件事件收件箱与 CLI、来源映射和事件审计、会议文字证据草稿已实现。QQ 明确未连接。

## 编译与运行

要求 macOS 13+、Swift 5.9+。无第三方运行时依赖，使用系统 SQLite。

```sh
swift run CoreChecks
bash scripts/build-app.sh
open dist/Workdesk.app
```

完整 Xcode 环境还可执行 `swift test`；仅 Command Line Tools 的机器可能缺少 XCTest，使用 `CoreChecks` 验证核心行为。

已实现中文管理窗口、菜单栏、置顶窗、创建/删除项目、创建/删除任务、手动任务状态和版本冲突保护。删除项目会先确认，再级联删除任务。完成状态只由手动选择触发。

默认数据在 `~/Library/Application Support/Workdesk/workdesk.sqlite`。设置 `WORKDESK_DATA_DIR` 可指定隔离样例目录。关闭窗口后可从菜单栏重新打开；退出菜单结束应用。打包脚本生成本机架构的 Release `.app` 并作 ad-hoc 本地签名，未进行公证。

项目和任务由登记并授权的智能体通过签名协议创建；本机保留改名、阶段、状态和删除操作。日历、截止与提醒流程已撤回，旧数据库字段原样保留。会议文字可生成证据草稿，正式任务由授权智能体发送 draft.confirm 创建。接入步骤见 [事件协议](docs/event-protocol.md)。

当前限制：尚未接入真实智能体/QQ、音频转写或模型；无统一手动操作审计；性能预算尚未按规定数据量与 10 分钟流程验收。可运行 `python3 scripts/check-launch.py` 隔离验证真实 app 和 CLI。

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
