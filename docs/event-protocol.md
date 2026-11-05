# 本地签名事件协议 v1

无网络监听、无常驻服务、不依赖 Hermes 内部模块。通用适配器仅显式上报调用方提供的文字，不读取日志或聊天；会议识别另经用户授权调用 Hermes 公共单次 CLI，QQ 未自动连接。

## 登记与使用（可信本机操作者的旧 CLI 参考）

日常首次接入请使用[点击授权](click-onboarding.md)。以下 local-agent、demo 均为示例占位身份与别名，不代表当前真实身份；不要重新 enroll 已有身份来修复连接，外部智能体不执行这些登记管理命令。

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

JSON camelCase 字段：schemaVersion=1、eventID、sourceID、projectID（绑定别名）、taskID（可选）、occurredAt（ISO8601）、type、text、expectedVersion（可选）、signature（Base64）、transport（可选，MCP 为 mcp）。Ed25519 签名内容按如下顺序：schemaVersion、sourceID、projectID、taskID 或空串、occurredAt、type、text、expectedVersion 或空串、eventID。每个字段编码为 UTF-8 字节长度、冒号、字段值，字段之间以竖线连接。若存在 transport，在 eventID 后追加 transport 字面字段及其值，使用同样长度编码；该标记纳入签名。CLI report 负责签名；submit 接收已签名 JSON。

先验证签名和当前来源/别名授权，再查询 sourceID+eventID 去重，未签名重放不能取得 accepted。有效重复返回首次回执；必须复用同一事件与签名重试。report 默认生成新 eventID，可用 --event-id 指定重试 ID。相同 ID 的再次签名内容仍按首次结果处理；不要跨逻辑操作重用 ID。task.rename 只可修改映射项目内的任务，并检查 expectedVersion。progress 仅记录；task.create 创建待办；任务完成必须本地确认。拒绝未授权项目、外部完成及不支持类型。

## 文件与边界

根目录及 inbox/receipts/ 为 0700，新输入原子写入随机 .json；限制 64 KiB，以 O_NOFOLLOW/fstat 拒绝链接、超大或非普通文件。事务成功后写回执，再移除输入；存储失败保留输入，提交后回执失败可以重放。目录事件驱动，无轮询；目录被替换后须重启。无断电 fsync 保证、目录替换强隔离、磁盘配额或跨进程单实例锁。

同一 macOS 用户仍可读取文件和修改数据库，不是远程、多租户或同用户恶意进程隔离。只对可信本机调用方提供 CLI。projects / projects.json 包含全部本地项目及截止设置，不是按来源过滤的远程查询，禁止直接转发 QQ。审计存原始事件文本；调用方不要把密钥放入文字。UI 仅展示最近 200 条，底层暂无自动清理。手动操作暂无统一审计。

旧会议的标记草稿及 `draft.confirm --task-id DRAFT_ID` 保留兼容，检查所属项目并幂等确认。新会议收件箱支持普通转写文字，通过已安装的 Hermes 公共单次 CLI 生成带逐字证据的审核草稿；用户确认后使用当前来源与现有 MCP 权限签名提交 task.create/progress。没有音频转写或自动新项目，详见 [会议 AI 审核](meeting-ai.md)。

## 从空工作台接入：优先 MCP

本机用户在连接中心选择有效身份（没有时点击创建），勾选「允许创建新项目」（默认关闭）及所需待办权限，点击「授权所选范围并记住」。然后配置客户端并刷新 MCP；四工具的独立可用指南、完整 schema 与调用示例见[智能体接入指南](agent-integration-guide.md)。创建工具参数为 alias、title、event_id；创建后的项目自动获得动态许可，待办继承创建时的本机选择。项目、绑定、MCP 许可和事件记录原子提交。

### 旧 CLI 权限模型（历史兼容）

旧版本由可信本机操作者使用 `grant-create` 管理来源级 project.create 许可；该命令仍保留兼容，**不等同 MCP 创建授权**。MCP 还要求独立的新项目授权记录，旧 CLI 创建不会自动生成 MCP 项目许可。不得把管理命令交给智能体执行，也不得改数据库来补授权；日常接入由用户在连接中心点击一次保存范围。

原签名 `report --type project.create` 的 text 是项目标题、alias 是未占用别名；与 MCP 的 title 参数不同。仅在可信本机操作者已经明确安排的旧适配中使用。创建许可不允许覆盖映射，签名和当前范围检查发生在去重前；撤销后旧事件不能恢复许可。MCP 会比较原 alias、类型、文字和 transport，同 ID 不同操作返回 conflict；普通旧签名协议仍返回首次回执，不应混用两者重试语义。

界面不手动创建项目、任务；会议 AI 只审核真实智能体建议，再经显式本机确认和已授权的签名协议入库。日历、截止编辑和提醒流程已撤回；旧数据库的 deadline/timezone/reminders 数据原样保留，不删除列、记录或降 schema 版本。应用不再安排提醒。QQ 未自动接入，调用方必须明确配置上述 CLI 命令。
