import SwiftUI
import WorkdeskCore

@MainActor final class MeetingEditor: ObservableObject {
 @Published var text = ""
 @Published var date = Date()
 @Published var current: Meeting?
 @Published var reviews: [MeetingReview] = []
 @Published var saved: [Meeting] = []
 @Published var sources: [String] = []
 @Published var source = ""
 @Published var busy = false
 @Published var analyzing = false
 @Published var message = "原文与审核草稿仅保存在本机"
 private var operation: Task<Void, Never>?
 private var saving: Task<Void, Never>?
 private var saveWork: Task<Void, Error>?
 private var projectID: String?
 let model: Model
 init(model: Model) { self.model = model }
 var selected: [MeetingReview] { reviews.filter { $0.selected && !$0.accepted } }
 var canConfirm: Bool {
  !selected.isEmpty && !busy && selected.allSatisfy { review in
   model.projects.contains { $0.id == review.proposal.projectID } && !review.proposal.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
 }
 func refresh() async {
  do {
   guard let store = model.store else { return }
   saved = try await store.allMeetings()
   sources = try await store.meetingAgentSources(credentials: model.connectionCredentials)
   if !sources.contains(source) { source = sources.first ?? "" }
  } catch { message = error.localizedDescription }
 }
 func changed() {
  saving?.cancel()
  saving = Task {
   do {
    try await Task.sleep(nanoseconds: 500_000_000)
    try await persist()
   } catch is CancellationError {} catch { message = error.localizedDescription }
  }
 }
 func persist() async throws {
  let previous = saveWork
  let work = Task {
   if let previous { try? await previous.value }
   try await self.persistNow()
  }
  saveWork = work
  try await work.value
 }
 private func persistNow() async throws {
  guard let store = model.store else { throw StoreError.missing }
  if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, current?.text != text {
   guard let project = projectID ?? model.selection ?? model.projects.first?.id else { throw StoreError.database("请先通过连接中心接入已有项目") }
   let snapshot = text
   current = try await store.saveMeetingSource(project: project, text: snapshot, originalDate: MeetingAnalysis.day(date), id: current?.id, expected: current?.version)
   projectID = project
  }
  for review in reviews {
   let stored = try await store.saveMeetingReview(review)
   if let index = reviews.firstIndex(where: { $0.id == review.id }),
      reviews[index].proposal.text == review.proposal.text,
      reviews[index].proposal.projectID == review.proposal.projectID,
      reviews[index].proposal.type == review.proposal.type,
      reviews[index].selected == review.selected { reviews[index] = stored }
  }
  saved = try await store.allMeetings()
  message = "原文与审核草稿已保存 · 仅 accepted 回执表示已入库"
 }
 func open(_ meeting: Meeting?) {
  saving?.cancel()
  operation = Task {
   busy = true; defer { busy = false }
   do {
    try await persist()
    current = meeting; text = meeting?.text ?? ""; reviews = []
    projectID = try await meeting.mapAsyncProject(model.store)
    if let meeting, let store = model.store {
     reviews = try await store.meetingReviews(meeting.id)
     if let original = MeetingAnalysis.date(meeting.originalDate) { date = original }
    } else { date = Date() }
   } catch { message = error.localizedDescription }
  }
 }
 func analyze() {
  saving?.cancel()
  operation = Task {
   busy = true; analyzing = true
   defer { busy = false; analyzing = false }
   do {
    try await persist()
    guard let store = model.store, let current, let root = model.connectionRoot, !source.isEmpty else { throw StoreError.database("没有可验证的已登记智能体身份，请检查连接中心") }
    let agentSource = source
    let context = try await store.meetingContext().map { $0 as [String: Any] }
    let prompt = try MeetingAnalysis.prompt(source: current.text, originalDate: current.originalDate, projects: context)
    message = "Hermes 正在识别 · 最长 120 秒 · 可取消"
    let data = try await HermesMeetingAgent.analyze(prompt: prompt, directory: root)
    try Task.checkCancellation()
    reviews = try await store.storeMeetingAnalysis(data, meeting: current, source: agentSource)
    message = "识别完成，请核对文字、项目与证据后确认"
   } catch { message = error.localizedDescription }
  }
 }
 func cancel() { operation?.cancel(); message = "正在取消 Hermes 识别…" }
 func confirm() {
  saving?.cancel()
  operation = Task {
   busy = true; defer { busy = false }
   do {
    try await persist()
    guard let current, let store = model.store, let root = model.connectionRoot, let inbox = model.connectionInbox else { throw StoreError.missing }
    let ids = selected.map(\.id)
    reviews = try await MeetingConfirmation.submit(ids: ids, meeting: current.id, store: store, credentials: model.connectionCredentials, root: root, inbox: inbox)
    let accepted = reviews.filter { ids.contains($0.id) && $0.accepted }.count
    message = "已写入 \(accepted) / \(ids.count) 条；未成功项保留，可按原事件重试"
    await model.reload()
   } catch { message = error.localizedDescription }
  }
 }
 func leave() {
  if analyzing { cancel() }
  saving?.cancel()
  model.perform { try await self.persist() }
 }
 /// Deletes a saved meeting (原文、草稿与识别记录)；已确认入库的项目任务不受影响。
 func delete(_ meeting: Meeting) {
  if analyzing { cancel() }
  saving?.cancel()
  operation = Task {
   busy = true; defer { busy = false }
   do {
    guard let store = model.store else { throw StoreError.missing }
    try await store.deleteMeeting(meeting.id)
    if current?.id == meeting.id { current = nil; text = ""; reviews = []; projectID = nil }
    saved = try await store.allMeetings()
    message = "已删除该会议原文与草稿；已入库的项目事项不受影响"
   } catch { message = error.localizedDescription }
  }
 }
}

private extension Optional where Wrapped == Meeting {
 func mapAsyncProject(_ store: Store?) async throws -> String? {
  guard let self, let store else { return nil }
  return try await store.meetingProject(self.id)
 }
}

struct MeetingsView: View {
 @ObservedObject var model: Model
 @StateObject var editor: MeetingEditor
 @State private var disclosure = false
 @State private var pendingDelete: Meeting?
 init(model: Model) {
  self.model = model; _editor = StateObject(wrappedValue: MeetingEditor(model: model))
 }
 init(model: Model, editor: MeetingEditor) {
  self.model = model; _editor = StateObject(wrappedValue: editor)
 }
 var body: some View {
  VStack(alignment: .leading, spacing: 16) {
   Text("会议收件箱").font(.system(size: 16, weight: .semibold))
   Text("粘贴录音转文字，让智能体提取事项并匹配已有项目").font(.system(size: 13.5)).foregroundStyle(.secondary)
   HStack(spacing: 10) {
    Menu("打开已存会议") {
     ForEach(editor.saved) { meeting in
      Menu((meeting.originalDate.isEmpty ? "日期未知" : meeting.originalDate) + " · " + String(meeting.text.prefix(28)).replacingOccurrences(of: "\n", with: " ")) {
       Button("打开") { editor.open(meeting) }
       Button("删除…", role: .destructive) { pendingDelete = meeting }
      }
     }
     if editor.saved.isEmpty { Button("暂无已存会议") {}.disabled(true) }
    }.menuStyle(.borderlessButton).fixedSize().padding(10).background(Desk.wash, in: RoundedRectangle(cornerRadius: 6))
    Button("新会议") { editor.open(nil) }.buttonStyle(DeskButton())
    Spacer(minLength: 0)
    Text("智能体：Hermes").font(.system(size: 13.5)).foregroundStyle(Desk.green)
    Button(editor.reviews.isEmpty ? "交给智能体识别" : "重新识别") { disclosure = true }.buttonStyle(DeskButton(primary: true))
     .disabled(editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editor.source.isEmpty)
   }.disabled(editor.busy)
   Divider()
   GeometryReader { geometry in
    let available = max(0, geometry.size.width - 33)
    HStack(alignment: .top, spacing: 16) {
     sourcePanel.frame(width: available * 0.45)
     Divider()
     reviewPanel.frame(width: available * 0.55)
    }
   }
   Divider()
   HStack(spacing: 12) {
    Text(editor.message).font(.system(size: 10.5)).foregroundStyle(.secondary).textSelection(.enabled)
    Spacer(minLength: 6)
    if editor.analyzing {
     ProgressView().controlSize(.small)
     Button("取消识别") { editor.cancel() }.buttonStyle(DeskButton())
    } else {
     Button("保存草稿") { model.perform { try await editor.persist() } }.buttonStyle(DeskButton()).disabled(editor.busy)
     Button("确认并写入所选 \(editor.selected.count) 条") { editor.confirm() }.buttonStyle(DeskButton(primary: true)).disabled(!editor.canConfirm)
    }
   }
  }.padding(24).background(.white).foregroundStyle(Desk.ink).tint(Desk.green)
   .task { await editor.refresh() }
   .onDisappear { editor.leave() }
   .alert("授权 Hermes 分析会议", isPresented: $disclosure) {
    Button("取消", role: .cancel) {}
    Button("授权并识别") { editor.analyze() }
   } message: {
    Text("会议全文、当前已有项目和任务名称将发送给 Hermes 已配置的模型。使用本机 hermes-agent 单次进程，关闭全部工具；本机进程参数可能包含会议文字。仅生成本地审核草稿，不会自动创建项目或事项。确认所选条目时，才以现有身份签名提交，并遵守连接中心的项目与创建权限。")
   }
   .confirmationDialog("删除这条已存会议？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
    Button("删除会议原文与草稿", role: .destructive) {
     if let meeting = pendingDelete { editor.delete(meeting) }
     pendingDelete = nil
    }
    Button("取消", role: .cancel) { pendingDelete = nil }
   } message: {
    Text("将删除该会议的原文、待办草稿与识别记录；已确认写入项目的事项不受影响。")
   }
 }
 private var sourcePanel: some View {
  VStack(alignment: .leading, spacing: 10) {
   Text("会议原文").font(.system(size: 14, weight: .semibold))
   Text("无需“待办”标记，保留口语和上下文即可").font(.system(size: 10.5)).foregroundStyle(.secondary)
   if let current = editor.current {
    Text("原始会议日期：" + (current.originalDate.isEmpty ? "未知（不推断相对日期）" : current.originalDate)).font(.system(size: 10.5)).foregroundStyle(.secondary)
   } else {
    DatePicker("会议日期", selection: $editor.date, displayedComponents: .date).font(.system(size: 10.5)).environment(\.locale, Locale(identifier: "zh_CN"))
   }
   TextEditor(text: $editor.text).font(.system(size: 13.5)).scrollContentBackground(.hidden)
    .padding(10).background(Desk.wash, in: RoundedRectangle(cornerRadius: 8))
    .accessibilityLabel("会议原文").disabled(editor.busy).onChange(of: editor.text) { _ in if !editor.busy { editor.changed() } }
   Text("原文可编辑 · 每轮识别保留独立原文与历史证据").font(.system(size: 10.5)).foregroundStyle(.secondary)
  }
 }
 private var reviewPanel: some View {
  VStack(alignment: .leading, spacing: 10) {
   HStack {
    Text("识别结果").font(.system(size: 14, weight: .semibold))
    Spacer()
    Text("\(editor.reviews.filter { $0.proposal.type == "task" }.count) 条事项 · \(editor.reviews.filter { $0.proposal.type == "progress" }.count) 条进度").font(.system(size: 10.5)).foregroundStyle(.secondary)
   }
   Text("确认目标项目和事项内容后，再加入项目").font(.system(size: 10.5)).foregroundStyle(.secondary)
   if editor.sources.count > 1 {
    Picker("提交身份", selection: $editor.source) { ForEach(editor.sources, id: \.self) { Text($0).tag($0) } }.disabled(editor.busy)
   }
   ScrollView {
    LazyVStack(alignment: .leading, spacing: 10) {
     if editor.reviews.isEmpty {
      Text("识别后将在这里列出建议事项与进度。\n每条建议都必须有可核对的原文依据。").font(.system(size: 13.5)).foregroundStyle(.secondary).padding(.vertical, 30)
     }
     ForEach($editor.reviews) { $review in
      MeetingReviewCard(review: $review, projects: model.projects, changed: editor.changed).disabled(editor.busy)
     }
    }
   }
  }
 }
}

struct MeetingReviewCard: View {
 @Binding var review: MeetingReview
 let projects: [Project]
 let changed: () -> Void
 var body: some View {
  VStack(alignment: .leading, spacing: 10) {
   HStack(spacing: 8) {
    Button { review.selected.toggle() } label: {
     Image(systemName: review.selected ? "checkmark.square.fill" : "square")
      .font(.system(size: 14)).foregroundStyle(Desk.green).frame(width: 24, height: 24).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel("选择事项").accessibilityValue(review.selected ? "已选" : "未选").disabled(review.accepted)
    Picker("类型", selection: $review.proposal.type) {
     Text("新增事项").tag("task"); Text("记录进度").tag("progress")
    }.labelsHidden().frame(width: 104).disabled(review.locked)
    Spacer(minLength: 0)
    Picker("目标项目", selection: $review.proposal.projectID) {
     Text("请选择项目").tag("")
     ForEach(projects) { Text($0.title).tag($0.id) }
    }.labelsHidden().frame(maxWidth: 190).disabled(review.locked)
   }
   TextField("事项内容", text: $review.proposal.text, axis: .vertical).textFieldStyle(.plain).font(.system(size: 13.5, weight: .medium)).lineLimit(1...5).disabled(review.locked)
   Text("依据：“\(review.proposal.evidence)”").font(.system(size: 10.5)).foregroundStyle(.secondary).textSelection(.enabled)
   if review.proposal.projectID.isEmpty || !projects.contains(where: { $0.id == review.proposal.projectID }) {
    Text("项目未知或已删除，选择现有项目后才能确认").font(.system(size: 10.5)).foregroundStyle(.orange)
   }
   if review.duplicate { Text("疑似重复 · 默认不选，请核对后再选择").font(.system(size: 10.5)).foregroundStyle(.orange) }
   Text(review.proposal.type == "progress" ? "仅记录进度，不改变正式状态" : "负责人和未明确的截止日期不自动补全").font(.system(size: 10.5)).foregroundStyle(.secondary)
   if let receipt = review.receipt {
    Text(receipt.outcome == "accepted" ? "已写入 · accepted" : "未写入 · \(receipt.detail)").font(.system(size: 10.5)).foregroundStyle(receipt.outcome == "accepted" ? Desk.green : .orange)
   }
   if let failure = review.failure { Text(failure).font(.system(size: 10.5)).foregroundStyle(.orange) }
   DisclosureGroup("历史依据 · \(review.originalDate.isEmpty ? "日期未知" : review.originalDate)") {
    Text("Hermes 原建议：\(review.original.text)\n提交身份：\(review.agentSource)\n\n\(review.sourceText)").font(.system(size: 10.5)).textSelection(.enabled)
   }.font(.system(size: 10.5)).foregroundStyle(.secondary)
  }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
   .background(review.proposal.type == "progress" ? Color.blue.opacity(0.045) : Desk.wash, in: RoundedRectangle(cornerRadius: 8))
   .onChange(of: review.selected) { _ in changed() }
   .onChange(of: review.proposal.text) { _ in changed() }
   .onChange(of: review.proposal.type) { _ in changed() }
   .onChange(of: review.proposal.projectID) { _ in changed() }
 }
}
