# 截止日期与本机智能体使用指南

在「项目任务」选择项目并启用截止，在日历选日期并编辑时间。日期格、时间编辑和总览标签使用项目时区；切换时区保留同一绝对时刻。夏令时切换遵循系统 Calendar/DatePicker 对不存在或重复本地时间的处理，可核对世界时后保存。

1、6、24、48 小时预设可独立开关。自定义支持小数小时，添加后显示按钮，点击 × 删除；最多 16 个，范围 (0,87600]。保存才写入，清除截止立即保存。提醒以截止绝对时刻减小时数计算，跨时区或夏令时不改变提前时长。

全部任务完成取消提醒；重新打开任务恢复未来提醒。没有任务的项目仍提醒，删除最后一个任务也适用此规则。改期替换旧提醒，删除项目或清除截止取消计划。已过时提醒不补发，逾期在总览红字显示，激活或刷新时更新。

「来源与事件」提供原生通知授权。本地 ad-hoc/未签名构建明确只提供应用内提示，不申请权限或宣称可靠后台送达。正式签名有原生授权和计划路径，本次未请求真实权限或发送通知。最多安排最近 60 个未来请求，更多提醒需后续刷新。退出、休眠、专注模式下送达由 macOS 决定，不保证；应用退出时不处理新事件或刷新计划，无后台辅助进程。

界面可复制来源登记及上报命令。首次登记和轮换都须使用全新凭据路径，旧签名在轮换后失效。详见 [事件协议](event-protocol.md)。通用进程适配器使用：

```sh
export WORKDESK_CLI="$PWD/dist/Workdesk.app/Contents/MacOS/WorkdeskCLI"
export WORKDESK_SOURCE=local-agent WORKDESK_ALIAS=demo
export WORKDESK_TOKEN_FILE="$HOME/.workdesk-credentials/local-agent.key"
scripts/workdesk-agent-adapter.sh '已完成一步检查，待人工验收'
```

只上报显式提供的文本，未自动接入 Hermes/QQ，未修改它们的配置。`bash scripts/test-agent-simulator.sh` 使用 TMPDIR 隔离样例并清理，不访问真实数据或发送通知。
