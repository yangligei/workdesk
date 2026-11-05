import SwiftUI
import WorkdeskCore

struct Board: View {
 @ObservedObject var model: Model
 @AppStorage("boardSection") private var section = "项目总览"
 var body: some View {
  HStack(spacing: 0) {
   VStack(alignment: .leading, spacing: 8) {
    Text("工作进度台").font(.system(size: 15, weight: .semibold)).padding(.horizontal, 12).padding(.top, 32).padding(.bottom, 24)
    ForEach(["项目总览", "项目待办", "会议收件箱", "智能体动态"], id: \.self) { item in
     Button { section = item } label: { Text(item).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 12).foregroundStyle(section == item ? Desk.green : .secondary).background(section == item ? Desk.selected : .clear, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
    }
    Spacer()
    Text("○ QQ 收发待验证").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
    Button("设置与接入") { section = "设置与接入" }.buttonStyle(.plain).foregroundStyle(.secondary).padding(12)
    Button("显示置顶窗") { FloatingWindow.shared.show(model) }.buttonStyle(DeskButton()).padding(.bottom, 20)
   }.padding(.horizontal, 18).frame(width: 195).background(Desk.sidebar)
   Divider()
   Group {
    switch section {
    case "项目总览": ProjectOverview(model: model) { section = "项目待办" }
    case "项目待办": TaskBoard(model: model)
    case "会议收件箱": MeetingsView(model: model)
    default: IntegrationView(model: model)
    }
   }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }.frame(minWidth: 900, minHeight: 580).background(.white).foregroundStyle(Desk.ink).tint(Desk.green).preferredColorScheme(.light)
  .onChange(of: model.selection) { _ in model.perform { await model.reload() } }
  .alert("操作失败", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("确定") { model.error = nil } } message: { Text(model.error ?? "") }
 }
}
struct ProjectEditor: View {
 @ObservedObject var model: Model
 let project: Project
 @State private var title = ""
 @State private var stage = ""
 var body: some View {
  HStack {
   TextField("项目名称", text: $title)
   TextField("当前阶段", text: $stage)
   Button("保存项目") { model.perform {
    try await model.store?.updateProject(project.id, title: title, stage: stage, expected: project.version); await model.reload()
   } }
  }.padding(16).background(Desk.wash, in: RoundedRectangle(cornerRadius: 6)).onAppear { title = project.title; stage = project.stage }
 }
}
struct TaskTitleEditor: View {
 @ObservedObject var model: Model
 let task: WorkTask
 @State private var title = ""
 var body: some View {
  TextField("任务名称（回车保存）", text: $title).textFieldStyle(.plain).font(.system(size: 15)).onAppear { title = task.title }.onSubmit { model.perform {
   try await model.store?.updateTask(task.id, title: title, status: task.status, expected: task.version); await model.reload()
  } }
 }
}
struct IntegrationView: View {
 @ObservedObject var model: Model
 @State private var source = ""
 @State private var alias = ""
 var body: some View {
  ScrollView {
  VStack(alignment: .leading, spacing: 12) {
   AgentSetupView(model: model)
   DisclosureGroup("高级 · 命令与手动映射") {
   Text("本机智能体 · 签名文件协议").font(.headline)
   Text("不读取聊天、不发送消息，未自动连接 QQ 或 Hermes。登记来源后，通用 CLI 可接收任何进程显式上报；凭据只保存在权限 600 的文件中。相同 macOS 用户仍可访问应用数据，这不是系统用户隔离。").foregroundStyle(.secondary)
   Text("首次接入：使用 WorkdeskCLI enroll --name NAME --token-file PATH 登记；仅本机 CLI grant-create --name NAME --allow yes 可授予创建项目权限。未授予时默认拒绝。详见 docs/event-protocol.md。").font(.caption).textSelection(.enabled)
   ProjectChooser(model: model)
   if let project = model.selection {
    ConnectionCommands(project: project)
   }
   Text("绑定到项目：" + (model.projects.first { $0.id == model.selection }?.title ?? "请先选择项目"))
   HStack {
    TextField("来源 ID", text: $source); TextField("生产者项目别名", text: $alias)
    Button("授权映射") { model.perform {
     guard let project = model.selection else { return }
     try await model.store?.bind(source: source, alias: alias, project: project); await model.reload()
    } }.disabled(model.selection == nil || source.isEmpty || alias.isEmpty)
   }
   }
   ForEach(model.bindings) { binding in
    HStack {
     Text("\(binding.source) / \(binding.alias) → \(model.projects.first { $0.id == binding.project }?.title ?? binding.project)")
     Spacer()
     Button("撤销") { model.perform { try await model.store?.unbind(source: binding.source, alias: binding.alias); await model.reload() } }
    }
   }
   Text("事件审计 · 最近 200 条（accepted 已接受 / conflict 冲突 / rejected 拒绝）").font(.headline)
   List(model.audit) { entry in
    VStack(alignment: .leading) {
     Text("\(entry.source) · \(entry.type) · \(entry.outcome)").bold()
     Text(entry.text)
     Text("来源时间 \(entry.occurred) · 接收 \(entry.received)").font(.caption).foregroundStyle(.secondary)
    }.textSelection(.enabled)
   }.frame(height: 240)
  }.padding()
  }
 }
}
