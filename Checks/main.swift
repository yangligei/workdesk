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
  let task = try await store.createTask(project.id, title: "原始任务")
  try await store.updateTask(task.id, title: "更新任务", status: "完成", expected: 1)
  do { try await store.updateTask(task.id, title: "过期写入", status: "待办", expected: 1); throw NSError(domain: "expected conflict", code: 1) } catch StoreError.conflict { }
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
  print("PASS: 空名称拒绝、参数绑定、持久化 CRUD、版本冲突保护、级联删除、外键约束（6 组检查）")
 }
}
