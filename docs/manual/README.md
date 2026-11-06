# 图文 HTML 手册

交付文件：`workdesk-user-manual.html`。图片、样式和交互已内嵌，单文件可离线打开或发送。图片可点击放大，支持键盘 Esc 关闭；打印按钮使用浏览器原生打印。

## 内容与来源

- 7 个主章节、7 张配图；完整内容来自 `../user-guide.md`，附当前四个 MCP 工具说明。
- `focus-native.png`：当前生产 FocusPanel 的内存隔离渲染。
- `authorization-native.png`：当前生产授权选项控件的内存隔离渲染。
- `meeting-native.png`：生产会议视图，临时隔离数据库及虚构样例；原文和审核配图由此裁切。
- `menu-guide.png`、`connection-guide.png`、`archive-guide.png`：Pillow 绘制的操作示意，图片及图注均明确标记，不冒充截图。
- 无真实聊天、个人项目数据或密钥。原生置顶窗配图保留真实滚动视口；未显示的任务可在应用中滚动查看。

## 重新生成

在仓库根目录执行（Python 需要 Pillow 和 markdown）：

```sh
python3 scripts/check-focus-render.py docs/manual/images/focus-native.png
python3 scripts/check-authorization-render.py docs/manual/images/authorization-native.png existing
python3 scripts/check-meeting-render.py docs/manual/images/meeting-native.png 1140
python3 docs/manual/build_manual.py
```

会议渲染依赖已有 Debug 构建产物，缺少时先执行 `swift build`。原生渲染使用内存样例或临时数据目录，不启动用户正在使用的 Workdesk 实例。

`manual-source.md` 是生成时保存的中间文稿；维护正文应编辑 `../user-guide.md`，随后运行生成器。

## 实际验证（2026-11-06）

- 原生置顶窗：PASS，520×720 pt，5 个 152×48 pt 状态控件，任务状态列对齐；仅内存样例。
- 原生授权控件：PASS，项目与任务创建默认关闭；54 pt 整行按钮；仅内存样例。
- 原生会议视图：PASS，1140×760 pt，原文宽 456.5 pt，隔离数据库未新增正式任务。
- 本机 Chrome 直接打开 file URL：7/7 图片 complete 且 naturalWidth > 0；7 个主章节，目录锚点全部存在。
- 1280、390、320 px 三种宽度：scrollWidth 等于 innerWidth，无横向溢出。
- 实际调用图片放大按钮：dialog.open 为 true，放大图加载成功；关闭成功。
- 点击会议目录项：跳转到相应章节 hash。
- 打印媒体样式：侧栏和工具栏均 display:none；正文为 16px，即 12pt。
- 资源检查：无外部 src，Performance resource 中无非 data 资源；无需网络。
- 检视桌面首页、会议审核局部与手机窄屏截图，另检视原生置顶窗与会议 PNG：正文及状态无重叠。窄屏图片可点击后按原尺寸滚动阅读。
- 设计自检：0/10 装饰性模板特征；以文档侧栏、分节正文和必要配图构成，无渐变、玻璃效果、虚构指标或营销卡片。

未执行实体打印，未生成 PDF 或 Word；当前交付以 HTML 为准。
