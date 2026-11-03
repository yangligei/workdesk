import Foundation
public struct Meeting: Identifiable, Sendable {
 public let id: String; public let text: String; public let version: Int
}
public struct MeetingDraft: Identifiable, Sendable {
 public let id: String; public let title: String; public let evidence: String; public let line: Int; public let taskID: String
}
public extension Store {
 func meetingSchema() throws {
  _ = try query("CREATE TABLE IF NOT EXISTS meetings(id TEXT PRIMARY KEY,project TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,text TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1)")
  _ = try query("CREATE TABLE IF NOT EXISTS drafts(id TEXT PRIMARY KEY,meeting TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,title TEXT NOT NULL,evidence TEXT NOT NULL,line INTEGER NOT NULL,task TEXT NOT NULL DEFAULT '')")
 }
 func meetings(_ project: String) throws -> [Meeting] {
  try meetingSchema()
  return try query("SELECT id,text,version FROM meetings WHERE project=? ORDER BY rowid DESC", [project]).map { Meeting(id: $0[0], text: $0[1], version: Int($0[2])!) }
 }
 /// Explicit markers only. No model, inferred owners, dates, or invented timestamps.
 func saveMeeting(project: String, text: String, id: String? = nil, expected: Int? = nil) throws -> String {
  try meetingSchema()
  guard text.utf8.count <= 262144 else { throw StoreError.database("会议文字超过 256 KiB") }
  _ = try title(text)
  let meetingID = id ?? UUID().uuidString
  _ = try query("BEGIN IMMEDIATE")
  do {
   if let id {
    guard let row = try query("SELECT version FROM meetings WHERE id=? AND project=?", [id, project]).first, Int(row[0]) == expected else { throw StoreError.conflict }
    guard try query("SELECT id FROM drafts WHERE meeting=? AND task<>''", [id]).isEmpty else { throw StoreError.database("已有确认任务；请新建会议修订以保留原始证据") }
    _ = try query("UPDATE meetings SET text=?,version=version+1 WHERE id=?", [text,id])
    _ = try query("DELETE FROM drafts WHERE meeting=?", [id])
   } else { _ = try query("INSERT INTO meetings(id,project,text) VALUES(?,?,?)", [meetingID,project,text]) }
   for (index, line) in text.components(separatedBy: .newlines).enumerated() {
    let markers = ["待办：", "待办:", "TODO:", "- [ ] "]
    guard let range = markers.compactMap({ line.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { continue }
    let taskTitle = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    guard !taskTitle.isEmpty else { continue }
    _ = try query("INSERT INTO drafts(id,meeting,title,evidence,line) VALUES(?,?,?,?,?)", [UUID().uuidString,meetingID,taskTitle,line,String(index+1)])
   }
   _ = try query("COMMIT"); return meetingID
  } catch { _ = try? query("ROLLBACK"); throw error }
 }
 func meetingDrafts(_ meeting: String) throws -> [MeetingDraft] {
  try meetingSchema()
  return try query("SELECT id,title,evidence,line,task FROM drafts WHERE meeting=? ORDER BY line", [meeting]).map { MeetingDraft(id: $0[0], title: $0[1], evidence: $0[2], line: Int($0[3])!, taskID: $0[4]) }
 }
 func confirmDraft(_ id: String, title text: String) throws {
  try meetingSchema(); _ = try query("BEGIN IMMEDIATE")
  do {
   guard let row = try query("SELECT meetings.project,drafts.task FROM drafts JOIN meetings ON drafts.meeting=meetings.id WHERE drafts.id=?", [id]).first else { throw StoreError.missing }
   if row[1].isEmpty {
    let task = try createTask(row[0], title: text)
    _ = try query("UPDATE drafts SET task=?,title=? WHERE id=?", [task.id,task.title,id])
   }
   _ = try query("COMMIT")
  } catch { _ = try? query("ROLLBACK"); throw error }
 }
}
