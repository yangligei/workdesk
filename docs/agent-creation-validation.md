# 智能体创建流程验证

> 版本注记（2026-11-05 文档同步）：下文保留当时实现与验证事实，不是当前操作指南。当前已提供持久化首次授权、四工具 MCP 项目创建及会议 AI 审核；手动新增入口已移除，项目与任务状态独立。请按[用户指南](user-guide.md)及[接入指南](agent-integration-guide.md)操作。本次仅校验文档，未重跑下列历史构建或客户端测试。


本次撤回 2ba1be5 的日历、截止编辑、通知设置与提醒调度，保留签名协议及旧数据库字段。采用 b195126 的项目编辑布局，移除手动新项目、新任务、浮窗快速添加、会议草稿直接入库入口。草稿标题现在只读，避免无保存操作的编辑框。

实际验证命令：

```sh
scripts/build-app.sh
.build/release/CoreChecks
scripts/test-agent-simulator.sh
python3 scripts/check-launch.py
codesign --verify --deep --strict dist/Workdesk.app
git diff --check
```

以上均通过。CoreChecks 覆盖默认拒绝项目创建、独立本机授权与撤销、创建事件重放、别名冲突、创建后任务映射、跨项目任务和会议草稿拒绝、签名篡改、旧密钥失效、收件箱、CRUD、持久化。模拟器从空数据目录登记、默认拒绝、授权、重复项目创建、任务创建与进度上报；不是实际 Hermes 连接。

应用启动检查使用临时目录中的旧 schema 样例，验证迁移、离线补扫、实时目录事件、回执与项目快照，并确认旧 deadline/timezone/reminders 值原样保留。测试没有访问真实 Workdesk 数据或修改 Hermes 配置。应用保持原生单进程，无新增服务或轮询。

Swift 5.10，arm64。`swift test` 实际尝试失败：当前 Command Line Tools 缺少 XCTest（`error: XCTest not available`）。CoreChecks 是已编译并运行的独立验证，不声称 XCTest 通过。已验证进程启动和协议更新；本次没有进行截图或人工点击视觉验收，没有测量性能。

构建产物为 dist/Workdesk.app（ad-hoc 签名）。已有系统投递通知不主动访问或清除；移除调度后应用不再新建提醒。旧截止列继续作为兼容数据保留。所有本机管理能力仍遵循可信同一系统用户边界，不是远程多租户隔离。
