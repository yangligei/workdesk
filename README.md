# Workdesk · 工作进度台

轻量 macOS 菜单栏与置顶悬浮窗，汇总个人任务、智能体进度和会议待办。

状态：需求与架构设计阶段，尚未实现应用和机器人接口。

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
