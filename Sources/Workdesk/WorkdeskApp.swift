import SwiftUI
import AppKit
import WorkdeskCore

@MainActor final class Model: ObservableObject {
 @Published var projects: [Project] = []
 @Published var tasks: [WorkTask] = []
 @Published var selection: String?
 @Published var error: String?
 private var store: Store?
 init() {
  do {
   let root = ProcessInfo.processInfo.environment["WORKDESK_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Workdesk")
   store = try Store(root: root)
   perform { await self.reload() }
  } catch { self.error = error.localizedDescription }
 }
 func perform(_ action: @escaping () async throws -> Void) {
  Task { do { try await action() } catch { self.error = error.localizedDescription } }
 }
 func reload() async {
  do {
   guard let store else { return }
   projects = try await store.projects()
   if !projects.contains(where: { $0.id == selection }) { selection = projects.first?.id }
   tasks = try await selection.asyncTasks(store)
  } catch { self.error = error.localizedDescription }
 }
 func addProject(_ title: String) { perform {
  guard let store = self.store else { return }
  let project = try await store.createProject(title); self.selection = project.id; await self.reload()
 } }
 func addTask(_ title: String) { perform {
  guard let store = self.store, let id = self.selection else { return }
  _ = try await store.createTask(id, title: title); await self.reload()
 } }
 func update(_ task: WorkTask, status: String) { perform {
  try await self.store?.updateTask(task.id, title: task.title, status: status, expected: task.version); await self.reload()
 } }
 func deleteTask(_ task: WorkTask) { perform { try await self.store?.deleteTask(task.id); await self.reload() } }
 func deleteProject() { perform {
  guard let id = self.selection else { return }
  try await self.store?.deleteProject(id); await self.reload()
 } }
}
private extension Optional where Wrapped == String {
 func asyncTasks(_ store: Store) async throws -> [WorkTask] {
  guard let id = self else { return [] }; return try await store.tasks(id)
 }
}

struct Board: View {
 @ObservedObject var model: Model
 @State private var projectTitle = ""
 @State private var taskTitle = ""
 @State private var confirmDelete = false
 var body: some View {
  VStack(alignment: .leading, spacing: 14) {
   HStack {
    Text("工作进度台").font(.title2.bold())
    Spacer()
    Button("刷新") { model.perform { await model.reload() } }
   }
   HStack {
    TextField("新项目名称", text: $projectTitle).onSubmit(addProject)
    Button("添加项目", action: addProject).disabled(projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
   }
   Picker("项目", selection: $model.selection) {
    Text("请选择").tag(String?.none)
    ForEach(model.projects) { Text($0.title).tag(Optional($0.id)) }
   }.onChange(of: model.selection) { _ in model.perform { await model.reload() } }
   HStack {
    TextField("下一步要做什么", text: $taskTitle).onSubmit(addTask)
    Button("添加任务", action: addTask).disabled(model.selection == nil || taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
   }
   List(model.tasks) { task in
    HStack {
     Text(task.title).frame(maxWidth: .infinity, alignment: .leading)
     Picker("状态", selection: Binding(get: { task.status }, set: { model.update(task, status: $0) })) {
      ForEach(["待办", "进行中", "阻塞", "完成"], id: \.self) { Text($0) }
     }.labelsHidden().frame(width: 110)
     Button { model.deleteTask(task) } label: { Image(systemName: "trash") }.help("删除任务")
    }
   }.overlay { if model.tasks.isEmpty { Text("暂无任务").foregroundStyle(.secondary) } }
   HStack {
    Text("共 \(model.tasks.count) 项 · 完成 \(model.tasks.filter { $0.status == "完成" }.count) 项").foregroundStyle(.secondary)
    Spacer()
    Button("删除项目…", role: .destructive) { confirmDelete = true }.disabled(model.selection == nil)
   }
  }.padding(18).frame(minWidth: 440, minHeight: 340)
  .alert("操作失败", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("确定") { model.error = nil } } message: { Text(model.error ?? "") }
  .confirmationDialog("删除项目及其全部任务？", isPresented: $confirmDelete) { Button("删除项目", role: .destructive) { model.deleteProject() } }
 }
 private func addProject() { model.addProject(projectTitle); projectTitle = "" }
 private func addTask() { guard model.selection != nil else { return }; model.addTask(taskTitle); taskTitle = "" }
}

@MainActor final class FloatingWindow {
 static let shared = FloatingWindow()
 private var panel: NSPanel?
 func show(_ model: Model) {
  if panel == nil {
   let window = NSPanel(contentRect: NSRect(x: 160, y: 240, width: 480, height: 400), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
   window.title = "Workdesk · 置顶窗"; window.level = .floating
   window.isReleasedWhenClosed = false
   window.contentView = NSHostingView(rootView: Board(model: model)); panel = window
  }
  panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
 }
}
@main struct WorkdeskApp: App {
 @StateObject private var model = Model()
 @Environment(\.openWindow) private var openWindow
 var body: some Scene {
  Window("Workdesk · 工作进度台", id: "main") { Board(model: model) }.defaultSize(width: 640, height: 480)
  MenuBarExtra("工作进度台", systemImage: "checklist") {
   Text("项目 \(model.projects.count) · 当前任务 \(model.tasks.count)")
   Button("打开管理窗口") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
   Button("显示置顶窗") { FloatingWindow.shared.show(model) }
   Divider()
   Button("退出 Workdesk") { NSApp.terminate(nil) }.keyboardShortcut("q")
  }
 }
}
