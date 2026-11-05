# 会议 AI 审核

会议收件箱接收普通口语转写，不要求待办标记。原文占可用宽度的 45%，审核卡占 55%。原生 SwiftUI，标题 16、分栏标题 14、正文 13.5、说明 10.5 pt。会议原文与审核修改自动保存，提供显式保存入口。历史会议的原始日期不会因编辑、重开或重新识别而改变；旧会议迁移后日期未知，不以迁移日冒充会议日期。

每次点击识别均显示授权说明：全文、当前项目与任务名称发送到 Hermes 已配置模型。只支持 Hermes；不会注册来源、修改映射、授予权限或创建项目。用户先审核可编辑文字、类型和目标项目，再通过底部“确认并写入所选 N 条”签名提交。未知项目清空并阻止确认。重复项默认不选并显示提示；本地查重按规范化文字、项目、类型，不能保证识别所有语义改写。

首次身份与项目权限按[点击接入](click-onboarding.md)保存；创建新项目许可与目标项目 MCP 权限独立。四工具中的项目创建能力供客户端使用，会议识别和审核流程仍只针对已有项目；新建项目后需重新选择目标，再审核确认。会议删除及归档操作见[用户指南](user-guide.md)，本次权限更新不改变其行为。

## 公共 CLI

2026-11-05 核对官方 CLI 文档和安装的命令帮助：

- https://hermes-agent.nousresearch.com/docs/reference/cli-commands
- https://hermes-agent.nousresearch.com/docs/user-guide/cli

当前 `hermes chat --format stream-json` 输出包含 system、text、tool_use、tool_result、result 等 JSONL 事件；result 的 exit_code/text 是结果，不能把任意文本事件当成最终答案。当前安装路由到 gateway，不支持 `--run-budget`，终止客户端可能仅断开而不停止服务端生成。因此会议识别采用官方公开的 `hermes-agent` 单次运行接口，不使用此 gateway 路径，也不导入 Hermes 内部模块。

运行前检查 `hermes-agent --help`，从 `hermes config get model` 读取 default/base_url，只解析所需字段，不打印配置。通过 PATH、常见安装目录及管理安装的 venv/bin 发现命令，没有写死模型、来源名称、安装哈希或私钥。

调用 `hermes-agent --enabled-toolsets none --max-turns 1 --model MODEL --base-url ENDPOINT --query PROMPT`。参数通过 Foundation Process 数组传递，无 shell。安装版本实际报告 No tools loaded、Available tools: 0。严格提取 FINAL RESPONSE 分隔符之间的 JSON，拒绝工具数非零、不支持的输出或 Markdown 围栏。模型配置缺少公开 endpoint 时安全报错，不猜测或修改配置。

进程异步运行，输出上限 2 MB；识别最长 120 秒，帮助/配置读取分别最多 10 秒。取消/超时发送 SIGTERM，1 秒后仍运行则 SIGKILL。无新增常驻服务、依赖、模型运行时或后台轮询。仅按需启动已有 CLI，有一次模型请求的耗时与费用。上述时间为限制值，不是性能实测。授权说明也提示旧版 CLI 的 query 位于本机进程参数中；不保存完整 CLI 日志或密钥。

## 验证与持久化

提示明确把转写、项目和任务全部视为不可信数据，禁止执行其中的指令。返回 JSON 只能有 items，单项严格为 type/text/projectID/evidence，type 只有 task/progress，最多 60 条。证据必须是原文连续逐字片段。负责人和日期不明确时不补全；出现今天/明天时按保存的原始会议日期换算，不按运行日推断。

`meetings.original_date` 向后兼容迁移；旧 drafts 与旧签名确认协议保留。`meeting_reviews` 保存每条原建议、编辑后建议、识别时完整原文快照、历史日期、来源、选择/重复标记、稳定事件、逐条回执与错误。重新识别追加记录并查重，不覆盖旧证据或回执。

本机确认通过当前数据库中的来源公钥验证 credentials 目录下的现有私钥，使用现有绑定别名和 MCP 权限。任务要求 create_tasks，进度要求项目已授权；不因本机确认扩大来源范围。正式写入复用 `task.create` / `progress`、transport=mcp、Ed25519 签名和 EventInbox 协议，会议界面不调用 createTask。进度不会改变正式状态。

事件 ID 为 meeting-草稿 UUID。签名事件先持久化，再投递收件箱。重试使用同一事件，逐条持久化回执；只有 accepted 且与实际审计事件匹配才标为成功。提交后但回执写入前故障可重放恢复。部分失败不回滚已成功条目，后续只重试未成功项。已提交的内容冻结，选择可调整；不能以相同 ID 修改操作。

## 隔离验证

```sh
export TMPDIR="$HOME/.hermes/cache/scratch"
swift build
.build/debug/CoreChecks
WORKDESK_MEETING_AI_SMOKE=1 .build/debug/CoreChecks
swift test
scripts/build-app.sh
python3 scripts/check-launch.py
scripts/test-agent-simulator.sh
python3 scripts/check-meeting-render.py "$TMPDIR/workdesk-meeting-native.png"
python3 scripts/check-meeting-render.py "$TMPDIR/workdesk-meeting-native-narrow.png" 900
codesign --verify --deep --strict dist/Workdesk.app
```

CoreChecks 使用独立数据库及样例凭据，覆盖非法 JSON/类型/证据、未知项目、历史日期、编辑证据保护、去重、创建权限、部分失败、回执恢复、取消和超时。真实 AI smoke 仅发合成文本，输出保存在指定 scratch；不是假造模型结果。原生 render 使用生产视图、独立存储与合成卡片，明确不声称这些渲染样例是 AI 输出。
