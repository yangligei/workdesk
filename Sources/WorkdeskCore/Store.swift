import Foundation
import CSQLite

public struct Project: Identifiable, Codable, Sendable {
 public let id: String; public let title: String; public var stage: String = ""; public var version: Int = 1
 public var status: String = "待办"
 public var deadline: Date? = nil
 public var timeZone: String = TimeZone.current.identifier
 public var reminderHours: [Double] = [24]
}
public struct WorkTask: Identifiable, Sendable {
 public let id: String
 public let title: String
 public let status: String
 public let version: Int
 public var archived: Bool = false
 public var completedAt: Date? = nil
}
public struct ArchivedTask: Identifiable, Sendable {
 public let id: String
 public let title: String
 public let status: String
 public let version: Int
 public let completedAt: Date?
 public let projectID: String
 public let projectTitle: String
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
  CREATE TABLE IF NOT EXISTS tasks(id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE, title TEXT NOT NULL, status TEXT NOT NULL DEFAULT '待办', version INTEGER NOT NULL DEFAULT 1, archived INTEGER NOT NULL DEFAULT 0, completed_at REAL);
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
  if !columns.contains("status") {
   _ = try Self.execute(handle, "ALTER TABLE projects ADD COLUMN status TEXT NOT NULL DEFAULT '待办'")
   _ = try Self.execute(handle, "UPDATE projects SET status=CASE WHEN EXISTS(SELECT 1 FROM tasks WHERE project_id=projects.id AND status='阻塞') THEN '阻塞' WHEN EXISTS(SELECT 1 FROM tasks WHERE project_id=projects.id) AND NOT EXISTS(SELECT 1 FROM tasks WHERE project_id=projects.id AND status!='完成') THEN '完成' WHEN EXISTS(SELECT 1 FROM tasks WHERE project_id=projects.id AND status='进行中') THEN '进行中' ELSE '待办' END")
  }
  let taskColumns = try Self.execute(handle, "PRAGMA table_info(tasks)").map { $0[1] }
  if !taskColumns.contains("archived") { _ = try Self.execute(handle, "ALTER TABLE tasks ADD COLUMN archived INTEGER NOT NULL DEFAULT 0") }
  if !taskColumns.contains("completed_at") {
   _ = try Self.execute(handle, "ALTER TABLE tasks ADD COLUMN completed_at REAL")
   // 迁移时刻起算 12 小时，历史完成任务不会被立即归档。
   _ = try Self.execute(handle, "UPDATE tasks SET completed_at=? WHERE status='完成' AND completed_at IS NULL", [String(Date().timeIntervalSince1970)])
  }
  _ = try Self.execute(handle, "CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
  _ = try Self.execute(handle, "PRAGMA user_version=5")
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
  try query("SELECT id,title,stage,version,deadline,timezone,reminders,status FROM projects ORDER BY rowid").map { Project(id: $0[0], title: $0[1], stage: $0[2], version: Int($0[3])!, status: $0[7], deadline: Double($0[4]).map { Date(timeIntervalSince1970: $0) }, timeZone: $0[5], reminderHours: (try? JSONDecoder().decode([Double].self, from: Data($0[6].utf8))) ?? [24]) }
 }
 public func createProject(_ text: String) throws -> Project {
  let item = Project(id: UUID().uuidString, title: try title(text), timeZone: "UTC")
  _ = try query("INSERT INTO projects(id,title) VALUES(?,?)", [item.id, item.title]); return item
 }
 public func updateProject(_ id: String, title text: String, stage: String, expected: Int) throws {
  _ = try query("UPDATE projects SET title=?,stage=?,version=version+1 WHERE id=? AND version=?", [try title(text), stage, id, String(expected)])
  guard sqlite3_changes(db) == 1 else { throw StoreError.conflict }
 }
 public func updateProjectStatus(_ id: String, status: String, expected: Int) throws {
  guard ["待办", "进行中", "阻塞", "完成"].contains(status) else { throw StoreError.database("无效状态") }
  _ = try query("UPDATE projects SET status=?,version=version+1 WHERE id=? AND version=?", [status, id, String(expected)])
  guard sqlite3_changes(db) == 1 else { throw StoreError.conflict }
 }
 public func deleteProject(_ id: String) throws { _ = try query("DELETE FROM projects WHERE id=?", [id]) }
 public func tasks(_ project: String, includeArchived: Bool = false) throws -> [WorkTask] {
  try query("SELECT id,title,status,version,archived,completed_at FROM tasks WHERE project_id=?" + (includeArchived ? "" : " AND archived=0") + " ORDER BY rowid", [project]).map {
   WorkTask(id: $0[0], title: $0[1], status: $0[2], version: Int($0[3])!, archived: $0[4] == "1", completedAt: Double($0[5]).map { Date(timeIntervalSince1970: $0) })
  }
 }
 public func archivedTasks(_ project: String? = nil) throws -> [ArchivedTask] {
  let sql = "SELECT t.id,t.title,t.status,t.version,t.completed_at,p.id,p.title FROM tasks t JOIN projects p ON p.id=t.project_id WHERE t.archived=1" + (project == nil ? "" : " AND t.project_id=?") + " ORDER BY COALESCE(t.completed_at,0) DESC, t.rowid DESC"
  return try query(sql, project.map { [$0] } ?? []).map {
   ArchivedTask(id: $0[0], title: $0[1], status: $0[2], version: Int($0[3])!, completedAt: Double($0[4]).map { Date(timeIntervalSince1970: $0) }, projectID: $0[5], projectTitle: $0[6])
  }
 }
 public func createTask(_ project: String, title text: String) throws -> WorkTask {
  let item = WorkTask(id: UUID().uuidString, title: try title(text), status: "待办", version: 1)
  _ = try query("INSERT INTO tasks(id,project_id,title) VALUES(?,?,?)", [item.id, project, item.title]); return item
 }
 public func updateTask(_ id: String, title text: String, status: String, expected: Int) throws {
  guard ["待办", "进行中", "阻塞", "完成"].contains(status) else { throw StoreError.database("无效状态") }
  let now = String(Date().timeIntervalSince1970)
  // 只在进入／离开“完成”的转换上写 completed_at，其余编辑保持原时间。
  _ = try query("""
  UPDATE tasks SET title=?,status=?,
   archived=CASE WHEN status!='完成' AND ?='完成' THEN 0 WHEN status='完成' AND ?!='完成' THEN 0 ELSE archived END,
   completed_at=CASE WHEN status!='完成' AND ?='完成' THEN ? WHEN status='完成' AND ?!='完成' THEN NULL ELSE completed_at END,
   version=version+1
  WHERE id=? AND version=?
  """, [try title(text), status, status, status, status, now, status, id, String(expected)])
  guard sqlite3_changes(db) == 1 else { throw StoreError.conflict }
 }
 public func restoreTask(_ id: String, expected: Int) throws {
  _ = try query("UPDATE tasks SET archived=0,status='待办',completed_at=NULL,version=version+1 WHERE id=? AND version=?", [id, String(expected)])
  guard sqlite3_changes(db) == 1 else { throw StoreError.conflict }
 }
 public func autoArchiveEnabled() throws -> Bool {
  try query("SELECT value FROM settings WHERE key='auto_archive'").first.map { $0[0] != "0" } ?? true
 }
 public func setAutoArchive(_ enabled: Bool) throws {
  _ = try query("INSERT INTO settings(key,value) VALUES('auto_archive',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [enabled ? "1" : "0"])
 }
 /// 事件驱动的自动归档：完成满 12 小时且开关开启时标记归档，在 Model.reload() 时调用。
 @discardableResult
 public func sweepArchive(now: Date = Date()) throws -> Int {
  guard try autoArchiveEnabled() else { return 0 }
  _ = try query("UPDATE tasks SET archived=1 WHERE status='完成' AND archived=0 AND completed_at IS NOT NULL AND completed_at<=?", [String(now.timeIntervalSince1970 - 12 * 3600)])
  return Int(sqlite3_changes(db))
 }
 public func deleteTask(_ id: String) throws { _ = try query("DELETE FROM tasks WHERE id=?", [id]) }
}
