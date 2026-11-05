import SwiftUI
import WorkdeskCore

// Values taken from the agreed HTML references. Native controls retain keyboard and AX support.
enum Desk {
 static let ink = Color(red: 0.14, green: 0.17, blue: 0.16)
 static let green = Color(red: 0.157, green: 0.384, blue: 0.278)
 static let sidebar = Color(red: 0.973, green: 0.977, blue: 0.969)
 static let wash = Color(red: 0.945, green: 0.957, blue: 0.941)
 static let selected = Color(red: 0.91, green: 0.937, blue: 0.918)
}
struct DeskButton: ButtonStyle {
 @Environment(\.isEnabled) private var enabled
 var primary = false
 func makeBody(configuration: Configuration) -> some View {
  configuration.label.font(.system(size: 13, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 10)
   .foregroundStyle(primary ? .white : Desk.green)
   .background(primary ? Desk.green : Desk.wash, in: RoundedRectangle(cornerRadius: 6))
   .contentShape(Rectangle())
   .opacity(!enabled ? 0.4 : (configuration.isPressed ? 0.65 : 1))
 }
}
enum StatusAppearance {
 static func symbol(_ value: String) -> String {
  switch value { case "进行中": return "◐"; case "阻塞": return "!"; case "完成", "已完成": return "✓"; default: return "○" }
 }
 static func foreground(_ value: String) -> Color {
  switch value {
  case "进行中": return Color(red: 0.14, green: 0.36, blue: 0.56)
  case "阻塞": return Color(red: 0.62, green: 0.25, blue: 0.15)
  case "完成", "已完成": return Desk.green
  default: return Color(red: 0.32, green: 0.36, blue: 0.39)
  }
 }
 static func background(_ value: String) -> Color {
  switch value {
  case "进行中": return Color(red: 0.91, green: 0.95, blue: 0.98)
  case "阻塞": return Color(red: 0.99, green: 0.93, blue: 0.90)
  case "完成", "已完成": return Color(red: 0.91, green: 0.95, blue: 0.92)
  default: return Color(red: 0.94, green: 0.945, blue: 0.95)
  }
 }
}
struct StatusPill: View {
 let text: String
 var body: some View { Text(StatusAppearance.symbol(text) + " " + text).font(.system(size: 12)).padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(StatusAppearance.foreground(text)).background(StatusAppearance.background(text), in: RoundedRectangle(cornerRadius: 4)) }
}
func projectStatus(_ tasks: [WorkTask]) -> String {
 if tasks.isEmpty { return "暂无任务" }
 if tasks.contains(where: { $0.status == "阻塞" }) { return "阻塞" }
 if tasks.allSatisfy({ $0.status == "完成" }) { return "已完成" }
 return tasks.contains(where: { $0.status == "进行中" }) ? "进行中" : "待办"
}
struct ProjectOverview: View {
 @ObservedObject var model: Model
 let openProject: () -> Void
 @State private var query = ""
 @State private var filter = "全部项目"
 @FocusState private var searching: Bool
 var projects: [Project] { model.projects.filter { project in
  let status = project.status == "完成" ? "已完成" : project.status
  return (query.isEmpty || project.title.localizedCaseInsensitiveContains(query)) && (filter == "全部项目" || (filter == "已完成" ? status == "已完成" : status != "已完成"))
 } }
 var body: some View {
  VStack(alignment: .leading, spacing: 26) {
   HStack {
    VStack(alignment: .leading, spacing: 10) { Text("项目总览").font(.system(size: 24, weight: .semibold)); Text("把注意力放在下一步").foregroundStyle(.secondary) }
    Spacer()
    AgentStatus(model: model)
   }
   HStack(spacing: 24) {
    ForEach(["全部项目", "未完成", "已完成"], id: \.self) { value in
     Button(value) { filter = value }.buttonStyle(.plain).foregroundStyle(filter == value ? Desk.green : Desk.ink).fontWeight(filter == value ? .semibold : .regular)
    }
    Spacer()
    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
    TextField("搜索项目", text: $query).textFieldStyle(.plain).frame(width: 130).focused($searching)
    Button("⌘ F") { searching = true }.buttonStyle(.plain).foregroundStyle(.secondary).keyboardShortcut("f")
   }
   ScrollView {
    VStack(spacing: 0) {
     Divider()
     ForEach(projects) { project in
      let tasks = model.projectTasks[project.id] ?? []
      Button { model.selection = project.id; openProject() } label: {
       HStack(spacing: 20) {
        VStack(alignment: .leading, spacing: 12) {
         Text(project.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Desk.ink)
         Text((project.stage.isEmpty ? "阶段未设置" : project.stage) + " → 下一步：" + (tasks.first { $0.status != "完成" }?.title ?? "暂无待办"))
          .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
         if let entry = model.projectProgress[project.id]?.first {
          Text("最近进展 · " + entry.text).font(.system(size: 13)).foregroundStyle(Desk.green).lineLimit(2).multilineTextAlignment(.leading)
         }
        }
        Spacer(minLength: 12)
        StatusPill(text: project.status)
        Text("\(tasks.filter { $0.status == "完成" }.count) / \(tasks.count) 项完成").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 92, alignment: .trailing)
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
       }.padding(.vertical, 25).contentShape(Rectangle())
      }.buttonStyle(.plain)
      Divider()
     }
     if projects.isEmpty {
      VStack(alignment: .leading, spacing: 12) { Text(model.projects.isEmpty ? "从一个项目开始" : "没有匹配的项目").font(.headline); Text(model.projects.isEmpty ? "请在设置与接入中登记智能体，由智能体创建项目和任务。" : "调整筛选或搜索内容。").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 40)
     }
    }
   }
  }.padding(34)
 }
}
struct ProjectChooser: View {
 @ObservedObject var model: Model
 var body: some View {
  Picker("项目", selection: $model.selection) {
   Text("请选择项目").tag(String?.none)
   ForEach(model.projects) { Text($0.title).tag(Optional($0.id)) }
  }.frame(maxWidth: 340).onChange(of: model.selection) { _ in model.perform { await model.reload() } }
 }
}
struct FocusPanel: View {
 @ObservedObject var model: Model
 @State private var tabPosition = 0
 @State private var taskToDelete: WorkTask?
 /// 归档时间统一按 Asia/Shanghai 显示，「M月d日 HH:mm」。
 static func archiveTimestamp(_ date: Date) -> String {
  let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "M月d日 HH:mm"; return f.string(from: date)
 }
 static func completedLine(_ task: WorkTask) -> String {
  guard let completed = task.completedAt else { return "已完成" }
  let hours = 12 - Date().timeIntervalSince(completed) / 3600
  let suffix = hours <= 0 ? "即将自动归档" : String(format: "%.0f小时后自动归档", hours.rounded(.up))
  return "完成于 " + archiveTimestamp(completed) + " · " + suffix
 }
 private var today: String { let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 · EEEE"; return f.string(from: Date()) }
 var body: some View {
  VStack(alignment: .leading, spacing: 0) {
   HStack { Text("今日进度").font(.system(size: 16, weight: .semibold)); Spacer(); Text(today).font(.caption).foregroundStyle(.secondary) }.padding(20)
   ScrollViewReader { proxy in
    HStack(spacing: 5) {
     Button { moveTabs(-1, proxy) } label: { Image(systemName: "chevron.left") }.help("向左滚动项目")
     ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
       ForEach(Array(model.projects.enumerated()), id: \.element.id) { index, project in
        Button { model.selection = project.id; model.tasks = model.projectTasks[project.id] ?? []; tabPosition = index } label: {
         Text(project.title).font(.system(size: 13, weight: .medium)).fixedSize().padding(.horizontal, 15).padding(.vertical, 12)
          .foregroundStyle(model.selection == project.id ? Desk.green : Desk.ink)
          .background(model.selection == project.id ? Desk.selected : Desk.sidebar, in: RoundedRectangle(cornerRadius: 6))
        }.id(index).accessibilityLabel("切换项目：" + project.title)
       }
      }
     }
     Button { moveTabs(1, proxy) } label: { Image(systemName: "chevron.right") }.help("向右滚动项目")
    }.buttonStyle(.plain).padding(.horizontal, 14).padding(.bottom, 15)
   }
   Divider()
   ScrollView {
    VStack(alignment: .leading, spacing: 14) {
     if let project = model.projects.first(where: { $0.id == model.selection }) {
      let tasks = model.projectTasks[project.id] ?? []
      HStack(alignment: .top, spacing: 12) {
       VStack(alignment: .leading, spacing: 6) { Text(project.title).font(.system(size: 21, weight: .semibold)).fixedSize(horizontal: false, vertical: true); Text(project.stage.isEmpty ? "阶段未设置" : project.stage).font(.caption).foregroundStyle(.secondary) }
        .frame(maxWidth: .infinity, alignment: .leading)
       VStack(alignment: .trailing, spacing: 6) {
        Text("项目状态").font(.caption).foregroundStyle(.secondary)
        InlineStatus(value: project.status, label: "项目状态") { value in model.perform { try await model.store?.updateProjectStatus(project.id, status: value, expected: project.version); await model.reload() } }
         .layoutPriority(1)
       }
      }
      HStack(spacing: 12) {
       ProgressView(value: Double(tasks.filter { $0.status == "完成" }.count), total: Double(max(tasks.count, 1))).tint(Desk.green)
       Text("\(tasks.filter { $0.status == "完成" }.count) / \(tasks.count) 项完成").font(.caption).foregroundStyle(.secondary).fixedSize()
      }
      ProjectProgress(entries: model.projectProgress[project.id] ?? [])
      HStack {
       Text("项目任务").font(.system(size: 14, weight: .semibold))
       Spacer()
       Text("点击状态切换").font(.caption).foregroundStyle(.secondary)
       Button { ArchiveWindow.shared.show(model) } label: {
        Text("归档 (\(model.archivedTasks.count))").font(.system(size: 12, weight: .medium))
         .padding(.horizontal, 12).padding(.vertical, 10)
         .foregroundStyle(Desk.green).background(Desk.selected, in: RoundedRectangle(cornerRadius: 6))
         .frame(minHeight: 40).contentShape(Rectangle())
       }.buttonStyle(.plain).accessibilityLabel("打开归档列表")
      }
      VStack(spacing: 0) {
       ForEach(tasks) { task in
        HStack(alignment: .top, spacing: 12) {
         Circle().fill(task.status == "进行中" ? Desk.green : Color.gray.opacity(0.4)).frame(width: 5, height: 5).padding(.top, 21.5)
         VStack(alignment: .leading, spacing: 3) {
          Text(task.title).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
          if task.status == "完成" {
           Text(Self.completedLine(task)).font(.system(size: 11)).foregroundStyle(.secondary)
          }
         }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
         InlineStatus(value: task.status, label: task.title + "：任务状态") { model.update(task, status: $0) }
          .layoutPriority(1)
         Button { taskToDelete = task } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
          .buttonStyle(.plain).frame(width: 44, height: 48).contentShape(Rectangle()).help("删除任务")
        }.padding(.vertical, 3)
        Divider()
       }
       if tasks.isEmpty { Text("暂无任务").foregroundStyle(.secondary).padding(.vertical, 24) }
      }
     } else { Text("还没有项目").font(.headline); Text("请在设置与接入中登记智能体，由智能体创建项目和任务。").foregroundStyle(.secondary) }
    }.padding(20)
   }
   Divider()
   HStack {
    Text("完成的任务将在12小时后自动归档").font(.system(size: 11)).foregroundStyle(.secondary)
    Spacer()
    Button { ArchiveWindow.shared.show(model) } label: {
     HStack(spacing: 2) {
      Text("归档设置")
      Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
     }.font(.system(size: 11, weight: .medium)).foregroundStyle(Desk.green)
      .padding(.horizontal, 6).padding(.vertical, 9).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel("打开归档设置")
   }.padding(.horizontal, 20).padding(.vertical, 10)
   Divider()
   HStack { Text("已授权 \(model.bindings.count) 个项目映射"); Spacer(); Text("新增事项请交给已接入智能体").foregroundStyle(.secondary) }.font(.system(size: 11)).padding(20).background(Desk.sidebar)
  }.font(.system(size: 13.5)).background(.white).foregroundStyle(Desk.ink).preferredColorScheme(.light)
   .alert("操作失败", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("刷新") { model.error = nil; model.perform { await model.reload() } } } message: { Text(model.error ?? "") }
   .confirmationDialog("删除这条任务？", isPresented: Binding(get: { taskToDelete != nil }, set: { if !$0 { taskToDelete = nil } }), titleVisibility: .visible) {
    Button("删除", role: .destructive) { if let task = taskToDelete { model.deleteTask(task) }; taskToDelete = nil }
    Button("取消", role: .cancel) { taskToDelete = nil }
   } message: { Text(taskToDelete?.title ?? "") }
 }
 private func moveTabs(_ delta: Int, _ proxy: ScrollViewProxy) {
  tabPosition = max(0, min(model.projects.count - 1, tabPosition + delta))
  withAnimation { proxy.scrollTo(tabPosition, anchor: delta > 0 ? .trailing : .leading) }
 }
}
struct InlineStatus: View {
 let value: String
 let label: String
 let choose: (String) -> Void
 var body: some View {
  StatusMenuButton(value: value, label: label, choose: choose)
   .frame(width: 104, height: 48)

 }
}

