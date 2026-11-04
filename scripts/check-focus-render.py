#!/usr/bin/env python3
"""Snapshot production FocusPanel using a memory-only synthetic model (no storage)."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
source = (repo / 'Sources/Workdesk/DesignViews.swift').read_text()
views = source[source.index('enum Desk {'):source.index('struct StatusPill:')]
views += source[source.index('struct FocusPanel:'):source.index('struct AgentStatus:')]
views += (repo / 'Sources/Workdesk/StatusMenuButton.swift').read_text()
store = (repo / 'Sources/WorkdeskCore/Store.swift').read_text()
events = (repo / 'Sources/WorkdeskCore/Events.swift').read_text()
types = store[store.index('public struct Project:'):store.index('public enum StoreError:')]
types += events[events.index('public struct AuditEntry:'):events.index('public extension Store {')]
fixture = r'''
final class FixtureStore {
 func updateProjectStatus(_ id: String, status: String, expected: Int) async throws { fatalError("read-only render") }
}
final class Model: ObservableObject {
 @Published var projects = [Project(id: "fixture", title: "原生界面排版验收", stage: "视觉与交互验证", status: "进行中"), Project(id: "long", title: "长项目名称换行与状态列验证示例"), Project(id: "other", title: "隔离样例")]
 @Published var selection: String? = "fixture"
 @Published var tasks: [WorkTask] = []
 @Published var error: String?
 @Published var projectTasks = ["fixture": [WorkTask(id: "1", title: "核对标题、正文与状态的字号层级", status: "待办", version: 1), WorkTask(id: "2", title: "压缩任务行间距，保留完整点击区域", status: "进行中", version: 1), WorkTask(id: "3", title: "长任务标题应自然换行：检查右侧状态列独立对齐，正文不会重叠或被截断", status: "阻塞", version: 1), WorkTask(id: "4", title: "完成原生渲染检查", status: "完成", version: 1)]]
 @Published var projectProgress = ["fixture": [AuditEntry(id: "1", source: "fixture-agent", project: "fixture", occurred: "11月4日 16:00", received: "", type: "progress", text: "已调整整体字号与留白，正在核对原生界面。", outcome: "accepted"), AuditEntry(id: "2", source: "fixture-agent", project: "fixture", occurred: "11月4日 15:00", received: "", type: "progress", text: "更早的隔离样例进展", outcome: "accepted")]]
 @Published var bindings: [SourceBinding] = []
 var store: FixtureStore? = nil
 func perform(_ action: @escaping () async throws -> Void) { fatalError("read-only render") }
 func reload() async { fatalError("read-only render") }
 func update(_ task: WorkTask, status: String) { fatalError("read-only render") }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let model = Model()
if CommandLine.arguments.count > 2 {
 model.projects[0] = Project(id: "fixture", title: "长项目标题应完整换行并保留右侧独立状态列的原生排版验证", stage: "视觉与交互验证", status: "进行中")
}
let host = NSHostingView(rootView: FocusPanel(model: model))
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = host
// Offscreen window: capture native drawing without displaying fixture UI.
window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
window.orderFront(nil)
host.layoutSubtreeIfNeeded()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
func buttons(_ view: NSView) -> [StatusChoiceButton] { (view as? StatusChoiceButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) } }
let controls = buttons(host)
precondition(controls.count == 5)
let frames = controls.map { $0.convert($0.bounds, to: host) }
for frame in frames { precondition(frame.width == 104 && frame.height == 48 && frame.minX >= 0 && frame.maxX <= 520) }
precondition(Set(frames.map { $0.minX }).count == 1, "status column must align")
let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
host.cacheDisplay(in: host.bounds, to: image)
try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("PASS native 520x720pt FocusPanel, five 104x48pt controls, aligned status column; memory-only fixture")
print("Control frames:", frames)
'''
with tempfile.TemporaryDirectory(prefix='focus-render-', dir=os.environ['TMPDIR']) as temporary:
    root = Path(temporary)
    swift = root / 'main.swift'
    swift.write_text('import SwiftUI\nimport AppKit\n' + types + fixture[:fixture.index('let app =')] + views + fixture[fixture.index('let app ='):])
    subprocess.run(['swiftc', str(swift), '-o', str(root / 'check')], check=True)
    subprocess.run([str(root / 'check'), str(Path(sys.argv[1]).resolve())] + sys.argv[2:], check=True, timeout=20)
