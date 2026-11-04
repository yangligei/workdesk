import SwiftUI
import AppKit
import WorkdeskCore

@MainActor final class Model: ObservableObject {
 @Published var projects: [Project] = []
 @Published var tasks: [WorkTask] = []
 @Published var projectTasks: [String: [WorkTask]] = [:]
 @Published var selection: String?
 @Published var error: String?
 @Published var audit: [AuditEntry] = []
 @Published var projectProgress: [String: [AuditEntry]] = [:]
 @Published var bindings: [SourceBinding] = []
 @Published var meetings: [Meeting] = []
 var store: Store?
 private var root: URL?
 private var inbox: EventInbox?
 private var watcher: InboxWatcher?
 init() {
  do {
   let root = ProcessInfo.processInfo.environment["WORKDESK_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Workdesk")
   self.root = root
   let storage = try Store(root: root); store = storage
   inbox = try EventInbox(root: root, store: storage)
   watcher = try InboxWatcher(root: root) { [weak self] in
    guard let model = self else { return }
    Task { @MainActor in model.perform { try await model.inbox?.drain(); await model.reload() } }
   }
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
   var grouped: [String: [WorkTask]] = [:]
   for project in projects { grouped[project.id] = try await store.tasks(project.id) }
   var progress: [String: [AuditEntry]] = [:]
   for project in projects { progress[project.id] = try await store.projectProgress(project.id) }
   projectProgress = progress
   projectTasks = grouped
   tasks = selection.flatMap { grouped[$0] } ?? []
   audit = try await store.audit(); bindings = try await store.bindings()
   meetings = try await selection.mapAsyncMeetings(store)
   if let root { try await store.exportProjects(to: root) }
  } catch { self.error = error.localizedDescription }
 }
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
 func mapAsyncMeetings(_ store: Store) async throws -> [Meeting] {
  guard let id = self else { return [] }; return try await store.meetings(id)
 }
 func asyncTasks(_ store: Store) async throws -> [WorkTask] {
  guard let id = self else { return [] }; return try await store.tasks(id)
 }
}

struct TaskBoard: View {
 @ObservedObject var model: Model
 @State private var confirmDelete = false
 var body: some View {
  VStack(alignment: .leading, spacing: 14) {
   HStack {
    Text("项目待办").font(.system(size: 24, weight: .semibold))
    Spacer()
    Button("刷新") { model.perform { await model.reload() } }
   }
   Picker("项目", selection: $model.selection) {
    Text("请选择").tag(String?.none)
    ForEach(model.projects) { Text($0.title).tag(Optional($0.id)) }
   }.onChange(of: model.selection) { _ in model.perform { await model.reload() } }
   if let project = model.projects.first(where: { $0.id == model.selection }) {
    ProjectEditor(model: model, project: project).id(project.id + String(project.version))
   }
   if let id = model.selection { ProjectProgress(entries: model.projectProgress[id] ?? []) }
   AgentStatus(model: model)
   ScrollView {
    LazyVStack(spacing: 0) {
    ForEach(model.tasks) { task in
    HStack(spacing: 14) {
     TaskTitleEditor(model: model, task: task).id(task.id + String(task.version))
     Picker("状态", selection: Binding(get: { task.status }, set: { model.update(task, status: $0) })) {
      ForEach(["待办", "进行中", "阻塞", "完成"], id: \.self) { Text($0) }
     }.labelsHidden().frame(width: 110)
     Button { model.deleteTask(task) } label: { Image(systemName: "trash") }.help("删除任务")
    }.padding(.vertical, 18)
    Divider()
    }
    }
   }.overlay { if model.tasks.isEmpty { Text("暂无任务").foregroundStyle(.secondary) } }
   HStack {
    Text("共 \(model.tasks.count) 项 · 完成 \(model.tasks.filter { $0.status == "完成" }.count) 项").foregroundStyle(.secondary)
    Spacer()
    Button("删除项目…", role: .destructive) { confirmDelete = true }.disabled(model.selection == nil)
   }
  }.padding(34).frame(minWidth: 440, minHeight: 340)
  .alert("操作失败", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("确定") { model.error = nil } } message: { Text(model.error ?? "") }
  .confirmationDialog("删除项目及其全部任务？", isPresented: $confirmDelete) { Button("删除项目", role: .destructive) { model.deleteProject() } }
 }
}

@MainActor final class FloatingWindow {
 static let shared = FloatingWindow()
 private var panel: NSPanel?
 func hide() { panel?.orderOut(nil) }
 func show(_ model: Model) {
  if panel == nil {
   let window = NSPanel(contentRect: NSRect(x: 160, y: 240, width: 520, height: 720), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
   window.title = "Workdesk · 置顶窗"; window.level = .floating
   window.isReleasedWhenClosed = false
   window.contentMinSize = NSSize(width: 520, height: 420)
   window.contentView = NSHostingView(rootView: FocusPanel(model: model)); panel = window
  }
  panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
 }
}
@MainActor final class StatusBarController: NSObject, NSApplicationDelegate {
 let model = Model()
 private var item: NSStatusItem?
 private var pending: DispatchWorkItem?
 private var management: NSWindow?
 func applicationDidFinishLaunching(_ notification: Notification) {
  let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Workdesk：单击置顶窗，双击菜单")
  item.button?.target = self; item.button?.action = #selector(clicked)
  item.button?.sendAction(on: [.leftMouseUp])
  self.item = item
  FloatingWindow.shared.show(model)
 }
 func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  FloatingWindow.shared.show(model)
  return false
 }
 @objc private func clicked() {
  pending?.cancel(); pending = nil
  if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { showMenu(); return }
  // Wait for the system's double-click interval so a double click never flashes the panel.
  let work = DispatchWorkItem { [weak self] in guard let self else { return }; FloatingWindow.shared.show(self.model) }
  pending = work
  DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
 }
 private func showMenu() {
  guard let button = item?.button else { return }
  let menu = NSMenu()
  let count = NSMenuItem(title: "项目 \(model.projects.count) · 当前任务 \(model.tasks.count)", action: nil, keyEquivalent: "")
  menu.addItem(count)
  for (title, action) in [("打开置顶窗", #selector(showFocus)), ("隐藏置顶窗", #selector(hideFocus)), ("打开管理窗口…", #selector(showManagement)), ("设置与接入…", #selector(showSettings))] {
   let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
  }
  menu.addItem(.separator())
  let quit = NSMenuItem(title: "退出 Workdesk", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
  menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
 }
 @objc private func showFocus() { FloatingWindow.shared.show(model) }
 @objc private func hideFocus() { FloatingWindow.shared.hide() }
 @objc private func showSettings() { UserDefaults.standard.set("设置与接入", forKey: "boardSection"); showManagement() }
 @objc private func showManagement() {
  if management == nil {
   let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 1080, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
   window.title = "Workdesk · 工作进度台"; window.isReleasedWhenClosed = false
   window.contentView = NSHostingView(rootView: Board(model: model)); management = window
  }
  management?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
 }
 @objc private func quitApp() { NSApp.terminate(nil) }
}
@main struct WorkdeskApp: App {
 @NSApplicationDelegateAdaptor(StatusBarController.self) private var delegate
 var body: some Scene { Settings { EmptyView() } }
}
