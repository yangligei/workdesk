import SwiftUI
import WorkdeskCore

struct Board: View {
 @ObservedObject var model: Model
 var body: some View {
  TabView {
   TaskBoard(model: model).tabItem { Text("项目任务") }
   MeetingsView(model: model).tabItem { Text("会议草稿") }
   IntegrationView(model: model).tabItem { Text("来源与事件") }
  }.frame(minWidth: 620, minHeight: 480)
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
  }.onAppear { title = project.title; stage = project.stage }
 }
}
struct TaskTitleEditor: View {
 @ObservedObject var model: Model
 let task: WorkTask
 @State private var title = ""
 var body: some View {
  TextField("任务名称（回车保存）", text: $title).onAppear { title = task.title }.onSubmit { model.perform {
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
   Text("QQ：未连接").font(.headline)
   Text("本版本仅提供本地文件协议；未接入 QQ，也不会读取聊天或发送消息。来源名不是身份认证，同一系统用户可伪造。仅绑定可信本机生产者。").foregroundStyle(.secondary)
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
   Text("项目：" + (model.projects.first { $0.id == model.selection }?.title ?? "请先选择项目")).font(.headline)
   Text("粘贴并编辑会议文字。每行使用「待办：」「TODO:」或「- [ ] 」；草稿保留行号及原文中的时间戳，不推断负责人和日期。").font(.caption)
   HStack {
    Menu("打开已保存会议") {
     ForEach(model.meetings) { meeting in Button(String(meeting.text.prefix(40))) { current = meeting; text = meeting.text; loadDrafts(meeting.id) } }
    }
    Button("新会议") { current = nil; text = ""; drafts = [] }
    Button("保存文字并生成草稿") { model.perform {
     guard let project = model.selection, let store = model.store else { return }
     let id = try await store.saveMeeting(project: project, text: text, id: current?.id, expected: current?.version)
     await model.reload(); current = model.meetings.first { $0.id == id }; drafts = try await store.meetingDrafts(id)
    } }.disabled(model.selection == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
   }
   TextEditor(text: $text).font(.body.monospaced()).frame(minHeight: 130)
   List(drafts) { draft in
    DraftRow(model: model, draft: draft) { if let current { loadDrafts(current.id) } }.id(draft.id + draft.taskID)
   }
  }.padding().onChange(of: model.selection) { _ in current = nil; text = ""; drafts = [] }
 }
 private func loadDrafts(_ id: String) { model.perform { drafts = try await model.store?.meetingDrafts(id) ?? [] } }
}
struct DraftRow: View {
 @ObservedObject var model: Model
 let draft: MeetingDraft
 let reload: () -> Void
 @State private var title = ""
 var body: some View {
  VStack(alignment: .leading) {
   HStack {
    TextField("草稿标题", text: $title).disabled(!draft.taskID.isEmpty)
    Button(draft.taskID.isEmpty ? "确认入项目" : "已确认") { model.perform {
     try await model.store?.confirmDraft(draft.id, title: title); await model.reload(); reload()
    } }.disabled(!draft.taskID.isEmpty)
   }
   Text("证据 · 第 \(draft.line) 行：\(draft.evidence)").font(.caption).textSelection(.enabled)
  }.onAppear { title = draft.title }
 }
}
