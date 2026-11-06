#!/usr/bin/env python3
"""Build the offline manual from the maintained user guide and isolated images.
Requires Python packages markdown and Pillow; run from any directory.
Native images come from scripts/check-{focus,authorization,meeting}-render.py.
"""
from pathlib import Path
import base64
import re
import html
import markdown
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
IMAGES = ROOT / 'images'
FONT = '/System/Library/Fonts/STHeiti Light.ttc'

def diagram(name, title, steps, foot):
    im = Image.new('RGB', (1400, 210 + len(steps)*116), '#f3f5f1')
    d = ImageDraw.Draw(im)
    font = lambda size: ImageFont.truetype(FONT, size)
    d.text((42, 32), title, font=font(34), fill='#244e3b')
    for i, (head, body) in enumerate(steps):
        y = 100+i*116
        d.rounded_rectangle((40,y,1360,y+100),radius=10,fill='white')
        d.ellipse((60,y+24,108,y+72),fill='#315f49')
        d.text((75,y+30),str(i+1),font=font(28),fill='white')
        d.text((132,y+14),head,font=font(28),fill='#20352a')
        d.text((132,y+54),body,font=font(23),fill='#526158')
    d.text((42,im.height-65),foot,font=font(22),fill='#526158')
    im.save(IMAGES/name)

diagram('menu-guide.png','菜单栏：用一次点击找到正确窗口',[
 ('左键单击清单图标','打开「今日进度」置顶窗，快速查看当前项目。'),
 ('右键 / 触控板双指按压，松手','打开菜单，再选择管理窗口、设置与接入或退出。'),
 ('关闭窗口后，应用仍在运行','要结束应用，请从菜单选择「退出 Workdesk」。')], '操作示意图 · 按当前交互绘制，并非应用截图')
diagram('archive-guide.png','完成 → 满 12 小时 → 自动归档',[
 ('本机确认任务完成','从进入「完成」的时刻计时；改标题不重置计时。'),
 ('完成后满 12 小时，且自动归档已开启','运行中按到期时间自动归档；启动、刷新与唤醒时补扫。'),
 ('归档窗口保留历史','可筛选项目、恢复为待办；永久删除需要确认。')], '流程示意图 · 归档不改变项目状态，也不删除来源证据')
diagram('connection-guide.png','连接成功，要看本次调用的回执',[
 ('先在本机授权身份和范围','创建项目默认关闭；新增待办另行勾选；已有项目逐个授权。'),
 ('预览并确认客户端配置','在客户端刷新 MCP 或重新打开会话，再发出实际请求。'),
 ('核对 accepted 与目标项目','本机握手测试、客户端调用、QQ 送达是不同验证环节。')], '接入流程示意图 · QQ 与按小时同步需要用户额外配置')

meeting = Image.open(IMAGES/'meeting-native.png')
meeting.crop((20,280,1040,1340)).save(IMAGES/'meeting-source.png')
meeting.crop((1040,280,2260,1500)).save(IMAGES/'meeting-review.png')

figures = {
 'menu': ('menu-guide.png','图 1 · 菜单栏操作示意：先选手势，再选窗口。'),
 'focus': ('focus-native.png','图 2 · 当前原生置顶窗，内存隔离样例。① 顶部切换项目；② 项目状态独立；③ 任务右侧改状态；④ 底部进入归档。'),
 'auth': ('authorization-native.png','图 3 · 原生首次授权控件，内存隔离样例。① 选择创建权限；② 确认当前项目范围；③ 点击授权并记住。'),
 'connection': ('connection-guide.png','图 4 · 接入流程示意：发现、配置、授权与送达需分别核对。'),
 'source': ('meeting-source.png','图 5 · 原生会议原文局部，隔离虚构样例。① 先定会议日期；② 粘贴完整上下文；③ 保存或授权识别。'),
 'review': ('meeting-review.png','图 6 · 原生会议审核局部，隔离虚构样例。① 勾选条目；② 核对类型和项目；③ 查依据；④ 确认写入所选。'),
 'archive': ('archive-guide.png','图 7 · 归档流程示意：任务完成满 12 小时后自动归档，应用启动或唤醒时补扫。'),
}
def figure(key):
    name, caption = figures[key]
    data = base64.b64encode((IMAGES/name).read_bytes()).decode()
    return f'<figure class="{key}"><button class="image-open" onclick="openImage(this)" aria-label="放大配图"><img src="data:image/png;base64,{data}" alt="{html.escape(caption)}" loading="eager"></button><figcaption>{caption} 点击图片可放大，按 Esc 关闭。</figcaption></figure>'

