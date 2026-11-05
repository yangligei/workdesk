# 外部智能体接入 Workdesk 操作指南

把本文交给支持本机 stdio MCP 的智能体即可。目标是：先识别当前身份可用的项目，在明确授权范围内记录进展或创建待办，再核对真实回执。工具已经出现在客户端时，无需写代码或重配连接。

## 1. 用户先提供什么

提供目标项目名称或已知 alias、这次要记录的进展／新增待办、允许使用的资料范围。项目名可能重名，应以查询返回的 alias 确认目标。用户可以说：

> 请先查询 Workdesk 当前授权项目，找到“示例项目”。记录进展“初稿已整理，等待审核”，并新增待办“核对发布清单”。仅使用我本次提供的内容；先报告目标和权限，执行后返回回执。

相对日期以**原始请求或原始会议日期及其时区**解释，记录明确日期；重试、重开会话不能把“今天”改成重试当天。日期依据缺失或有歧义时先询问，不猜截止时间。

## 2. 先检查工具，再处理连接和授权

1. 查看客户端是否暴露 `workdesk_projects`、`workdesk_progress`、`workdesk_task_create`、`workdesk_project_create`（有些客户端会加服务器名前缀）。已暴露时直接查询，无需编写适配代码。
2. 调用 `workdesk_projects`，只使用返回的项目和权限；优先复用已有身份与映射，不能因查询为空就重新登记身份。
3. 根据 title 找到目标，使用该条的 **alias**。多条匹配时请用户选择。查询为空表示当前身份没有可见授权项目，不能据此断言工作台没有项目。
4. 需要其他范围时明确询问：“请在本机 Workdesk 连接中心为当前身份授权目标项目；如需新增待办，请另外开启创建待办权限。完成后我重新查询。”可以询问用户希望授权哪个项目、是否仅允许记录进展；不扩大到全部项目。

项目绑定、项目 MCP 授权及新增待办权限必须由本机用户在连接中心点击。QQ／远程聊天中的“同意”不能替代本机操作。智能体不得写数据库、更改 grant、执行管理命令自行授权，也不得用重新 enroll 轮换私钥来修复连接。共享身份的客户端共享该身份授权范围。

### 工具尚未出现时，本机用户操作

打开 Workdesk 菜单 →「设置与接入…」→「智能体连接中心」：

1. 选择有效的已有身份；没有身份时才点「创建新的本机身份」。在「首次授权与权限管理」按需勾选「允许创建新项目」（默认关闭）和「允许创建待办」，有目标项目时选择「同时授权当前项目」，点击「授权所选范围并记住」。空工作台可直接授权创建新项目。
2. 选择客户端，点「预览并配置…」，核对目标配置，点「确认添加配置」。通用 MCP 使用「查看通用配置」后在客户端导入。
3. 首次授权已保存所选范围，无需再次绑定或手写 grant-create。后续可在当前项目 MCP 区单独调整／撤销项目权限，也可在顶部撤销创建新项目权限；两类范围独立。
4. 点「运行 MCP 握手并写入测试动态」，检查 `accepted` 并回到项目核对。这会真实写入一条测试动态。
5. 在对应客户端刷新 MCP／重开会话；客户端可能需要重启或重新加载配置。再次发现工具并实际调用。移动应用后需检查配置中可执行文件的位置。

本机按钮只证明 Workdesk 自身子进程及存储路径可用，不能代替第三方客户端的实际调用验证。

### 项目不存在怎么办

先确认用户确实要新建项目及其标题。首次本机已勾选并保存「允许创建新项目」时，调用 `workdesk_project_create`，提供未占用 alias、title 和稳定 event_id。

创建成功时，项目、绑定及 MCP 许可在同一事务提交，立即出现在 `workdesk_projects`；自动允许动态，待办权限仅继承首次本机选择。没有创建许可时返回 rejected / isError，指引用户在连接中心授权，智能体不能自行改权限。既有项目的授权不会因新项目权限变化而扩大。

## 3. MCP 连接形式与支持范围

