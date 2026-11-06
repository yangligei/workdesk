#!/usr/bin/env python3
"""Render production meeting views against an isolated, synthetic native store."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1]).resolve()
fixture = r'''
import SwiftUI
import AppKit
import WorkdeskCore

@main struct RenderCheck {
 @MainActor static func main() {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  Task { @MainActor in
   do {
    let model = Model()
    let store = model.store!
    let project = try await store.createProject("演示验证")
    let other = try await store.createProject("公众号运营")
    _ = try await store.registerSource("render-fixture", project: project.id, alias: "demo", tokenFile: model.connectionCredentials.appendingPathComponent("render-fixture.key"))
    let text = "11月4日 · 工作沟通（隔离示例）\n\n李经理：演示验证这个 demo 还要再跑一遍，看看上次的问题有没有解决。\n\n我：好的，我再验证一下，把结果整理出来。\n\n小林：公众号我还在推进。\n\n我：微信推文的流程也得梳理一下，后续运营安排再找时间讨论。"
    let meeting = try await store.saveMeetingSource(project: project.id, text: text, originalDate: "2026-11-04")
    let fixture: [[String:String]] = [
     ["type":"task","text":"把 demo 再跑一遍，并整理验证结果","projectID":project.id,"evidence":"我再验证一下，把结果整理出来。"],
     ["type":"task","text":"梳理微信推文流程","projectID":other.id,"evidence":"微信推文的流程也得梳理一下"],
     ["type":"progress","text":"公众号正在推进","projectID":other.id,"evidence":"公众号我还在推进。"]
    ]
    let reviews = try await store.storeMeetingAnalysis(JSONSerialization.data(withJSONObject: ["items":fixture]), meeting: meeting, source: "render-fixture")
    await model.reload()
    let editor = MeetingEditor(model: model)
    editor.current = meeting; editor.text = text; editor.reviews = reviews
    editor.message = "隔离原生渲染样例 · 未写入真实项目"
    let host = NSHostingView(rootView: MeetingsView(model: model, editor: editor))
    let width = Double(CommandLine.arguments[2])!
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFront(nil)
    try await Task.sleep(nanoseconds: 400_000_000)
    host.layoutSubtreeIfNeeded()
    @MainActor func editors(_ view: NSView) -> [NSTextView] {
     if let editor = view as? NSTextView { return [editor] }
     return view.subviews.flatMap { editors($0) }
    }
    let source = editors(host).first { $0.string == text }!
    let frame = source.convert(source.bounds, to: host)
    precondition(frame.width > (width - 81) * 0.39 && frame.maxX < width * 0.5, "source editor squeezed or wrong split")
    let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: image)
    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    let projectTasks = try await store.tasks(project.id)
    let otherTasks = try await store.tasks(other.id)
    precondition(projectTasks.isEmpty && otherTasks.isEmpty)
    print("PASS native meeting render \(Int(width))x760pt; source editor \(frame); no task mutations; \(CommandLine.arguments[1])")
    exit(0)
   } catch { print("FAIL: \(error)"); exit(1) }
  }
  app.run()
 }
}
'''
with tempfile.TemporaryDirectory(prefix="meeting-render-", dir=os.environ["TMPDIR"]) as temporary:
    root = Path(temporary)
    app_source = (repo / "Sources/Workdesk/WorkdeskApp.swift").read_text()
    (root / "AppSupport.swift").write_text(app_source[:app_source.index("@main struct WorkdeskApp")])
    (root / "RenderCheck.swift").write_text(fixture)
    build = repo / ".build/arm64-apple-macosx/debug"
    objects = [build / "WorkdeskCore.build" / (path.name + ".o") for path in sorted((repo / "Sources/WorkdeskCore").glob("*.swift"))]
    sources = sorted(path for path in (repo / "Sources/Workdesk").glob("*.swift") if path.name != "WorkdeskApp.swift")
    subprocess.run(["swiftc", "-target", "arm64-apple-macosx13.0", "-parse-as-library", "-I", str(build), "-I", str(repo / "Sources/CSQLite"),
                    *map(str, sources), str(root / "AppSupport.swift"), str(root / "RenderCheck.swift"),
                    *map(str, objects), "-o", str(root / "render")], check=True)
    env = dict(os.environ, WORKDESK_DATA_DIR=str(root / "data"), WORKDESK_DISABLE_NOTIFICATIONS="1")
    subprocess.run([str(root / "render"), str(output), sys.argv[2] if len(sys.argv) > 2 else "1140"], env=env, check=True, timeout=30)
