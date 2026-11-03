import SwiftUI
import WorkdeskCore

struct DeadlineLabel: View {
 let project: Project
 let tasks: [WorkTask]
 var body: some View {
  if let deadline = project.deadline {
   let overdue = deadline < Date() && !(tasks.allSatisfy { $0.status == "完成" } && !tasks.isEmpty)
   Text((overdue ? "逾期 · " : "截止 · ") + formatted(deadline) + " · " + project.timeZone)
    .font(.system(size: 12, weight: overdue ? .semibold : .regular))
    .foregroundStyle(overdue ? Color.red : Color.secondary)
  }
 }
 private func formatted(_ date: Date) -> String {
  let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm"
  formatter.timeZone = TimeZone(identifier: project.timeZone) ?? .current
  return formatter.string(from: date)
 }
}

struct NotificationSettings: View {
 @ObservedObject var notifications: DeadlineNotifications
 var body: some View {
  VStack(alignment: .leading, spacing: 8) {
   Text("截止提醒").font(.headline)
   Text(notifications.status).font(.caption).foregroundStyle(.secondary)
   Button("启用系统通知") { Task { await notifications.request() } }.buttonStyle(DeskButton())
   Text("正式签名且获授权后由 macOS 安排；退出后送达取决于系统，不能保证。当前本地 ad-hoc 构建仅提供应用内提示。睡眠、专注模式与系统权限会影响送达。错过的提醒不补发，逾期在项目总览显示。所有任务完成时取消；没有任务的项目仍会提醒。").font(.caption).foregroundStyle(.secondary)
  }
 }
}