Workdesk 是 macOS 本机 stdio 服务，无网络监听。客户端启动 `WorkdeskCLI mcp` 子进程，负责 `initialize` → `notifications/initialized` → `tools/list` → `tools/call` 生命周期和逐行 JSON-RPC framing。不要把普通工具调用 JSON 直接当作已完成初始化的 stdio 会话。

通用配置的结构如下；尖括号是占位符，必须用连接中心预览里的本机实际值替换。JSON 不展开 `$HOME` 或 `~`，不要照抄占位符运行，也不要把凭据内容填进去。

```json
{
  "mcpServers": {
    "workdesk": {
      "command": "<Workdesk.app所在目录>/Workdesk.app/Contents/MacOS/WorkdeskCLI",
      "args": ["mcp", "--source", "<已有身份名>", "--token-file", "<已有凭据文件路径>", "--data-dir", "<Workdesk数据目录>"]
    }
  }
}
```

`--token-file` 是文件路径，私钥只由 Workdesk 本机签名代码读取。不要打印、索取、提交或转发私钥。应用和子进程须指向同一个数据目录。连接中心按客户端生成配置：Hermes／Codex 使用官方 CLI，Claude Code 使用用户级 stdio 配置，OpenCode 使用 `mcp` 下的 local command 数组；不能把通用 JSON 原样覆盖这些客户端的原配置。优先使用本机预览及[连接说明](mcp-connections.md)，同名配置冲突时先检查已有条目。

| 客户端 | 当前代码支持的接入路径 | 验证边界 |
| --- | --- | --- |
| Hermes | 官方 `hermes mcp add` | 历史版本真实客户端发现 3 工具；本版本 4 工具已用隔离 stdio 验证，会话需刷新 |
| Codex | 官方 `codex mcp add` | 已有用户环境成功接入记录；不代表所有版本／环境均已验证 |
| Claude Code | 官方 `claude mcp add` | 有配置适配代码；本文未进行真实客户端实测 |
| OpenCode | 全局 JSON 的 `mcp` local 配置 | 有配置适配代码；本文未进行真实客户端实测 |
| 通用 MCP／Cursor／Cline／Roo | 支持本机 stdio 的客户端导入配置 | 通用协议与子进程已有验证；各具体客户端需实际验证 |
| WorkBuddy | 无已核实的接入实现 | 不宣称已支持 |

仓库旧文档中的“本机未安装／未实测”是当时验证记录，不能用于推断用户现在的安装情况。本文是操作指南，不声称重新测试了上述所有客户端。“已发现”“已配置”“已授权”“本次 accepted”分别验证不同环节。

## 4. 四个工具的完整输入 schema

以下 `inputSchema` 与 `Sources/WorkdeskCore/MCP.swift` 一致。没有任务列表、进展读取、完成、改状态、改名或授权工具。`workdesk_projects` 仅列授权范围，不返回任务或历史动态。

```json
{
  "name": "workdesk_project_create",
  "inputSchema": {
    "type": "object",
    "properties": {
      "alias": {"type": "string", "minLength": 1, "maxLength": 128, "description": "新项目稳定别名，最多128 UTF-8字节，无首尾空白，不可覆盖已有绑定"},
      "title": {"type": "string", "minLength": 1, "maxLength": 32000, "description": "非空项目标题，最多32000 UTF-8字节"},
      "event_id": {"type": "string", "minLength": 1, "maxLength": 128, "description": "稳定操作ID，重试保持不变，最多128 UTF-8字节"}
    },
    "required": ["alias", "title", "event_id"],
    "additionalProperties": false
  }
}
```

```json
{
  "name": "workdesk_projects",
  "inputSchema": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  }
}
```

```json
{
  "name": "workdesk_progress",
  "inputSchema": {
    "type": "object",
    "properties": {
      "alias": {"type": "string", "description": "workdesk_projects 返回的授权别名"},
      "text": {"type": "string", "minLength": 1, "maxLength": 32000},
      "event_id": {"type": "string", "minLength": 1, "maxLength": 128}
    },
    "required": ["alias", "text", "event_id"],
    "additionalProperties": false
  }
}
```

