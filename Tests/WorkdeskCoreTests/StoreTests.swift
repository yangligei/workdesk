import XCTest
@testable import WorkdeskCore
final class StoreTests: XCTestCase {
 func testPersistentCRUD() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try Store(root: root)
  let project = try await store.createProject("示例")
  let task = try await store.createTask(project.id, title: "任务")
  try await store.updateTask(task.id, title: "更新", status: "完成", expected: 1)
  let reopened = try Store(root: root)
  let tasks = try await reopened.tasks(project.id)
  XCTAssertEqual(tasks.first?.title, "更新")
  XCTAssertEqual(tasks.first?.version, 2)
  try await reopened.deleteTask(task.id)
  try await reopened.deleteProject(project.id)
  let projects = try await reopened.projects()
  XCTAssertTrue(projects.isEmpty)
 }
}
