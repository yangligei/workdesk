import Foundation
import CSQLite

public struct Project: Identifiable, Codable, Sendable {
 public let id: String; public let title: String; public var stage: String = ""; public var version: Int = 1
 public var deadline: Date? = nil
 public var timeZone: String = TimeZone.current.identifier
 public var reminderHours: [Double] = [24]
}
public struct WorkTask: Identifiable, Sendable {
 public let id: String
 public let title: String
 public let status: String
 public let version: Int
}
public enum StoreError: Error, LocalizedError {
 case database(String), invalidTitle, conflict, missing
 public var errorDescription: String? {
  switch self {
  case .database(let message): return "数据库错误：\(message)"
  case .invalidTitle: return "名称不能为空"
  case .conflict: return "任务已被修改，请刷新后重试"
  case .missing: return "记录不存在"
  }
 }
}

public actor Store {
 private let db: OpaquePointer
 public init(root: URL) throws {
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  var handle: OpaquePointer?
  guard sqlite3_open(root.appendingPathComponent("workdesk.sqlite").path, &handle) == SQLITE_OK, let handle else {
   if let handle { sqlite3_close(handle) }
   throw StoreError.database("无法打开存储")
  }
  db = handle
  sqlite3_busy_timeout(handle, 3000)
  let schema = """
  PRAGMA foreign_keys=ON;
  PRAGMA journal_mode=WAL;
  CREATE TABLE IF NOT EXISTS projects(id TEXT PRIMARY KEY, title TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS tasks(id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE, title TEXT NOT NULL, status TEXT NOT NULL DEFAULT '待办', version INTEGER NOT NULL DEFAULT 1);
  CREATE INDEX IF NOT EXISTS tasks_project ON tasks(project_id);
  """
  guard sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK else {
   let message = String(cString: sqlite3_errmsg(handle)); sqlite3_close(handle)
   throw StoreError.database(message)
  }
  let columns = try Self.execute(handle, "PRAGMA table_info(projects)").map { $0[1] }
  if !columns.contains("stage") { _ = try Self.execute(handle, "ALTER TABLE projects ADD COLUMN stage TEXT NOT NULL DEFAULT ''") }
  if !columns.contains("version") { _ = try Self.execute(handle, "ALTER TABLE projects ADD COLUMN version INTEGER NOT NULL DEFAULT 1") }
  if !columns.contains("deadline") { _ = try Self.execute(handle, "ALTER TABLE projects ADD COLUMN deadline REAL") }
  if !columns.contains("timezone") { _ = try Self.execute(handle, "ALTER TABLE projects ADD COLUMN timezone TEXT NOT NULL DEFAULT 'UTC'") }
  if !columns.contains("reminders") { _ = try Self.execute(handle, "ALTER TABLE projects ADD COLUMN reminders TEXT NOT NULL DEFAULT '[24]'") }
  _ = try Self.execute(handle, "PRAGMA user_version=3")
 }
 deinit { sqlite3_close(db) }
 func query(_ sql: String, _ values: [String] = []) throws -> [[String]] { try Self.execute(db, sql, values) }
 private static func execute(_ db: OpaquePointer, _ sql: String, _ values: [String] = []) throws -> [[String]] {
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.database(String(cString: sqlite3_errmsg(db))) }
  defer { sqlite3_finalize(statement) }
  for (index, value) in values.enumerated() {
   let result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
   guard result == SQLITE_OK else { throw StoreError.database("参数绑定失败") }
  }
  var rows: [[String]] = []
  while true {
   let result = sqlite3_step(statement)
   if result == SQLITE_DONE { return rows }
   guard result == SQLITE_ROW else { throw StoreError.database(String(cString: sqlite3_errmsg(db))) }
   rows.append((0..<sqlite3_column_count(statement)).map { column in
    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
   })
  }
 }
 func title(_ text: String) throws -> String {
  let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !value.isEmpty else { throw StoreError.invalidTitle }; return value
 }
 public func projects() throws -> [Project] {
  try query("SELECT id,title,stage,version,deadline,timezone,reminders FROM projects ORDER BY rowid").map { Project(id: $0[0], title: $0[1], stage: $0[2], version: Int($0[3])!, deadline: Double($0[4]).map { Date(timeIntervalSince1970: $0) }, timeZone: $0[5], reminderHours: (try? JSONDecoder().decode([Double].self, from: Data($0[6].utf8))) ?? [24]) }
 }
 public func createProject(_ text: String) throws -> Project {
  let item = Project(id: UUID().uuidString, title: try title(text), timeZone: "UTC")
  _ = try query("INSERT INTO projects(id,title) VALUES(?,?)", [item.id, item.title]); return item
 }
 public func updateProject(_ id: String, title text: String, stage: String, expected: Int) throws {
  _ = try query("UPDATE projects SET title=?,stage=?,version=version+1 WHERE id=? AND version=?", [try title(text), stage, id, String(expected)])
  guard sqlite3_changes(db) == 1 else { throw StoreError.conflict }
 }
 public func deleteProject(_ id: String) throws { _ = try query("DELETE FROM projects WHERE id=?", [id]) }
 public func tasks(_ project: String) throws -> [WorkTask] {
  try query("SELECT id,title,status,version FROM tasks WHERE project_id=? ORDER BY rowid", [project]).map { WorkTask(id: $0[0], title: $0[1], status: $0[2], version: Int($0[3])!) }
 }
 public func createTask(_ project: String, title text: String) throws -> WorkTask {
  let item = WorkTask(id: UUID().uuidString, title: try title(text), status: "待办", version: 1)
  _ = try query("INSERT INTO tasks(id,project_id,title) VALUES(?,?,?)", [item.id, project, item.title]); return item
 }
 public func updateTask(_ id: String, title text: String, status: String, expected: Int) throws {
  guard ["待办", "进行中", "阻塞", "完成"].contains(status) else { throw StoreError.database("无效状态") }
  _ = try query("UPDATE tasks SET title=?,status=?,version=version+1 WHERE id=? AND version=?", [try title(text), status, id, String(expected)])
  guard sqlite3_changes(db) == 1 else { throw StoreError.conflict }
 }
 public func deleteTask(_ id: String) throws { _ = try query("DELETE FROM tasks WHERE id=?", [id]) }
}
