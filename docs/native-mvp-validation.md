# 原生 MVP 验证

> 版本注记（2026-11-05 文档同步）：下文保留当时实现与验证事实，不是当前操作指南。当前已提供持久化首次授权、四工具 MCP 项目创建及会议 AI 审核；手动新增入口已移除，项目与任务状态独立。请按[用户指南](user-guide.md)及[接入指南](agent-integration-guide.md)操作。本次仅校验文档，未重跑下列历史构建或客户端测试。


环境：Apple Silicon，macOS 27.0.1，Apple Swift 5.10，Command Line Tools。

- `swift run CoreChecks` 与 Release `CoreChecks` 均通过：空名称拒绝、参数绑定（含单引号名称）、持久化 CRUD、过期版本拒绝且不覆盖正式状态、级联删除、外键约束。
- `bash scripts/build-app.sh` 成功，产物 `dist/Workdesk.app`，本机 arm64 Release，ad-hoc 签名。
- `codesign --verify --deep --strict dist/Workdesk.app` 通过。
- 使用 `WORKDESK_DATA_DIR` 指向 TMPDIR 下隔离样例启动 3 秒：进程存活，数据库创建，stderr 为空；验证结束终止该样例进程。未访问真实项目、聊天、音频或正式 Workdesk 数据库。
- 包体文件合计 292090 字节。3 秒处单次 ps RSS 为 99280 KiB、CPU 为 0.1%；此为启动冒烟采样，不能代替要求的 10 分钟空闲物理内存/CPU/唤醒验收。
- `git diff --check` 通过。
- `swift test` 受环境阻塞：XCTest not available，当前 Command Line Tools 无 SDK PlatformPath；保留 XCTest 用例供完整 Xcode 环境运行。

以上为上一轮 MVP 记录。本轮实现事件收件箱/CLI、编辑/阶段、会议文字草稿，新增验证见下。QQ、音频和模型仍未接入。

## 事件与会议增量验证

- Debug 与 Release `CoreChecks` 通过：原有 CRUD 回归，项目阶段、来源映射、重复事件、过期事件版本、越权项目、外部完成拒绝、已提交事件重放回执、原子收件箱、损坏/超大/符号链接文件拒绝、未完成临时文件忽略、会议证据与重复确认。
- `bash scripts/build-app.sh` 成功；CLI 打包进 Contents/MacOS；`codesign --verify --deep --strict` 通过。
- `python3 scripts/check-launch.py` 通过：真实 Release app 使用 TMPDIR 隔离合成旧 schema 数据，迁移、启动补扫、运行中 CLI 目录通知、回执和项目缓存均通过，退出前进程存活、stderr 空；样例清理。
- 未进行可视控件交互验收或 10 分钟标准性能测量；不将引擎/进程结果称为 UI 验收。仅 CLT 的 XCTest 环境警告仍存在，使用 CoreChecks。
- 没有访问真实聊天/音频/项目数据库，没有修改 Hermes 配置、发送消息或推送 Git。