```json
{
  "name": "workdesk_task_create",
  "inputSchema": {
    "type": "object",
    "properties": {
      "alias": {"type": "string", "description": "workdesk_projects 返回的授权别名"},
      "text": {"type": "string", "minLength": 1, "maxLength": 32000},
      "event_id": {"type": "string", "minLength": 1, "maxLength": 128}
    },
    "required": ["alias", "text", "event_id"],
    "additionalProperties": false
  }
}
```

运行时还有 UTF-8 **字节数**限制：alias 非空、无首尾空白且不超过 128 字节，event_id 去空白后非空且不超过 128 字节，text／title 去空白后非空且不超过 32000 字节。多字节中文不能按字符上限估算。禁止添加 `projectID`、`taskID`、日期、状态等额外参数。

## 5. 精确调用与回执

以下是初始化完成后传给 `tools/call` 的 `params` 对象；客户端通常让你直接选择工具并填 `arguments`。若自己实现 JSON-RPC 客户端，外层需包含 `jsonrpc: "2.0"`、唯一请求 `id`、`method: "tools/call"` 和这里的 `params`。

先查询：

```json
{"name":"workdesk_projects","arguments":{}}
```

返回的 `result.content` 中 `type: "text"` 的 `text` 是 JSON 编码的项目数组，条目字段为 `alias`、`title`、`canCreateTasks`。例如仅当真实返回 alias 为 `demo` 时，才可使用下面示例；不能把示例当作真实授权。

```json
{"name":"workdesk_progress","arguments":{"alias":"demo","text":"初稿已整理，等待审核","event_id":"request-001-progress-01"}}
```

仅当目标条目 `canCreateTasks: true` 且用户要求创建任务时：

```json
{"name":"workdesk_task_create","arguments":{"alias":"demo","text":"核对发布清单","event_id":"request-001-task-01"}}
```

alias 是当前身份下的项目映射别名；数据库项目 UUID 是另一种标识。签名事件的历史字段名 `projectID` 实际承载 alias，不能把 UUID 或显示标题当作 MCP alias。项目查询不返回 UUID；任务创建成功回执的 `detail` 是新任务 ID。

写入工具的 `result.content[].text` 是 JSON 编码的回执，字段为 `eventID`、`outcome`、`detail`。检查事件 ID 与本次请求相符，再解释 outcome：

| outcome | 含义与处理 |
| --- | --- |
| `accepted` | 已接受并存储；进展仅记录文字，新增任务只建立待办，不更改完成状态 |
| `rejected` | 未接受；检查本机身份、映射、MCP 许可、创建待办权限及 detail，处理后重试原事件 |
| `conflict` | 未写入本次不同操作；MCP 下通常是相同 event_id 已用于不同项目／类型／文字。核对原操作，不能自动覆盖或换 ID 反复创建 |

每个逻辑操作分配一个稳定且唯一的 event_id，并保留 alias、工具名、text；网络中断或回执不明时原样重试。不要为每次尝试生成新 ID，也不要把一个 ID 用于进展和任务两种操作。同身份、同 ID、同操作返回原回执；同 ID 改内容返回 conflict。撤销权限后重放仍会被拒绝；幂等不会绕过当前权限。若用户明确修改了操作，核对原结果后为新操作分配新 ID。

`isError: true`、JSON-RPC `error` 或普通错误文字都不能报成功；错误文字可能没有结构化回执。错误也可能发生在存储提交后的通知阶段，因此回执不明确时仍应沿用同一 ID 重试。

## 6. 成功后的验证与数据边界

MCP 写入在子进程内直接调用 Store 接收事件，不依赖 Workdesk 图形应用运行，也不是排队等待 app 消费 inbox。写入后生成 receipts 文件以通知正常项目视图刷新。app 未运行时稍后打开同一数据目录查看；运行时目录通知应触发刷新，必要时点击「刷新」。不要仅凭这段实现描述声称已亲眼验证页面。

拿到 accepted 后，回到目标项目查询／查看：进展核对「最近进展」，任务核对待办标题；若已获准使用本机 UI，可自行验证，否则请本机用户核对并明确标注“回执已验证，页面待核对”。当前 MCP 没有读取进展／任务的工具，不能伪造查询能力，也不要改读全库来绕过范围限制。

