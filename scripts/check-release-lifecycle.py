#!/usr/bin/env python3
"""Exercise production Model/MeetingEditor with synthetic SQLite data only."""
import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
fixture = r'''
import SwiftUI
import AppKit
import WorkdeskCore
import CSQLite

@main struct LifecycleCheck {
 @MainActor static func main() {
  NSApplication.shared.setActivationPolicy(.accessory)
  Task { @MainActor in
   do {
    let model = Model()
    let store = model.store!
    let project = try await store.createProject("发布验收隔离项目")
    let task = try await store.createTask(project.id, title: "空闲到期归档")
    try await store.updateTask(task.id, title: task.title, status: "完成", expected: 1)
    var db: OpaquePointer?
    let path = model.connectionRoot!.appendingPathComponent("workdesk.sqlite").path
    // Resolve the store's actual database filename without reading production data.
    let files = try FileManager.default.contentsOfDirectory(atPath: model.connectionRoot!.path)
    guard let name = files.first(where: { $0.hasSuffix(".sqlite") || $0.hasSuffix(".db") }) else { throw StoreError.missing }
    guard sqlite3_open(model.connectionRoot!.appendingPathComponent(name).path, &db) == SQLITE_OK else { throw StoreError.missing }
    _ = path
    let completion = Date().timeIntervalSince1970 - 12 * 3600 + 1
    guard sqlite3_exec(db, "UPDATE tasks SET completed_at=\(completion) WHERE id='\(task.id)'", nil, nil, nil) == SQLITE_OK else { throw StoreError.missing }
    sqlite3_close(db)
    await model.reload()
    precondition(model.tasks.contains { $0.id == task.id }, "archived before deadline")
    try await Task.sleep(nanoseconds: 2_000_000_000)
    let remaining = try await store.tasks(project.id)
    guard remaining.isEmpty && model.archivedTasks.contains(where: { $0.id == task.id }) else {
     print("FAIL idle archive: deadline passed without automatic sweep/UI refresh"); exit(1)
    }
    print("PASS idle deadline archives and updates production Model without user refresh")
    let editor = MeetingEditor(model: model)
    editor.text = "隔离会议：整理测试结果"
    try await editor.persist()
    let meeting = editor.current!
    editor.text += "，保留原始证据"
    editor.changed()
    editor.delete(meeting)
    editor.leave()
    try await Task.sleep(nanoseconds: 1_000_000_000)
    let meetings = try await store.allMeetings()
    guard meetings.isEmpty && editor.current == nil && editor.text.isEmpty else {
     print("FAIL deleted meeting resurrected by queued save/leave"); exit(1)
    }
    print("PASS meeting deletion drains pending save and leave without resurrection")
    exit(0)
   } catch { print("FAIL \(error)"); exit(1) }
  }
  NSApplication.shared.run()
 }
}
'''
with tempfile.TemporaryDirectory(prefix="workdesk-lifecycle-", dir=os.environ["TMPDIR"]) as temporary:
    root = Path(temporary)
    source = (repo / "Sources/Workdesk/WorkdeskApp.swift").read_text()
    (root / "AppSupport.swift").write_text(source[:source.index("@main struct WorkdeskApp")])
    (root / "Check.swift").write_text(fixture)
    build = repo / ".build/arm64-apple-macosx/debug"
    objects = [build / "WorkdeskCore.build" / (p.name + ".o") for p in sorted((repo / "Sources/WorkdeskCore").glob("*.swift"))]
    sources = sorted(p for p in (repo / "Sources/Workdesk").glob("*.swift") if p.name != "WorkdeskApp.swift")
    subprocess.run(["swiftc", "-target", "arm64-apple-macosx13.0", "-parse-as-library", "-I", str(build), "-I", str(repo / "Sources/CSQLite"), *map(str, sources), str(root / "AppSupport.swift"), str(root / "Check.swift"), *map(str, objects), "-o", str(root / "check")], check=True)
    subprocess.run([str(root / "check")], env=dict(os.environ, WORKDESK_DATA_DIR=str(root / "data"), WORKDESK_DISABLE_NOTIFICATIONS="1"), check=True, timeout=30)
