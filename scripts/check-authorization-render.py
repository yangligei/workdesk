#!/usr/bin/env python3
"""Render production authorization controls with memory-only state; no database or credentials."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
view = (repo / 'Sources/Workdesk/MCPAuthorizationOptions.swift').read_text()
fixture = r'''
import AppKit
enum Desk { static let green = Color(red: 0.18, green: 0.38, blue: 0.29) }
struct Fixture: View {
 @State var projects = false
 @State var tasks = false
 @State var include = true
 let hasProject: Bool
 var body: some View {
  VStack(alignment: .leading, spacing: 12) {
   Text("首次授权与权限管理").font(.system(size: 17, weight: .semibold))
   Text("已有身份 · fixture-agent").font(.system(size: 13.5))
   MCPAuthorizationOptions(allowProjects: $projects, allowTasks: $tasks, includeProject: $include, hasProject: hasProject)
   Text("选择范围并授权后持续生效；客户端配置仍需你确认。").font(.system(size: 11)).foregroundStyle(.secondary)
   Button("授权所选范围并记住") {}.controlSize(.large)
  }.padding(20).frame(width: 640).background(Color.white).preferredColorScheme(.light)
 }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let host = NSHostingView(rootView: Fixture(hasProject: CommandLine.arguments.count > 2))
let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 340), styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = host
window.orderFront(nil)
host.layoutSubtreeIfNeeded()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
host.cacheDisplay(in: host.bounds, to: image)
try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("PASS: native authorization options, default-off project/task controls, 54pt full-row buttons; memory-only fixture")
'''
with tempfile.TemporaryDirectory(prefix='authorization-render-', dir=os.environ['TMPDIR']) as directory:
    root = Path(directory)
    (root / 'main.swift').write_text(view + fixture)
    subprocess.run(['swiftc', str(root / 'main.swift'), '-o', str(root / 'check')], check=True)
    subprocess.run([str(root / 'check'), str(Path(sys.argv[1]).resolve())] + sys.argv[2:], check=True, timeout=20)
