import Foundation

public struct ProgressEvent: Codable, Sendable {
 public var schemaVersion = 1
 public var eventID = UUID().uuidString
 public var sourceID: String
 public var projectID: String
 public var taskID: String?
 public var occurredAt = ISO8601DateFormatter().string(from: Date())
 public var type: String
 public var text: String
 public var expectedVersion: Int?
 public init(sourceID: String, projectID: String, type: String, text: String, taskID: String? = nil, expectedVersion: Int? = nil) {
  self.sourceID = sourceID; self.projectID = projectID; self.type = type; self.text = text; self.taskID = taskID; self.expectedVersion = expectedVersion
 }
}
public struct Receipt: Codable, Equatable, Sendable {
 public let eventID: String
 public let outcome: String
 public let detail: String
}
public struct AuditEntry: Identifiable, Sendable {
 public let id: String; public let source: String; public let project: String; public let occurred: String; public let received: String; public let type: String; public let text: String; public let outcome: String
}
public struct SourceBinding: Identifiable, Sendable {
 public var id: String { source + ":" + alias }
 public let source: String; public let alias: String; public let project: String
}
public extension Store {
 func exportProjects(to root: URL) throws {
  try JSONEncoder().encode(projects()).write(to: root.appendingPathComponent("projects.json"), options: .atomic)
 }
 func integrationSchema() throws {
  _ = try query("CREATE TABLE IF NOT EXISTS bindings(source TEXT NOT NULL,alias TEXT NOT NULL,project TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,PRIMARY KEY(source,alias))")
  _ = try query("CREATE TABLE IF NOT EXISTS events(source TEXT NOT NULL,id TEXT NOT NULL,project TEXT NOT NULL,occurred TEXT NOT NULL,received TEXT NOT NULL,type TEXT NOT NULL,text TEXT NOT NULL,outcome TEXT NOT NULL,detail TEXT NOT NULL,PRIMARY KEY(source,id))")
 }
 func bind(source: String, alias: String, project: String) throws {
  try integrationSchema()
  _ = try query("INSERT INTO bindings(source,alias,project) VALUES(?,?,?) ON CONFLICT(source,alias) DO UPDATE SET project=excluded.project", [try title(source), try title(alias), project])
 }
 func bindings() throws -> [SourceBinding] {
  try integrationSchema()
  return try query("SELECT source,alias,project FROM bindings ORDER BY source,alias").map { SourceBinding(source: $0[0], alias: $0[1], project: $0[2]) }
 }
 func unbind(source: String, alias: String) throws {
  try integrationSchema(); _ = try query("DELETE FROM bindings WHERE source=? AND alias=?", [source, alias])
 }
 func audit() throws -> [AuditEntry] {
  try integrationSchema()
  return try query("SELECT source,id,project,occurred,received,type,text,outcome FROM events ORDER BY rowid DESC LIMIT 200").map { AuditEntry(id: $0[0]+":"+$0[1], source: $0[0], project: $0[2], occurred: $0[3], received: $0[4], type: $0[5], text: $0[6], outcome: $0[7]) }
 }
 func receive(_ event: ProgressEvent) throws -> Receipt {
  try integrationSchema()
  _ = try query("BEGIN IMMEDIATE")
  do {
   if let row = try query("SELECT outcome,detail FROM events WHERE source=? AND id=?", [event.sourceID,event.eventID]).first {
    _ = try query("COMMIT"); return Receipt(eventID: event.eventID, outcome: row[0], detail: row[1])
   }
   var outcome = "rejected", detail = "无效事件或未授权来源/项目"
   let mapping = try query("SELECT project FROM bindings WHERE source=? AND alias=?", [event.sourceID,event.projectID]).first?.first
   if event.schemaVersion == 1, !event.eventID.isEmpty, event.eventID.utf8.count <= 128, event.sourceID.utf8.count <= 128, event.text.utf8.count <= 32000, ISO8601DateFormatter().date(from: event.occurredAt) != nil, let project = mapping {
    switch event.type {
    case "task.create":
     if !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let task = try createTask(project, title: event.text); outcome = "accepted"; detail = task.id
     }
    case "task.rename":
     if let id = event.taskID, let version = event.expectedVersion, let task = try tasks(project).first(where: { $0.id == id }) {
      if task.version != version { outcome = "conflict"; detail = "版本冲突，正式任务未变更" }
      else if !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
       try updateTask(id, title: event.text, status: task.status, expected: version); outcome = "accepted"; detail = id
      }
     }
    case "progress": outcome = "accepted"; detail = "仅记录进度，不改变正式状态"
    default: detail = "不支持的类型；任务完成须本地确认"
    }
   }
   _ = try query("INSERT INTO events(source,id,project,occurred,received,type,text,outcome,detail) VALUES(?,?,?,?,?,?,?,?,?)", [event.sourceID,event.eventID,mapping ?? event.projectID,event.occurredAt,ISO8601DateFormatter().string(from: Date()),event.type,event.text,outcome,detail])
   _ = try query("COMMIT")
   return Receipt(eventID: event.eventID, outcome: outcome, detail: detail)
  } catch { _ = try? query("ROLLBACK"); throw error }
 }
}
