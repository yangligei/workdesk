import Foundation

public extension Store {
 func setDeadline(_ id: String, date: Date?, timeZone: String, hours: [Double], expected: Int) throws {
  guard TimeZone(identifier: timeZone) != nil, hours.count <= 16, hours.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 87600 }), date?.timeIntervalSince1970.isFinite != false else { throw StoreError.database("时区或提醒无效；最多 16 个，小时数须大于 0 且不超过 87600") }
  let encoded = String(decoding: try JSONEncoder().encode(Array(Set(hours)).sorted()), as: UTF8.self)
  _ = try query("UPDATE projects SET deadline=NULLIF(?,''),timezone=?,reminders=?,version=version+1 WHERE id=? AND version=?", [date.map { String($0.timeIntervalSince1970) } ?? "", timeZone, encoded, id, String(expected)])
  // Querying the updated version cannot distinguish a stale writer, so use SQLite changes().
  guard try query("SELECT changes()").first?.first == "1" else { throw StoreError.conflict }
 }
}
public struct PlannedReminder: Equatable, Sendable {
 public let id: String
 public let project: String
 public let title: String
 public let fire: Date
}
public enum DeadlinePlan {
 /// Missed reminders are never replayed as notifications. Overdue remains visible in-app.
 /// Completion means a nonempty task list where every task is complete.
 public static func reminders(projects: [Project], tasks: [String: [WorkTask]], now: Date) -> [PlannedReminder] {
  projects.flatMap { project -> [PlannedReminder] in
   guard let deadline = project.deadline else { return [] }
   let list = tasks[project.id] ?? []
   guard list.isEmpty || !list.allSatisfy({ $0.status == "完成" }) else { return [] }
   return Set(project.reminderHours).compactMap { hours -> PlannedReminder? in
    guard hours.isFinite, hours > 0, hours <= 87600 else { return nil }
    let fire = deadline.addingTimeInterval(-hours * 3600)
    guard fire > now else { return nil }
    return PlannedReminder(id: "ddl.\(project.id).\(deadline.timeIntervalSince1970).\(hours)", project: project.id, title: project.title, fire: fire)
   }
  }.sorted { $0.fire < $1.fire }.prefix(60).map { $0 }
 }
}