source = (REPO/'docs/user-guide.md').read_text()
source = '\n'.join(line for line in source.splitlines() if not line.startswith('图文阅读入口：'))
source = source.replace('# Workdesk 中文用户指南','# Workdesk 图文用户手册',1)
source = source.replace('本指南依据当前版本界面与代码编写，适用于 macOS 13 及以上版本。','本手册依据当前版本界面与代码核对，适用于 macOS 13 及以上版本。配图均为隔离虚构样例或明确标注的操作示意。核对日期：2026 年 11 月 6 日。')
placements = {
 '## 快速开始':'menu',
 '### 在置顶窗查看今天的工作':'focus',
 '### 按四步完成连接':'auth',
 '### 四种提示分别代表什么':'connection',
 '### 示例流程':'source',
 '### 审核右侧建议':'review',
 '## 完成任务与归档':'archive',
}
for heading,key in placements.items(): source=source.replace(heading,heading+'\n\n@@FIGURE_'+key+'@@\n')
source=source.replace('### 四种提示分别代表什么','### 当前 MCP 提供四个工具\n\n| 工具 | 用途与边界 |\n| --- | --- |\n| `workdesk_projects` | 查询当前身份已授权的项目 |\n| `workdesk_progress` | 记录进展，不改变正式状态 |\n| `workdesk_task_create` | 新增待办，需要独立权限 |\n| `workdesk_project_create` | 新建项目并建立绑定，需要本机创建许可 |\n\n### 四种提示分别代表什么')
(ROOT/'manual-source.md').write_text(source)
body=markdown.markdown(source,extensions=['tables','toc','fenced_code'],extension_configs={'toc':{'permalink':False}})
for key in figures: body=body.replace('<p>@@FIGURE_'+key+'@@</p>',figure(key))
# Keep related source links navigable when delivered as a single offline file.
body=re.sub(r'<a href="([^"#][^"]*\.md)">([^<]*)</a>',r'<span>\2（补充文档位于源码仓库 docs/）</span>',body)
heads=re.findall(r'<h2 id="([^"]+)">(.*?)</h2>',body)
nav=''.join(f'<a href="#{anchor}"><span>{i:02}</span>{title}</a>' for i,(anchor,title) in enumerate(heads,1))
css='''
:root{--ink:#24362c;--muted:#5d6b62;--green:#315f49;--line:#dbe2da;--paper:#fff;--bg:#f3f5f1}*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:24px}body{margin:0;color:var(--ink);background:var(--bg);font:17px/1.85 "PingFang SC","Hiragino Sans GB",sans-serif}aside{position:fixed;inset:0 auto 0 0;width:260px;padding:34px 24px;border-right:1px solid var(--line);overflow-y:auto;background:#edf1eb}.brand{font-size:25px;font-weight:650;letter-spacing:.04em}.edition{font-size:13px;color:var(--muted);margin:8px 0 28px}nav a{display:flex;gap:12px;padding:10px 0;text-decoration:none;color:var(--ink);font-size:15px}nav span{font-size:12px;color:var(--green);padding-top:3px}main{max-width:1160px;margin-left:260px;padding:45px 60px 90px}article{max-width:920px;margin:auto}h1{font-size:38px;line-height:1.3;letter-spacing:-.02em;margin:0 0 25px}h2{font-size:28px;line-height:1.5;margin:68px 0 22px;padding-top:20px;border-top:2px solid var(--line)}h3{font-size:21px;line-height:1.6;margin:36px 0 16px}p,li{overflow-wrap:anywhere}li{margin:7px 0}a{color:var(--green)}a:focus-visible,button:focus-visible{outline:3px solid #a16a28;outline-offset:4px}blockquote{margin:20px 0;background:#e9f0e7;padding:14px 24px}figure{margin:26px 0 30px;background:var(--paper);padding:14px;border:1px solid var(--line);border-radius:8px}figure img{display:block;max-width:100%;height:auto;margin:auto}.focus img{max-height:720px}.auth img{max-height:380px}.source img,.review img{max-height:660px}figcaption{font-size:14px;color:var(--muted);line-height:1.7;margin:13px 4px 0}table{border-collapse:collapse;width:100%;font-size:15px;margin:22px 0;table-layout:fixed}th,td{text-align:left;vertical-align:top;padding:12px;border-bottom:1px solid var(--line);overflow-wrap:anywhere}th{background:#e9eee7}code{font-size:.88em;background:#e8eee6;padding:2px 5px;border-radius:3px}strong{font-weight:650}button{cursor:pointer;background:var(--green);color:white;border:0;border-radius:5px;padding:12px 16px;font:inherit}.tools{display:flex;gap:16px;align-items:center;margin:0 0 32px;font-size:13px;color:var(--muted)}footer{border-top:1px solid var(--line);margin-top:64px;padding-top:22px;font-size:14px;color:var(--muted)}@media(min-width:1500px){main{margin-right:auto;margin-left:max(260px,calc((100vw - 1080px)/2))}}@media(max-width:900px){aside{position:static;width:auto;padding:24px;border-right:0;border-bottom:1px solid var(--line)}nav{display:grid;grid-template-columns:1fr 1fr;gap:0 18px}.edition{margin-bottom:12px}main{margin:0;padding:30px 22px 60px}h1{font-size:30px}h2{font-size:25px;margin-top:48px}body{font-size:16px}figure{padding:8px;margin:22px 0}th,td{padding:8px;font-size:14px}.tools{flex-wrap:wrap}}@media(max-width:420px){nav{grid-template-columns:1fr}main{padding:26px 16px}h1{font-size:28px}ol,ul{padding-left:24px}}@media print{aside,.tools{display:none}body{font-size:12pt;background:white;color:#111}main{margin:0;max-width:none;padding:0}h1{font-size:25pt}h2{font-size:18pt;break-after:avoid}h3{font-size:14pt;break-after:avoid}figure{break-inside:avoid;max-width:100%}figure img{max-height:180mm}figcaption,table,th,td{font-size:12pt}a{color:inherit;text-decoration:none}tr{break-inside:avoid}@page{size:A4;margin:17mm}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
'''
page=f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="description" content="Workdesk 中文图文用户手册，含菜单栏、五状态、接入、会议审核、归档与备份"><title>Workdesk · 图文用户手册</title><style>{css}</style></head><body><aside aria-label="手册目录"><div class="brand">Workdesk</div><div class="edition">中文图文手册 · 离线版<br>核对日期 2026.11.06</div><nav>{nav}</nav></aside><main><article><div class="tools"><button onclick="window.print()">打印 / 保存为 PDF</button><span>单文件离线阅读 · 7 张配图 · 图片可放大</span></div>{body}<footer>本手册不读取应用数据，不连接网络。原生图来自当前源码的隔离渲染；流程图为操作示意。所有示例不代表真实项目或写入结果。</footer></article></main></body></html>'''
page = page.replace('</style>', '.image-open{display:block;width:100%;padding:0;background:transparent;border-radius:0;cursor:zoom-in}dialog{max-width:96vw;max-height:95vh;padding:16px;border:1px solid #dbe2da;border-radius:8px}dialog::backdrop{background:#15271ddd}dialog img{display:block;max-width:none;height:auto;margin-top:12px}dialog button{position:sticky;top:0}@media print{dialog{display:none}} </style>')
page = page.replace('</body>', '<dialog id="zoom"><button onclick="this.parentElement.close()">关闭放大图（Esc）</button><div id="zoom-content"></div></dialog><script>function openImage(button){const image=button.querySelector("img").cloneNode();document.getElementById("zoom-content").replaceChildren(image);document.getElementById("zoom").showModal();}</script></body>')
(ROOT/'workdesk-user-manual.html').write_text(page)
print(f'Built {len(page.encode()):,} bytes; {len(figures)} figures; {len(heads)} chapters')
