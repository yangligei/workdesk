# 原生 MVP 验证

环境：Apple Silicon，macOS 27.0.1，Apple Swift 5.10，Command Line Tools。

- `swift run CoreChecks` 与 Release `CoreChecks` 均通过：空名称拒绝、参数绑定（含单引号名称）、持久化 CRUD、过期版本拒绝且不覆盖正式状态、级联删除、外键约束。
- `bash scripts/build-app.sh` 成功，产物 `dist/Workdesk.app`，本机 arm64 Release，ad-hoc 签名。
- `codesign --verify --deep --strict dist/Workdesk.app` 通过。
- 使用 `WORKDESK_DATA_DIR` 指向 TMPDIR 下隔离样例启动 3 秒：进程存活，数据库创建，stderr 为空；验证结束终止该样例进程。未访问真实项目、聊天、音频或正式 Workdesk 数据库。
- 包体文件合计 292090 字节。3 秒处单次 ps RSS 为 99280 KiB、CPU 为 0.1%；此为启动冒烟采样，不能代替要求的 10 分钟空闲物理内存/CPU/唤醒验收。
- `git diff --check` 通过。
- `swift test` 受环境阻塞：XCTest not available，当前 Command Line Tools 无 SDK PlatformPath；保留 XCTest 用例供完整 Xcode 环境运行。

尚未进行可视界面和按钮交互验收；菜单栏、置顶和关闭窗口行为需进一步实际操作确认。未实现事件收件箱、QQ、会议和模型接入。下一阶段补编辑/阶段管理及标准数据量性能测量。