struct ProjectProgress: View {
 let entries: [AuditEntry]
 @State private var expanded = false
 var body: some View {
  VStack(alignment: .leading, spacing: 8) {
   Text("最近进展").font(.system(size: 14, weight: .semibold))
   if let latest = entries.first {
    ProgressEntry(entry: latest)
    if entries.count > 1 {
     Button { expanded.toggle() } label: {
      HStack {
       Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption)
       Text("更早进展（\(entries.count - 1) 条）").fontWeight(.semibold)
       Spacer()
       Text(expanded ? "点击整行收起" : "点击整行展开").font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, minHeight: 40).contentShape(Rectangle())
     }.buttonStyle(.plain).accessibilityValue(expanded ? "已展开" : "已收起")
     if expanded {
      Divider()
      ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(Array(entries.dropFirst())) { ProgressEntry(entry: $0) } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 180)
     }
    }
   } else { Text("暂无已接受的进展").foregroundStyle(.secondary) }
  }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Desk.wash, in: RoundedRectangle(cornerRadius: 6))
 }
}
private struct ProgressEntry: View {
 let entry: AuditEntry
 var body: some View {
  VStack(alignment: .leading, spacing: 6) {
   Text(entry.text).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
   Text("\(entry.source) · 来源时间 \(entry.occurred)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
  }
 }
}
struct AgentStatus: View {
 @ObservedObject var model: Model
 var body: some View {
  VStack(alignment: .leading, spacing: 6) {
   Text(model.bindings.isEmpty ? "智能体尚未授权项目" : "已授权 \(model.bindings.count) 个项目映射").font(.caption)
   Text("新增事项请交给已接入智能体；接入说明见设置与接入。").font(.caption).foregroundStyle(.secondary)
  }
 }
}
