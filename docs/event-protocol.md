# 本地事件协议 v1 与 QQ 接入边界

当前实现使用 JSON 的 **camelCase** 字段（下例是实际编码），不依赖 Hermes 内部模块，不监听网络，不安装服务。应用退出或休眠期间不处理事件；再次启动补扫。CLI 是短命进程，从不打开正式数据库。

## 使用

在应用「项目任务」选择项目，进入「来源与事件」，绑定来源 ID 与生产者项目别名。绑定只准许该来源/别名访问指定项目，可撤销。

```sh
# 与应用设置相同的 WORKDESK_DATA_DIR；未设置时使用默认 Application Support/Workdesk
CLI=dist/Workdesk.app/Contents/MacOS/WorkdeskCLI
"$CLI" projects
"$CLI" report local-agent demo '构建已结束，待人工验收'
"$CLI" submit event.json
"$CLI" receipt 返回的文件名.json
```

report/submit 输出队列文件名，**不代表应用已接受**。应用运行后读取 receipt；不存在表示尚未处理（CLI 非零退出）。不自动等待、不循环重试。重试同一逻辑操作必须保存并复用 sourceID/eventID；report 每次调用产生新 ID。

```json
{
  "schemaVersion": 1,
  "eventID": "stable-request-001",
  "sourceID": "local-agent",
  "projectID": "demo",
  "occurredAt": "2026-11-03T01:00:00Z",
  "type": "task.rename",
  "text": "更新任务标题",
  "taskID": "应用中的任务 UUID",
  "expectedVersion": 1
}
```

支持 progress（只记录）、task.create（创建待办）、task.rename（必须 taskID/expectedVersion，保留状态）。任务完成、阶段变化、执行结束推断均不支持。修改命令在事务内检查版本，旧版本返回 conflict。乱序 progress 只保留原始来源时间，不回退状态。回执为 eventID/outcome/detail，outcome 为 accepted/rejected/conflict；detail 在创建成功时包含任务 ID。重复键 sourceID+eventID 返回首次回执，即使重复内容变化也不再执行；提交后回执写失败可安全重放。

## 文件与恢复

同一数据目录下 inbox/、receipts/，新建目录权限 0700。生产者写临时文件，再原子改名为随机 .json；CLI 使用 Foundation 原子写。应用只读取 .json，最大 64 KiB，O_NOFOLLOW + fstat 拒绝链接、非普通文件及超大文件。成功事务后原子写回执再移除输入；数据库故障保留输入。无效文件生成拒绝回执并移除输入，符号链接仅移除链接本身。保留最近 200 条数据库事件的 UI 视图，底层事件及回执暂无自动清理。

目录监听采用 DispatchSource，启动补扫，读取期间收到通知会追加扫描，无周期轮询。目录被外部替换后须重启应用恢复监听。事件/快照文件 I/O 在 actor 上执行。当前未提供断电 fsync 保证、强对抗目录替换防护、磁盘配额和跨进程单实例锁；不要同时运行多个使用同一目录的应用。

## 来源、安全与快照

来源映射是可信本机生产者的授权配置，**不是身份认证**。尚未实现来源令牌。相同 macOS 用户可伪造来源或读取文件；不作为多租户/远程权限边界。根目录及协议子目录不可使用符号链接；祖先目录必须由用户控制，不能对抗同用户并发目录替换。错误消息不包含事件内容；事件审计保留来源、项目、原文、来源/接收时间和处理结果。手动 CRUD 与绑定变更尚无统一操作审计。

projects.json 是应用生成的本地缓存，包含全部项目 ID、名称、阶段和版本，不包含任务/会议正文；关闭应用后可能过时。它并非按来源过滤的远程回复，也不可直接转发到 QQ。

## QQ：未连接

本版本没有验证或启用任何 QQ 桥接、发件人身份、消息接收或发送能力。拟议适配器须通过公开扩展点：验证发件人 → 限定 sourceID/projectID → 用稳定消息 ID 去重 → 写事件 → 消费回执 → 按渠道权限构造有限回复。eventID 可作请求关联；队列文件名仅是本机回执位置。接入前还须实现令牌/身份绑定与按项目授权的查询回复，并实测重投及离线行为。不可把该本地 CLI 直接暴露为任意远程文件或 shell 接口。

## 会议文字

「会议草稿」按当前项目保存文字与版本，仅显式待办标记生成草稿，不调用模型。原文中的时间戳与行号作为证据保留；没有时间戳则仅显示行号。草稿标题可编辑，逐项确认后事务内创建待办并关联任务 ID，重复确认不重复创建。确认前修改文字会重建草稿；确认后锁定原记录，需新建会议修订，保留已确认依据。尚无音频、转写、智能总结、负责人/日期字段、草稿删除或原文跳转定位。
