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
   .opacity(!enabled ? 0.4 : (configuration.isPressed ? 0.65 : 1))
 }
}
struct StatusPill: View {
 let text: String
 var body: some View { Text(text).font(.system(size: 12)).padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(text == "阻塞" ? Color.brown : Desk.green).background(text == "阻塞" ? Color.orange.opacity(0.09) : Desk.selected, in: RoundedRectangle(cornerRadius: 4)) }
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
  let status = projectStatus(model.projectTasks[project.id] ?? [])
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
        StatusPill(text: projectStatus(tasks))
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
 @State private var collapsed = false
 var body: some View {
  VStack(alignment: .leading, spacing: 0) {
   HStack { Text("今日进度").foregroundStyle(.secondary); Spacer(); Button { collapsed.toggle() } label: { Image(systemName: collapsed ? "chevron.down" : "minus") }.buttonStyle(.plain).help(collapsed ? "展开" : "收起") }.padding(20)
   Divider()
   ScrollView {
    VStack(alignment: .leading, spacing: 20) {
     ProjectChooser(model: model)
     if let project = model.projects.first(where: { $0.id == model.selection }) {
      HStack { StatusPill(text: projectStatus(model.tasks)); Spacer(); Text("\(model.tasks.filter { $0.status == "完成" }.count) / \(model.tasks.count) 项完成").font(.caption).foregroundStyle(.secondary) }
      Text(project.title).font(.system(size: 18, weight: .semibold))
      if !collapsed {
       Text(project.stage.isEmpty ? "阶段未设置" : project.stage)
       if !model.tasks.isEmpty { ProgressView(value: Double(model.tasks.filter { $0.status == "完成" }.count), total: Double(model.tasks.count)).tint(Desk.green) }
       VStack(alignment: .leading, spacing: 8) { Text("下一步").font(.caption).foregroundStyle(.secondary); Text(model.tasks.first { $0.status != "完成" }?.title ?? "暂无待办") }
       ProjectProgress(entries: model.projectProgress[project.id] ?? [])
       Divider()
       Text("项目待办").font(.caption).foregroundStyle(.secondary)
       ForEach(model.tasks.filter { $0.status != "完成" }) { task in
        HStack(alignment: .top, spacing: 12) {
         Button { model.update(task, status: "完成") } label: { Image(systemName: "square").foregroundStyle(.secondary) }.buttonStyle(.plain).help("标记完成：\(task.title)")
         Text(task.title).frame(maxWidth: .infinity, alignment: .leading)
        }; Divider()
       }
      }
     } else { Text("还没有项目").font(.headline); Text("在管理窗口创建项目后，这里会显示当前重点。").foregroundStyle(.secondary) }
    }.padding(22)
   }
   if !collapsed {
    AgentStatus(model: model).padding(20)
   }
  }.background(.white).foregroundStyle(Desk.ink).preferredColorScheme(.light)
   .alert("操作失败", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("确定") { model.error = nil } } message: { Text(model.error ?? "") }
 }

}

struct ProjectProgress: View {
 let entries: [AuditEntry]
 var body: some View {
  VStack(alignment: .leading, spacing: 8) {
   Text("最近进展").font(.headline)
   if let latest = entries.first {
    ProgressEntry(entry: latest)
    if entries.count > 1 {
     DisclosureGroup("更早进展（\(entries.count - 1) 条）") {
      ScrollView { VStack(alignment: .leading, spacing: 12) { ForEach(Array(entries.dropFirst())) { ProgressEntry(entry: $0) } } }.frame(maxHeight: 180)
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
   Text(entry.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
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