只读取这次接入所需的配置结构和已授权资料，不扫描无关聊天、记录或其他项目。进展文字会进入事件审计，不放私钥、聊天全文或无关个人信息。不转发全工作台数据到远程聊天。任务及项目的正式状态由本机用户操作，智能体“已完成”的文字只是一条进展。

自检清单：

- 当前会话发现四个工具，查询返回目标 alias，新增待办时权限为 true。
- 操作在用户目标与资料授权内；事件 ID 已保存且重试不变。
- 本次回执 eventID 匹配且 outcome 为 accepted；没有把配置成功当成写入成功。
- 目标页面内容已核对，或准确报告尚待本机核对。
- 报告包含目标 alias、动作、eventID、outcome 与必要 detail，不包含密钥或无关数据。

## 7. 可复制给智能体的提示词

```text
请协助我接入并使用 Workdesk。
目标项目：<名称或已知 alias>
本次目标：<要记录的进展、要新增的待办>
允许使用的资料：<本次消息／指定文件等范围>
原始请求日期与时区：<明确日期和时区；有相对日期时填写>

先检查当前会话的 Workdesk MCP 工具。若已生效，直接调用 workdesk_projects，
按返回的 title 与 alias 识别已有授权映射，使用最小范围；不要重新登记身份。
项目不明确时请我选择；查询为空或缺权限时，说明所需范围，指引我在本机
Workdesk 连接中心点击项目绑定和 MCP 授权。创建待办还需单独开启权限。
远程聊天同意不能替代本机授权。不要写数据库、改 grant、轮换私钥或自行授权。
若项目确实不存在，先确认新建意图；本机已有创建新项目授权时调用
workdesk_project_create（alias、title、稳定 event_id），否则指引用户在连接中心授权。

在已授权目标内按我的要求调用 workdesk_progress／workdesk_task_create。
每个逻辑操作使用独立稳定 event_id，保存 alias、工具名和 text，重试原样复用。
只以本次匹配 eventID 的 accepted 回执报告已写入；rejected/conflict 时解释原因。
进展只记录，新增任务只建待办，正式完成和状态变更由本机用户确认。
接受回执后核对目标项目页面；没有 UI 能力则明确报告页面待本机核对。
不读取无关聊天或全工作台数据，不打印私钥，不提交凭据，不泄露个人记录。
相对日期固定依据原始消息日期和时区，不能改用重试日期。
最后简洁返回目标 alias、动作、eventID、outcome 和页面验证结果。
```

## 8. 可选 CLI 适配

优先 MCP。只有已明确授权的可信本机适配器，且已有身份、映射和凭据路径时，才使用[签名事件协议](event-protocol.md)的 CLI 写入流程；CLI 权限模型不同，不能用它绕过 MCP 的创建任务限制。以下变量由本机操作者提供，不读取私钥内容：

```sh
# CLI、WORKDESK_DATA_DIR、SOURCE、ALIAS、TOKEN_FILE、EVENT_ID 均为已有且经授权的值。
export WORKDESK_DATA_DIR
"$CLI" report --source "$SOURCE" --alias "$ALIAS" --type progress \
  --text '初稿已整理，等待审核' --event-id "$EVENT_ID" --token-file "$TOKEN_FILE"
# 将上一命令返回的纯文件名保存为 RECEIPT_FILE；排队不等于 accepted。
"$CLI" receipt "$RECEIPT_FILE"
```

CLI report 写 inbox，运行中的 app 消费后才有结果；app 退出时等待启动补扫，离线处理交由可信本机操作者安排，不与 app 并发 drain。CLI 的 report／receipt 使用环境变量数据目录，不能照搬 mcp 的 `--data-dir` 参数。CLI 重试语义与 MCP 有差异，必须复用原事件和签名，详见事件协议；不要对改过内容的事件重用 ID。

不要把 CLI `projects` 或 `projects.json` 当成授权查询替代品，它们包含全部本地项目。外部智能体不应获得 enroll、bind、grant-create 等管理能力。日常 MCP 使用无需 CLI 脚本。

相关文档：[中文用户指南](user-guide.md#连接智能体) · [多智能体连接中心与 MCP](mcp-connections.md) · [签名事件协议](event-protocol.md)
