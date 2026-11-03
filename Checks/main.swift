import Foundation
import WorkdeskCore

func require(_ value: Bool, _ message: String) throws {
 if !value { throw NSError(domain: "CoreChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
@main struct Checks {
 static func main() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("workdesk-check-\(UUID())")
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try Store(root: root)
  do { _ = try await store.createProject(" \n "); throw NSError(domain: "expected rejection", code: 1) } catch StoreError.invalidTitle { }
  let project = try await store.createProject("示例 ' 项目")
  try await store.updateProject(project.id, title: "编辑项目", stage: "实施", expected: 1)
  let edited = try await store.projects()
  try require(edited[0].stage == "实施" && edited[0].version == 2, "项目阶段编辑失败")
  try await store.bind(source: "fixture", alias: "demo", project: project.id)
  let event = ProgressEvent(sourceID: "fixture", projectID: "demo", type: "task.create", text: "来自事件")
  let first = try await store.receive(event)
  let duplicate = try await store.receive(event)
  try require(first.outcome == "accepted" && duplicate == first, "事件去重失败")
  let eventTasks = try await store.tasks(project.id)
  try require(eventTasks.count == 1, "事件未创建任务或重复创建")
  let inbox = try EventInbox(root: root, store: store)
  let queued = ProgressEvent(sourceID: "fixture", projectID: "demo", type: "progress", text: "运行结束，不代表完成")
  let filename = try EventInbox.submit(queued, root: root)
  try await inbox.drain()
  let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: root.appendingPathComponent("receipts/" + filename)))
  try require(receipt.outcome == "accepted", "原子收件箱失败")
  try await store.deleteTask(eventTasks[0].id)
  let meeting = try await store.saveMeeting(project: project.id, text: "[00:12] 待办：整理发布说明\n[00:30] 普通讨论")
  let drafts = try await store.meetingDrafts(meeting)
  try require(drafts.count == 1 && drafts[0].evidence.contains("00:12"), "会议证据提取失败")
  try await store.confirmDraft(drafts[0].id, title: "整理说明")
  try await store.confirmDraft(drafts[0].id, title: "重复确认")
  let meetingTasks = try await store.tasks(project.id)
  try require(meetingTasks.count == 1 && meetingTasks[0].title == "整理说明", "会议确认不幂等")
  try await store.deleteTask(meetingTasks[0].id)
  let task = try await store.createTask(project.id, title: "原始任务")
  try await store.updateTask(task.id, title: "更新任务", status: "完成", expected: 1)
  do { try await store.updateTask(task.id, title: "过期写入", status: "待办", expected: 1); throw NSError(domain: "expected conflict", code: 1) } catch StoreError.conflict { }
  var stale = ProgressEvent(sourceID: "fixture", projectID: "demo", type: "task.rename", text: "覆盖", taskID: task.id, expectedVersion: 1)
  let conflict = try await store.receive(stale)
  try require(conflict.outcome == "conflict", "事件版本冲突未拒绝")
  stale.eventID = UUID().uuidString; stale.projectID = "other"
  let denied = try await store.receive(stale)
  try require(denied.outcome == "rejected", "越权映射未拒绝")
  let completion = try await store.receive(ProgressEvent(sourceID: "fixture", projectID: "demo", type: "task.complete", text: "完成"))
  try require(completion.outcome == "rejected", "外部完成未拒绝")
  let replayFile = try EventInbox.submit(event, root: root)
  try await inbox.drain()
  let replayReceipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: root.appendingPathComponent("receipts/" + replayFile)))
  try require(replayReceipt == first, "重启回放回执不一致")
  let input = root.appendingPathComponent("inbox")
  try Data("broken".utf8).write(to: input.appendingPathComponent("bad.json"))
  try Data(repeating: 65, count: 65537).write(to: input.appendingPathComponent("large.json"))
  let outside = root.appendingPathComponent("outside.txt")
  try Data("untouched".utf8).write(to: outside)
  try FileManager.default.createSymbolicLink(at: input.appendingPathComponent("link.json"), withDestinationURL: outside)
  try Data("partial".utf8).write(to: input.appendingPathComponent("unfinished.tmp"))
  try await inbox.drain()
  for name in ["bad.json", "large.json", "link.json"] {
   let rejected = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: root.appendingPathComponent("receipts/" + name)))
   try require(rejected.outcome == "rejected", "无效文件未拒绝")
  }
  try require(try String(contentsOf: outside) == "untouched", "符号链接目标受影响")
  try require(FileManager.default.fileExists(atPath: input.appendingPathComponent("unfinished.tmp").path), "读取了未完成临时文件")
  let reopened = try Store(root: root)
  let tasks = try await reopened.tasks(project.id)
  try require(tasks.count == 1 && tasks[0].version == 2 && tasks[0].title == "更新任务" && tasks[0].status == "完成", "持久化或冲突保护失败")
  try await store.deleteTask(task.id)
  let empty = try await reopened.tasks(project.id)
  try require(empty.isEmpty, "删除任务失败")
  _ = try await store.createTask(project.id, title: "级联测试")
  try await store.deleteProject(project.id)
  let projects = try await reopened.projects()
  let remaining = try await reopened.tasks(project.id)
  try require(projects.isEmpty && remaining.isEmpty, "级联删除失败")
  do { _ = try await store.createTask(project.id, title: "孤立任务"); throw NSError(domain: "expected foreign key failure", code: 1) } catch StoreError.database { }
  print("PASS: CRUD、阶段编辑、映射/去重/冲突/越权/完成保护、原子收件箱与重放、恶意文件边界、会议证据与幂等确认、持久化和级联")
 }
}
