import SwiftUI
import WorkdeskCore

// 归档窗口：按已确认设计稿（workdesk-archive-2.png）实现。
// 开关、筛选标签、恢复/删除按钮点击区均 ≥44pt。
struct ArchiveView: View {
 @ObservedObject var model: Model
 @State private var filter = "全部"
 @State private var taskToDelete: ArchivedTask?
 private var tabs: [String] { ["全部"] + model.projects.map(\.title) }
 private var visible: [ArchivedTask] { model.archivedTasks.filter { filter == "全部" || $0.projectTitle == filter } }
 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 16) {
    HStack(alignment: .firstTextBaseline) {
     Text("归档").font(.system(size: 21, weight: .semibold))
     Spacer()
     Text("共 \(model.archivedTasks.count) 条").font(.system(size: 11)).foregroundStyle(.secondary)
    }
    Text("完成的任务在 12 小时后自动进入此处，可随时恢复。").font(.system(size: 11)).foregroundStyle(.secondary)
    Button { model.setAutoArchive(!model.autoArchive) } label: {
     HStack {
      Text("自动归档：完成后 12 小时").font(.system(size: 13.5, weight: .medium))
      Spacer()
      ArchiveSwitch(on: model.autoArchive)
     }.padding(.horizontal, 16).padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
    }.buttonStyle(.plain)
     .background(Desk.sidebar, in: RoundedRectangle(cornerRadius: 8))
     .accessibilityLabel("自动归档开关").accessibilityValue(model.autoArchive ? "已开启" : "已关闭")
    ScrollView(.horizontal, showsIndicators: false) {
     HStack(spacing: 8) {
      ForEach(tabs.indices, id: \.self) { index in
       let name = tabs[index]
       Button { filter = name } label: {
        Text(name).font(.system(size: 13, weight: .medium)).fixedSize()
         .padding(.horizontal, 15).padding(.vertical, 12)
         .frame(minHeight: 44).contentShape(Rectangle())
         .foregroundStyle(filter == name ? Desk.green : Desk.ink)
         .background(filter == name ? Desk.selected : Desk.sidebar, in: RoundedRectangle(cornerRadius: 6))
       }.buttonStyle(.plain).accessibilityLabel("筛选归档：" + name)
      }
     }
    }
    Text("已归档 · \(visible.count) 条").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
    if visible.isEmpty {
     Text(filter == "全部" ? "暂无归档任务" : "该项目暂无归档任务").font(.system(size: 13.5)).foregroundStyle(.secondary).padding(.vertical, 24)
    }
    ForEach(visible) { task in
     VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
       Circle().fill(Color.gray.opacity(0.4)).frame(width: 5, height: 5).padding(.top, 8)
       VStack(alignment: .leading, spacing: 5) {
        Text(task.title).font(.system(size: 13.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
        Text("\(task.projectTitle) · \(task.completedAt.map(FocusPanel.archiveTimestamp) ?? "未知时间") 归档")
         .font(.system(size: 11)).foregroundStyle(.secondary)
       }.frame(maxWidth: .infinity, alignment: .leading)
       Text(task.status).font(.system(size: 13, weight: .semibold))
        .foregroundStyle(StatusAppearance.foreground(task.status))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(StatusAppearance.background(task.status), in: RoundedRectangle(cornerRadius: 6))
      }
      HStack(spacing: 12) {
       Button { model.restoreTask(task) } label: {
        Text("恢复为待办").font(.system(size: 13, weight: .medium)).foregroundStyle(Desk.green)
         .frame(minWidth: 140, minHeight: 44).contentShape(Rectangle())
         .overlay(RoundedRectangle(cornerRadius: 8).stroke(Desk.green, lineWidth: 1))
       }.buttonStyle(.plain).accessibilityLabel("恢复任务：" + task.title)
       Button { taskToDelete = task } label: {
        Text("删除").font(.system(size: 13, weight: .medium))
         .foregroundStyle(StatusAppearance.foreground("阻塞"))
         .frame(minWidth: 120, minHeight: 44).contentShape(Rectangle())
         .overlay(RoundedRectangle(cornerRadius: 8).stroke(StatusAppearance.foreground("阻塞"), lineWidth: 1))
       }.buttonStyle(.plain).accessibilityLabel("删除归档任务：" + task.title)
       Spacer()
      }
     }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }
    Text("归档不删除数据；恢复后任务回到原项目并重新计时。").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
   }.padding(24)
  }
  .background(Desk.sidebar).foregroundStyle(Desk.ink).preferredColorScheme(.light)
  .confirmationDialog("删除这条归档任务？", isPresented: Binding(get: { taskToDelete != nil }, set: { if !$0 { taskToDelete = nil } }), titleVisibility: .visible) {
   Button("删除", role: .destructive) { if let task = taskToDelete { model.deleteArchivedTask(task) }; taskToDelete = nil }
   Button("取消", role: .cancel) { taskToDelete = nil }
  } message: { Text(taskToDelete?.title ?? "") }
  .alert("操作失败", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
   Button("刷新") { model.error = nil; model.perform { await model.reload() } }
  } message: { Text(model.error ?? "") }
 }
}

struct ArchiveSwitch: View {
 let on: Bool
 var body: some View {
  ZStack {
   Capsule().fill(on ? Desk.green : Color.gray.opacity(0.3)).frame(width: 46, height: 28)
   Circle().fill(.white).frame(width: 24, height: 24).shadow(color: .black.opacity(0.15), radius: 1, y: 0.5).offset(x: on ? 10 : -10)
  }.animation(.easeInOut(duration: 0.15), value: on)
 }
}
