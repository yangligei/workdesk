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
  .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.perform { await model.reload() } }
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
  VStack(alignment: .leading, spacing: 16) {
   HStack {
    TextField("项目名称", text: $title)
    TextField("当前阶段", text: $stage)
    Button("保存项目") { model.perform {
     try await model.store?.updateProject(project.id, title: title, stage: stage, expected: project.version); await model.reload()
    } }
   }
   ProjectDeadlineEditor(model: model, project: project)
  }.padding(16).background(Desk.wash, in: RoundedRectangle(cornerRadius: 6)).onAppear { title = project.title; stage = project.stage }
 }
}

struct ProjectDeadlineEditor: View {
 @ObservedObject var model: Model
 let project: Project
 @State private var deadline = Date()
 @State private var hasDeadline = false
 @State private var zone = TimeZone.current.identifier
 @State private var hours: Set<Double> = [24]
 @State private var custom = ""
 @State private var month = Date()
 private let presets: [Double] = [1, 6, 24, 48]
 private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: zone) ?? .current; return value }
 var body: some View {
  VStack(alignment: .leading, spacing: 12) {
   HStack {
    Text("项目截止").font(.system(size: 13, weight: .medium))
    Spacer()
    Text(hasDeadline ? "世界时 \(deadline.ISO8601Format())" : "未设置截止时间").font(.caption).foregroundStyle(.secondary)
   }
   CalendarStrip(deadline: hasDeadline ? deadline : nil, month: $month, calendar: calendar) { day in
    let time = calendar.dateComponents([.hour, .minute], from: deadline)
    deadline = calendar.date(bySettingHour: time.hour ?? 18, minute: time.minute ?? 0, second: 0, of: day) ?? day
    hasDeadline = true
   }
   HStack {
    DatePicker("日期与时间", selection: $deadline, displayedComponents: [.date, .hourAndMinute]).labelsHidden().environment(\.timeZone, calendar.timeZone).disabled(!hasDeadline)
    Picker("时区", selection: $zone) {
     ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0) }
    }.labelsHidden().frame(maxWidth: 180)
    Button(hasDeadline ? "关闭截止" : "启用截止") { hasDeadline.toggle() }
   }
   HStack(spacing: 8) {
    Text("提前提醒").font(.system(size: 12)).foregroundStyle(.secondary)
    ForEach(presets, id: \.self) { value in
     Button(label(value)) { toggle(value) }.buttonStyle(.plain).font(.system(size: 12))
      .padding(.horizontal, 8).padding(.vertical, 4)
      .foregroundStyle(hours.contains(value) ? .white : Desk.green)
      .background(hours.contains(value) ? Desk.green : .white, in: RoundedRectangle(cornerRadius: 4))
    }
    TextField("自定义小时", text: $custom).frame(width: 88).onSubmit { addCustom() }
    Button("添加") { addCustom() }.buttonStyle(.plain).foregroundStyle(Desk.green)
   }
   HStack {
    ForEach(hours.sorted().filter { !presets.contains($0) }, id: \.self) { value in
     Button("\(value.formatted()) 小时 ×") { hours.remove(value) }.font(.caption)
    }
   }
   HStack {
    Text("按所选时区编辑；切换时区保留同一时刻。已过提醒不补发；逾期在应用内红字显示。").font(.caption).foregroundStyle(.secondary)
    Spacer()
    Button("清除截止") { hasDeadline = false; save(nil) }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(project.deadline == nil && !hasDeadline)
    Button("保存截止与提醒") { save(hasDeadline ? deadline : nil) }.buttonStyle(DeskButton(primary: true))
   }
   if !hasDeadline && project.deadline != nil { Text("保存后截止时间将被清除，已安排的通知会取消。").font(.caption).foregroundStyle(.orange) }
  }.onAppear {
   if let date = project.deadline { deadline = date; hasDeadline = true; month = date }
   zone = project.timeZone; hours = Set(project.reminderHours)
  }
 }
 private func label(_ value: Double) -> String { value < 24 ? "\(Int(value)) 小时" : "\(Int(value / 24)) 天" }
 private func toggle(_ value: Double) { if hours.contains(value) { hours.remove(value) } else { hours.insert(value) } }
 private func addCustom() { guard let value = Double(custom.trimmingCharacters(in: .whitespaces)), value.isFinite, value > 0, value <= 87600, hours.contains(value) || hours.count < 16 else { model.error = "提醒最多 16 个；小时数须大于 0 且不超过 87600"; return }; hours.insert(value); custom = "" }
 private func save(_ date: Date?) { model.perform {
  guard let store = model.store else { return }
  try await store.setDeadline(project.id, date: date, timeZone: zone, hours: Array(hours), expected: project.version)
  await model.reload()
 } }
}

