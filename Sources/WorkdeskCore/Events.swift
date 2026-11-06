import Foundation
import CryptoKit

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
 public var signature: String?
 public var transport: String?
 public init(sourceID: String, projectID: String, type: String, text: String, taskID: String? = nil, expectedVersion: Int? = nil) {
  self.sourceID = sourceID; self.projectID = projectID; self.type = type; self.text = text; self.taskID = taskID; self.expectedVersion = expectedVersion
 }
 /// Stable field framing prevents ambiguous concatenation between signed fields.
 public var signingPayload: Data {
  Data([String(schemaVersion), sourceID, projectID, taskID ?? "", occurredAt, type, text, expectedVersion.map(String.init) ?? "", eventID].appendingTransport(transport).map { "\($0.utf8.count):\($0)" }.joined(separator: "|").utf8)
 }
}
private extension Array where Element == String {
 func appendingTransport(_ transport: String?) -> [String] { transport.map { self + ["transport", $0] } ?? self }
}
public enum EventSigning {
 public static func sign(_ event: inout ProgressEvent, privateKey: String) throws {
  guard let data = Data(base64Encoded: privateKey), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else { throw StoreError.database("凭据文件无效") }
  event.signature = try key.signature(for: event.signingPayload).base64EncodedString()
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
  _ = try query("CREATE TABLE IF NOT EXISTS source_capabilities(source TEXT PRIMARY KEY,create_projects INTEGER NOT NULL DEFAULT 0)")
  _ = try query("CREATE TABLE IF NOT EXISTS bindings(source TEXT NOT NULL,alias TEXT NOT NULL,project TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,PRIMARY KEY(source,alias))")
  _ = try query("CREATE TABLE IF NOT EXISTS events(source TEXT NOT NULL,id TEXT NOT NULL,project TEXT NOT NULL,occurred TEXT NOT NULL,received TEXT NOT NULL,type TEXT NOT NULL,text TEXT NOT NULL,outcome TEXT NOT NULL,detail TEXT NOT NULL,PRIMARY KEY(source,id))")
  _ = try query("CREATE TABLE IF NOT EXISTS event_requests(source TEXT NOT NULL,id TEXT NOT NULL,alias TEXT NOT NULL,type TEXT NOT NULL,text TEXT NOT NULL,transport TEXT NOT NULL,PRIMARY KEY(source,id))")
 }
 func bind(source: String, alias: String, project: String) throws {
  try mcpSchema()
  if let old = try query("SELECT project FROM bindings WHERE source=? AND alias=?", [source, alias]).first?.first, old != project {
   _ = try query("DELETE FROM mcp_grants WHERE source=? AND alias=?", [source, alias])
  }
  _ = try query("INSERT INTO bindings(source,alias,project) VALUES(?,?,?) ON CONFLICT(source,alias) DO UPDATE SET project=excluded.project", [try title(source), try title(alias), project])
 }
 func bindings() throws -> [SourceBinding] {
  try integrationSchema()
  return try query("SELECT source,alias,project FROM bindings ORDER BY source,alias").map { SourceBinding(source: $0[0], alias: $0[1], project: $0[2]) }
 }
 func unbind(source: String, alias: String) throws {
  try mcpSchema()
  _ = try query("DELETE FROM mcp_grants WHERE source=? AND alias=?", [source, alias])
  _ = try query("DELETE FROM bindings WHERE source=? AND alias=?", [source, alias])
 }
 func audit() throws -> [AuditEntry] {
  try integrationSchema()
  return try query("SELECT source,id,project,occurred,received,type,text,outcome FROM events ORDER BY rowid DESC LIMIT 200").map { AuditEntry(id: $0[0]+":"+$0[1], source: $0[0], project: $0[2], occurred: $0[3], received: $0[4], type: $0[5], text: $0[6], outcome: $0[7]) }
 }
 /// Project-scoped history is independent of the global audit's 200-event window.
 func projectProgress(_ project: String) throws -> [AuditEntry] {
  try integrationSchema()
  return try query("SELECT source,id,project,occurred,received,type,text,outcome FROM events WHERE project=? AND type='progress' AND outcome='accepted' ORDER BY rowid DESC LIMIT 20", [project]).map { AuditEntry(id: $0[0]+":"+$0[1], source: $0[0], project: $0[2], occurred: $0[3], received: $0[4], type: $0[5], text: $0[6], outcome: $0[7]) }
 }
 func receive(_ event: ProgressEvent) throws -> Receipt {
  try integrationSchema()
  guard let signature = event.signature, try verify(source: event.sourceID, message: event.signingPayload, signature: signature) else {
   return Receipt(eventID: event.eventID, outcome: "rejected", detail: "签名缺失或无效；拒绝写入")
  }
  _ = try query("BEGIN IMMEDIATE")
  do {
   let mapping = try query("SELECT project FROM bindings WHERE source=? AND alias=?", [event.sourceID, event.projectID]).first?.first
   let mayCreate = try event.type == "project.create" && (query("SELECT source FROM source_capabilities WHERE source=? AND create_projects=1", [event.sourceID])).count == 1
   guard mapping != nil || mayCreate else {
    _ = try query("COMMIT")
    return Receipt(eventID: event.eventID, outcome: "rejected", detail: "未授权来源/项目")
   }
   let creationTasks = try event.transport == "mcp" ? mcpCreationPermission(source: event.sourceID) : nil
   if event.type == "project.create", !mayCreate || (event.transport == "mcp" && creationTasks == nil) {
    _ = try query("COMMIT")
    return Receipt(eventID: event.eventID, outcome: "rejected", detail: "未授权创建新项目，请在本机连接中心授权")
   }
   if event.transport != nil {
    let permission = try mcpPermission(source: event.sourceID, alias: event.projectID)
    let creating = event.type == "project.create" && mayCreate && creationTasks != nil && (mapping == nil || permission != nil)
    guard event.transport == "mcp", creating || (permission != nil && (event.type == "progress" || (event.type == "task.create" && permission == true))) else {
     _ = try query("COMMIT")
     return Receipt(eventID: event.eventID, outcome: "rejected", detail: "MCP 未授权此项目或任务创建操作")
    }
   }
   if let row = try query("SELECT outcome,detail,project,type,text FROM events WHERE source=? AND id=?", [event.sourceID,event.eventID]).first {
    let request = try query("SELECT alias,type,text,transport FROM event_requests WHERE source=? AND id=?", [event.sourceID,event.eventID]).first
    let changed = request.map { $0 != [event.projectID, event.type, event.text, event.transport ?? ""] } ?? (row[2] != mapping || row[3] != event.type || row[4] != event.text)
    _ = try query("COMMIT")
    if event.transport == "mcp", changed || (row[0] == "accepted" && row[2] != mapping) {
     return Receipt(eventID: event.eventID, outcome: "conflict", detail: "event_id 已用于不同操作；未写入")
    }
    return Receipt(eventID: event.eventID, outcome: row[0], detail: row[1])
   }
   var outcome = "rejected", detail = "无效事件或未授权来源/项目"
   if event.schemaVersion == 1, !event.eventID.isEmpty, event.eventID.utf8.count <= 128, event.sourceID.utf8.count <= 128, event.text.utf8.count <= 32000, ISO8601DateFormatter().date(from: event.occurredAt) != nil {
    let project = mapping ?? ""
    switch event.type {
    case "project.create":
     if mayCreate, mapping == nil, !event.projectID.isEmpty, event.projectID == event.projectID.trimmingCharacters(in: .whitespacesAndNewlines), event.projectID.utf8.count <= 128, !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let created = try createProject(event.text)
      try bind(source: event.sourceID, alias: event.projectID, project: created.id)
      if let creationTasks { try setMCPPermission(source: event.sourceID, alias: event.projectID, enabled: true, createTasks: creationTasks) }
      outcome = "accepted"; detail = created.id
     } else { detail = "项目别名已占用或缺少创建许可" }
    case "draft.confirm":
     if let id = event.taskID {
      try meetingSchema()
      if let row = try query("SELECT drafts.task FROM drafts JOIN meetings ON drafts.meeting=meetings.id WHERE drafts.id=? AND meetings.project=?", [id,project]).first {
       if row[0].isEmpty {
        let task = try createTask(project, title: event.text)
        _ = try query("UPDATE drafts SET task=?,title=? WHERE id=?", [task.id,task.title,id])
        detail = task.id
       } else { detail = row[0] }
       outcome = "accepted"
      }
     }
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
   _ = try query("INSERT INTO event_requests(source,id,alias,type,text,transport) VALUES(?,?,?,?,?,?)", [event.sourceID,event.eventID,event.projectID,event.type,event.text,event.transport ?? ""])
   _ = try query("INSERT INTO events(source,id,project,occurred,received,type,text,outcome,detail) VALUES(?,?,?,?,?,?,?,?,?)", [event.sourceID,event.eventID,mapping ?? (outcome == "accepted" ? detail : ""),event.occurredAt,ISO8601DateFormatter().string(from: Date()),event.type,event.text,outcome,detail])
   _ = try query("COMMIT")
   return Receipt(eventID: event.eventID, outcome: outcome, detail: detail)
  } catch { _ = try? query("ROLLBACK"); throw error }
 }
}
