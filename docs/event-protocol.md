# 本地签名事件协议 v1

无网络监听、无常驻服务、不依赖 Hermes 内部模块。通用适配器仅显式上报调用方提供的文字，不读取日志或聊天；会议识别另经用户授权调用 Hermes 公共单次 CLI，QQ 未自动连接。

## 登记与使用

```sh
CLI=dist/Workdesk.app/Contents/MacOS/WorkdeskCLI
"$CLI" projects
"$CLI" enroll --name local-agent --project PROJECT_UUID --alias demo --token-file "$HOME/.workdesk-credentials/local-agent.key"
"$CLI" report --source local-agent --alias demo --text '构建已结束，待人工验收' --token-file "$HOME/.workdesk-credentials/local-agent.key"
"$CLI" receipt 返回的文件名.json
```

应用与 CLI 必须使用相同 WORKDESK_DATA_DIR。enroll/projects/drain 会打开数据库；report/submit/receipt 仅使用文件协议。CLI 进程短命；drain 适合显式离线处理，避免和应用同时消费同一收件箱。report/submit 输出文件名只代表排队；receipt 中 accepted/rejected/conflict 才是结果。应用退出后事件等待启动补扫。

## 签名与授权

enroll 生成 Ed25519 私钥，使用 O_EXCL/O_NOFOLLOW 创建 0600 文件，拒绝覆盖既有文件或链接，数据库只保存公钥（历史列名 token_hash）。写文件失败不轮换身份，数据库事务失败删除新凭据。轮换用新的文件路径；同一来源旧签名立即失效，未处理旧事件会拒绝。来源的所有现有绑定保留，可在 UI 撤销。不得打印、提交或转发私钥。

JSON camelCase 字段：schemaVersion=1、eventID、sourceID、projectID（绑定别名）、taskID（可选）、occurredAt（ISO8601）、type、text、expectedVersion（可选）、signature（Base64）。Ed25519 签名内容按如下顺序：schemaVersion、sourceID、projectID、taskID 或空串、occurredAt、type、text、expectedVersion 或空串、eventID。每个字段编码为 UTF-8 字节长度、冒号、字段值，字段之间以竖线连接。CLI report 负责签名；submit 接收已签名 JSON。

先验证签名和当前来源/别名授权，再查询 sourceID+eventID 去重，未签名重放不能取得 accepted。有效重复返回首次回执；必须复用同一事件与签名重试。report 默认生成新 eventID，可用 --event-id 指定重试 ID。相同 ID 的再次签名内容仍按首次结果处理；不要跨逻辑操作重用 ID。task.rename 只可修改映射项目内的任务，并检查 expectedVersion。progress 仅记录；task.create 创建待办；任务完成必须本地确认。拒绝未授权项目、外部完成及不支持类型。

## 文件与边界

根目录及 inbox/receipts/ 为 0700，新输入原子写入随机 .json；限制 64 KiB，以 O_NOFOLLOW/fstat 拒绝链接、超大或非普通文件。事务成功后写回执，再移除输入；存储失败保留输入，提交后回执失败可以重放。目录事件驱动，无轮询；目录被替换后须重启。无断电 fsync 保证、目录替换强隔离、磁盘配额或跨进程单实例锁。

同一 macOS 用户仍可读取文件和修改数据库，不是远程、多租户或同用户恶意进程隔离。只对可信本机调用方提供 CLI。projects / projects.json 包含全部本地项目及截止设置，不是按来源过滤的远程查询，禁止直接转发 QQ。审计存原始事件文本；调用方不要把密钥放入文字。UI 仅展示最近 200 条，底层暂无自动清理。手动操作暂无统一审计。

旧会议的标记草稿及 `draft.confirm --task-id DRAFT_ID` 保留兼容，检查所属项目并幂等确认。新会议收件箱支持普通转写文字，通过已安装的 Hermes 公共单次 CLI 生成带逐字证据的审核草稿；用户确认后使用当前来源与现有 MCP 权限签名提交 task.create/progress。没有音频转写或自动新项目，详见 [会议 AI 审核](meeting-ai.md)。

## 从空工作台接入

本机用户执行登记和独立授权（不输出私钥；默认没有创建许可）：

```sh
"$CLI" enroll --name local-agent --token-file "$TMPDIR/workdesk-agent.key"
"$CLI" grant-create --name local-agent --allow yes
```

随后由智能体发送命令，使用同一数据目录与凭据文件：

```sh
"$CLI" report --source local-agent --alias release --type project.create --text '发布项目' --event-id project-001 --token-file "$TMPDIR/workdesk-agent.key"
# 运行中的应用自动处理；应用关闭时本机运行 drain。
"$CLI" drain
"$CLI" receipt 返回的文件名.json
# accepted.detail 是项目 ID，release 别名已在同一事务绑定。
"$CLI" report --source local-agent --alias release --type task.create --text '准备发布说明' --event-id task-001 --token-file "$TMPDIR/workdesk-agent.key"
"$CLI" report --source local-agent --alias release --type draft.confirm --task-id DRAFT_ID --text '草稿任务标题' --event-id draft-001 --token-file "$TMPDIR/workdesk-agent.key"
```

创建许可仅允许使用未占用别名创建项目，不允许覆盖已有映射，也不授予其他项目任务权限。相同事件 ID 重试返回原回执，不重复创建。CLI `--event-id` 允许调用方固定重试标识；修改操作使用新 ID。`task.rename` 还需 `--task-id ID --expected-version N`。本机用户可用 `grant-create --name local-agent --allow no` 撤销创建许可，UI 撤销单项目映射。智能体不能通过事件自行授权。CLI 管理命令仅供可信本机用户，不应作为远程代理能力暴露。

界面不手动创建项目、任务；会议 AI 只审核真实智能体建议，再经显式本机确认和已授权的签名协议入库。日历、截止编辑和提醒流程已撤回；旧数据库的 deadline/timezone/reminders 数据原样保留，不删除列、记录或降 schema 版本。应用不再安排提醒。QQ 未自动接入，调用方必须明确配置上述 CLI 命令。