struct CalendarStrip: View {
 let deadline: Date?
 @Binding var month: Date
 let calendar: Calendar
 let select: (Date) -> Void
 private var monthLabel: String { let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy年M月"; return formatter.string(from: month) }
 private var days: [Date?] {
  guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
  let first = interval.start
  let leading = calendar.component(.weekday, from: first) - 1
  let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
  return Array(repeating: nil, count: leading) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
 }
 var body: some View {
  VStack(spacing: 6) {
   HStack {
    Button { month = calendar.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
    Spacer(); Text(monthLabel).font(.system(size: 13, weight: .medium)); Spacer()
    Button { month = calendar.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
   }
   LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
    ForEach(["日","一","二","三","四","五","六"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
     if let day {
      let selected = deadline.map { calendar.isDate($0, inSameDayAs: day) } ?? false
      Button { select(day) } label: {
       VStack(spacing: 2) { Text("\(calendar.component(.day, from: day))"); Circle().fill(selected ? Color.white : Desk.green).frame(width: 3, height: 3).opacity(selected ? 1 : 0) }
        .font(.caption).frame(maxWidth: .infinity, minHeight: 28)
        .foregroundStyle(selected ? .white : Desk.ink)
        .background(selected ? Desk.green : (deadline.map { calendar.isDate($0, inSameDayAs: day) } == true ? Desk.selected : .clear), in: RoundedRectangle(cornerRadius: 4))
      }.buttonStyle(.plain).help(deadline.map { calendar.isDate($0, inSameDayAs: day) ? "当前截止日" : "" } ?? "")
     } else { Color.clear.frame(height: 28) }
    }
   }
  }.padding(8).background(.white, in: RoundedRectangle(cornerRadius: 5))
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
   NotificationSettings(notifications: model.notifications)
   Divider().padding(.vertical, 12)
   Text("本机智能体 · 签名文件协议").font(.headline)
   Text("不读取聊天、不发送消息，未自动连接 QQ 或 Hermes。登记来源后，通用 CLI 可接收任何进程显式上报；凭据只保存在权限 600 的文件中。相同 macOS 用户仍可访问应用数据，这不是系统用户隔离。").foregroundStyle(.secondary)
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
     HStack { Text("待办草稿").font(.system(size: 18, weight: .semibold)); Spacer(); Text("确认后入库").font(.caption).foregroundStyle(.secondary) }
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
    TextField("草稿标题", text: $title).textFieldStyle(.plain).font(.headline).disabled(!draft.taskID.isEmpty)
    Button(draft.taskID.isEmpty ? "确认入项目" : "已确认") { model.perform {
     try await model.store?.confirmDraft(draft.id, title: title); await model.reload(); reload()
    } }.buttonStyle(DeskButton(primary: draft.taskID.isEmpty)).disabled(!draft.taskID.isEmpty)
   }
   Text("证据 · 第 \(draft.line) 行：\(draft.evidence)").font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Desk.wash, in: RoundedRectangle(cornerRadius: 6))
  }.onAppear { title = draft.title }
 }
}
