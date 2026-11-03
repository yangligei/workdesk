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
    Text("○ QQ 未连接").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
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
  VStack(alignment: .leading) {
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
   }
  }.padding()
 }
}
struct MeetingsView: View {
 @ObservedObject var model: Model
 @State private var text = ""
 @State private var current: Meeting?
 @State private var drafts: [MeetingDraft] = []
 var body: some View {
  VStack(alignment: .leading) {
   Text("会议收件箱").font(.system(size: 24, weight: .semibold))
   ProjectChooser(model: model).padding(.vertical, 10)
   Text("粘贴并编辑会议文字。每行使用「待办：」「TODO:」或「- [ ] 」；草稿保留行号及原文中的时间戳，不推断负责人和日期。").font(.caption)
   HStack(spacing: 10) {
    Menu {
     ForEach(model.meetings) { meeting in Button(String(meeting.text.prefix(40))) { current = meeting; text = meeting.text; loadDrafts(meeting.id) } }
    } label: { Text("打开已保存会议") }.menuStyle(.button).buttonStyle(DeskButton())
    Button("新会议") { current = nil; text = ""; drafts = [] }.buttonStyle(DeskButton())
    Button("保存文字并生成草稿") { model.perform {
     guard let project = model.selection, let store = model.store else { return }
     let id = try await store.saveMeeting(project: project, text: text, id: current?.id, expected: current?.version)
     await model.reload(); current = model.meetings.first { $0.id == id }; drafts = try await store.meetingDrafts(id)
    } }.buttonStyle(DeskButton(primary: true)).disabled(model.selection == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    Spacer()
   }
   Divider().padding(.vertical, 12)
   GeometryReader { geo in
   HStack(alignment: .top, spacing: 28) {
    VStack(alignment: .leading, spacing: 16) {
     Text("会议原文").font(.system(size: 18, weight: .semibold))
     Text("保留讨论上下文与原文依据").font(.caption).foregroundStyle(.secondary)
     TextEditor(text: $text).font(.system(size: 14)).scrollContentBackground(.hidden).padding(14).background(Desk.wash, in: RoundedRectangle(cornerRadius: 6)).frame(minHeight: 230)
    }.frame(width: max(300, (geo.size.width - 28) * 0.55), alignment: .leading)
    Divider()
    VStack(alignment: .leading, spacing: 18) {
     HStack { Text("待办草稿").font(.system(size: 18, weight: .semibold)); Spacer(); Text("由智能体入库").font(.caption).foregroundStyle(.secondary) }
     ScrollView {
      VStack(alignment: .leading, spacing: 20) {
       if drafts.isEmpty { Text("保存会议文字后，这里会列出带有明确待办标记的草稿。").foregroundStyle(.secondary).padding(.vertical, 20) }
       ForEach(drafts) { draft in
        DraftRow(model: model, draft: draft) { if let current { loadDrafts(current.id) } }.id(draft.id + draft.taskID)
        Divider()
       }
      }
     }
     Text("未确认内容不会覆盖现有任务。").font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
   }
   }
  }.padding(34).onChange(of: model.selection) { _ in current = nil; text = ""; drafts = [] }
 }
 private func loadDrafts(_ id: String) { model.perform { drafts = try await model.store?.meetingDrafts(id) ?? [] } }
}
struct DraftRow: View {
 @ObservedObject var model: Model
 let draft: MeetingDraft
 let reload: () -> Void
 @State private var title = ""
 var body: some View {
  VStack(alignment: .leading, spacing: 14) {
   HStack {
    Text(draft.title).font(.headline)
    Text(draft.taskID.isEmpty ? "请由授权智能体发送 draft.confirm：" + draft.id : "已入项目").font(.caption).textSelection(.enabled)
   }
   Text("证据 · 第 \(draft.line) 行：\(draft.evidence)").font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Desk.wash, in: RoundedRectangle(cornerRadius: 6))
  }.onAppear { title = draft.title }
 }
}
