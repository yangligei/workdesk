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
 @Published var archivedTasks: [ArchivedTask] = []
 @Published var autoArchive = true
 var store: Store?
 var connectionRoot: URL? { root }
 var connectionCredentials: URL {
  if ProcessInfo.processInfo.environment["WORKDESK_DATA_DIR"] != nil, let root { return root.appendingPathComponent("credentials") }
  return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workdesk-credentials")
 }
 var connectionInbox: EventInbox? { inbox }
 private var root: URL?
 private var inbox: EventInbox?
 private var watcher: InboxWatcher?
 private var receiptWatcher: InboxWatcher?
 private var archiveTimer: Timer?
 private var wakeObserver: NSObjectProtocol?
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
   receiptWatcher = try InboxWatcher(root: root, directoryName: "receipts") { [weak self] in
    guard let model = self else { return }
    Task { @MainActor in await model.reload() }
   }
   wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
    guard let model = self else { return }
    Task { @MainActor in await model.reload() }
   }
   perform { await self.reload() }
  } catch { self.error = error.localizedDescription }
 }
 deinit {
  archiveTimer?.invalidate()
  if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
 }
 private func scheduleArchive() {
  archiveTimer?.invalidate(); archiveTimer = nil
  guard autoArchive else { return }
  let active: [WorkTask] = projectTasks.values.flatMap { $0 }
  let deadlines: [Date] = active.filter { $0.status == "完成" }.compactMap { task in
   task.completedAt?.addingTimeInterval(43200)
  }
  guard let deadline = deadlines.min() else { return }
  let timer = Timer(timeInterval: max(0.05, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
   guard let model = self else { return }
   Task { @MainActor in await model.reload() }
  }
  archiveTimer = timer
  RunLoop.main.add(timer, forMode: .common)
 }
 func perform(_ action: @escaping () async throws -> Void) {
  Task { do { try await action() } catch { self.error = error.localizedDescription } }
 }
 func reload() async {
  do {
   guard let store else { return }
   _ = try await store.sweepArchive()
   projects = try await store.projects()
   if !projects.contains(where: { $0.id == selection }) { selection = projects.first?.id }
   var grouped: [String: [WorkTask]] = [:]
   for project in projects { grouped[project.id] = try await store.tasks(project.id) }
   var progress: [String: [AuditEntry]] = [:]
   for project in projects { progress[project.id] = try await store.projectProgress(project.id) }
   projectProgress = progress
   projectTasks = grouped
   archivedTasks = try await store.archivedTasks()
   autoArchive = try await store.autoArchiveEnabled()
   scheduleArchive()
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
 func setAutoArchive(_ enabled: Bool) { perform { try await self.store?.setAutoArchive(enabled); await self.reload() } }
 func restoreTask(_ task: ArchivedTask) { perform {
  try await self.store?.restoreTask(task.id, expected: task.version); await self.reload()
 } }
 func deleteArchivedTask(_ task: ArchivedTask) { perform { try await self.store?.deleteTask(task.id); await self.reload() } }
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
     InlineStatus(value: task.status, label: task.title + "：任务状态") { model.update(task, status: $0) }
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
@MainActor final class ArchiveWindow {
 static let shared = ArchiveWindow()
 private var panel: NSPanel?
 func hide() { panel?.orderOut(nil) }
 func show(_ model: Model) {
  if panel == nil {
   let window = NSPanel(contentRect: NSRect(x: 220, y: 180, width: 540, height: 760), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
   window.title = "Workdesk · 归档"; window.level = .floating
   window.isReleasedWhenClosed = false
   window.contentMinSize = NSSize(width: 480, height: 420)
   window.contentView = NSHostingView(rootView: ArchiveView(model: model)); panel = window
  }
  panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
 }
}
@MainActor final class StatusBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
 private let checkMode: String? = {
  let args = ProcessInfo.processInfo.arguments
  if args.contains("--check-status-cg") { return "cg" }
  if args.contains("--check-status-menu") { return "menu" }
  if args.contains("--check-status-clicks") { return "clicks" }
  return nil
 }()
 private var statusCheck: Bool { checkMode != nil }
 private var checkActions = 0
 private var checkMenus = 0
 private var checkFocus = 0
 private var menuClosedEarly = false
 func menuWillOpen(_ menu: NSMenu) {
  guard let checkMode else { return }
  checkMenus += 1
  guard checkMode == "clicks" else { return }
  // Scenario runs must not block on a modal menu; cancel it shortly after it opens.
  let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(cancelScenarioMenu(_:)), userInfo: menu, repeats: false)
  RunLoop.main.add(timer, forMode: .common)
 }
 @objc private func cancelScenarioMenu(_ timer: Timer) {
  (timer.userInfo as? NSMenu)?.cancelTrackingWithoutAnimation()
 }
 func menuDidClose(_ menu: NSMenu) {
  // In menu mode nothing else cancels it, so a close here means the menu was
  // dismissed by the click that opened it.
  if checkMode == "menu" { menuClosedEarly = true }
 }
 let model = Model()
 private var item: NSStatusItem?
 private var management: NSWindow?
 func applicationDidFinishLaunching(_ notification: Notification) {
  let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Workdesk：单击置顶窗，双指按压打开菜单")
  item.button?.target = self; item.button?.action = #selector(clicked)
  // Handle presses before AppKit's button tracking can consume the matching release.
  item.button?.sendAction(on: [.leftMouseDown])
  self.item = item
  // 双指按压触摸板在状态栏按钮上是右键，但状态栏按钮不把右键转成 action，
  // 所以用本地事件监听识别落在图标上的右键。
  installSecondaryClickMonitor()
  if statusCheck { runStatusCheck() } else if ProcessInfo.processInfo.environment["WORKDESK_MCP_CHECK"] == "1" { checkMCPConnectionUI(model: model) } else { FloatingWindow.shared.show(model) }
 }
 private var secondaryMonitor: Any?
 private func installSecondaryClickMonitor() {
  guard secondaryMonitor == nil else { return }
  secondaryMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
   guard let self, self.isStatusBarPress(event) else { return event }
   self.handleSecondaryPress()
   return nil
  }
 }
 private func isStatusBarPress(_ event: NSEvent) -> Bool {
  guard let button = item?.button, let window = button.window else { return false }
  guard event.window === window else { return false }
  let point = button.convert(event.locationInWindow, from: nil)
  return button.bounds.contains(point)
 }
 /// 双指按压：菜单在松手后再弹出，避免被这次按压的松开事件立刻关闭。
 private func handleSecondaryPress() {
  if statusCheck { checkActions += 1 }
  presentMenuAfterRelease()
 }
 // MARK: status-bar self-checks (only reachable through --check-status-*)

 private func after(_ delay: TimeInterval, _ selector: Selector, _ info: Any? = nil) {
  let timer = Timer(timeInterval: delay, target: self, selector: selector, userInfo: info, repeats: false)
  RunLoop.main.add(timer, forMode: .common)
 }

 /// Send one real press/release pair through the status bar window.
 private func injectPress(secondary: Bool) {
  guard let button = item?.button, let window = button.window else { exit(2) }
  let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
  let stamp = ProcessInfo.processInfo.systemUptime
  let types: [NSEvent.EventType] = secondary ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
  for type in types {
   guard let event = NSEvent.mouseEvent(with: type, location: center, modifierFlags: [], timestamp: stamp, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
   // 右键走应用事件队列，才能经过本地事件监听；左键直接进状态栏窗口。
   if secondary { NSApp.postEvent(event, atStart: false) } else { window.sendEvent(event) }
  }
 }
 @objc private func injectLeftTimer(_ timer: Timer) { injectPress(secondary: false) }
 @objc private func injectRightTimer(_ timer: Timer) { injectPress(secondary: true) }

 // MARK: menu persistence (real menu, no forced cancel)

 private func runMenuPersistenceCheck() {
  after(0.3, #selector(menuCheckFirst))
 }
 @objc private func menuCheckFirst() {
  injectPress(secondary: false)
  after(0.12, #selector(menuCheckSecond))
 }
 @objc private func menuCheckSecond() {
  injectPress(secondary: true)
  // A .common-mode Timer still fires while the menu tracks modally.
  after(0.9, #selector(menuCheckVerify))
 }
 @objc private func menuCheckVerify() {
  let ok = checkMenus == 1 && !menuClosedEarly
  print("\(ok ? "PASS" : "FAIL"): menu stays open after two-finger press — menus=\(checkMenus) closedEarly=\(menuClosedEarly) attachedMenu=\(item?.menu != nil)")
  fflush(stdout)
  exit(ok ? 0 : 1)
 }

 // MARK: HID-level probe (needs Accessibility permission)

 private var cgPoint = CGPoint.zero
 private func runCGClickProbe() {
  after(0.5, #selector(cgBegin))
 }
 @objc private func cgBegin() {
  guard AXIsProcessTrusted() else {
   // No Accessibility permission for this binary: HID injection is silently
   // dropped, so report a skip instead of a false failure.
   print("SKIP: CG two-finger press — Accessibility permission not granted, HID events blocked")
   fflush(stdout)
   exit(3)
  }
  guard let button = item?.button, let window = button.window else { exit(2) }
  let local = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
  let screen = window.convertPoint(toScreen: local)
  let top = NSScreen.screens.first?.frame.maxY ?? 0
  cgPoint = CGPoint(x: screen.x, y: top - screen.y)
  print("trusted=\(AXIsProcessTrusted()) point=\(cgPoint)")
  // 双指按压触摸板等价于右键按下／抬起。
  post(.rightMouseDown, clickState: 1, button: .right)
  after(0.05, #selector(cgRelease))
 }
 @objc private func cgRelease() {
  post(.rightMouseUp, clickState: 1, button: .right)
  after(1.1, #selector(cgVerify))
 }
 private func post(_ type: CGEventType, clickState: Int64, button: CGMouseButton) {
  guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cgPoint, mouseButton: button) else { return }
  event.setIntegerValueField(.mouseEventClickState, value: clickState)
  event.post(tap: .cghidEventTap)
 }
 @objc private func cgVerify() {
  let ok = checkActions == 1 && checkMenus == 1 && !menuClosedEarly
  print("\(ok ? "PASS" : "FAIL"): CG two-finger press — actions=\(checkActions) menus=\(checkMenus) closedEarly=\(menuClosedEarly)")
  fflush(stdout)
  exit(ok ? 0 : 1)
 }

 // MARK: click scenarios

 private struct StatusScenario {
  let name: String
  let presses: [(delay: TimeInterval, secondary: Bool)]
  let menus: Int
  let focus: Int
 }
 private var failures: [String] = []
 private var scenarios: [StatusScenario] = []

 private func runStatusCheck() {
  if checkMode == "menu" { runMenuPersistenceCheck(); return }
  if checkMode == "cg" { runCGClickProbe(); return }
  // Drive the real NSStatusBarWindow with real NSEvents so the button's own
  // cell/tracking path decides how many actions arrive and with which
  // currentEvent.
  scenarios = [
   StatusScenario(name: "左键单击", presses: [(0, false)], menus: 0, focus: 1),
   StatusScenario(name: "双指按压", presses: [(0, true)], menus: 1, focus: 0),
   StatusScenario(name: "左键连点两下", presses: [(0, false), (0.12, false)], menus: 0, focus: 2),
   StatusScenario(name: "左键后双指按压", presses: [(0, false), (0.3, true)], menus: 1, focus: 1),
  ]
  after(0.3, #selector(scenarioStartTimer(_:)), 0)
 }
 @objc private func scenarioStartTimer(_ timer: Timer) { startScenario((timer.userInfo as? Int) ?? 0) }
 private func startScenario(_ index: Int) {
  guard index < scenarios.count else {
   let ok = failures.isEmpty && item?.menu == nil
   print("\(ok ? "PASS" : "FAIL"): status click scenarios \(scenarios.count) — \(ok ? "ok" : failures.joined(separator: "; "))")
   fflush(stdout)
   exit(ok ? 0 : 1)
  }
  let scenario = scenarios[index]
  checkMenus = 0; checkFocus = 0; checkActions = 0
  gate.reset()
  var last: TimeInterval = 0
  for press in scenario.presses {
   last = max(last, press.delay)
   after(0.05 + press.delay, press.secondary ? #selector(injectRightTimer(_:)) : #selector(injectLeftTimer(_:)), nil)
  }
  after(0.05 + last + 1.2, #selector(scenarioSettleTimer(_:)), index)
 }
 @objc private func scenarioSettleTimer(_ timer: Timer) {
  let index = (timer.userInfo as? Int) ?? 0
  let scenario = scenarios[index]
  if checkMenus != scenario.menus { failures.append("\(scenario.name): 菜单 \(checkMenus) 次，期望 \(scenario.menus)") }
  if checkFocus != scenario.focus { failures.append("\(scenario.name): 单击动作 \(checkFocus) 次，期望 \(scenario.focus)") }
  print("  · \(scenario.name): actions=\(checkActions) menus=\(checkMenus) focus=\(checkFocus)")
  startScenario(index + 1)
 }
 func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  FloatingWindow.shared.show(model)
  return false
 }
 @objc private func clicked() {
  if statusCheck { checkActions += 1 }
  // 左键单击立即打开置顶窗；双指按压（右键）走上面的事件监听打开菜单。
  checkFocus += 1
  FloatingWindow.shared.show(model)
 }
 private var releaseWaiter: Timer?
 private var gate = MenuReleaseGate(timeout: 0.35)
 private func presentMenuAfterRelease() {
  releaseWaiter?.invalidate()
  gate.begin(at: ProcessInfo.processInfo.systemUptime)
  let timer = Timer(timeInterval: 0.008, target: self, selector: #selector(releasePoll), userInfo: nil, repeats: true)
  RunLoop.main.add(timer, forMode: .common)
  releaseWaiter = timer
 }
 @objc private func releasePoll() {
  guard gate.shouldPresent(buttonsDown: NSEvent.pressedMouseButtons != 0, at: ProcessInfo.processInfo.systemUptime) else { return }
  releaseWaiter?.invalidate(); releaseWaiter = nil
  showMenu()
 }

 private func populate(_ menu: NSMenu) {
  menu.removeAllItems()
  let count = NSMenuItem(title: "项目 \(model.projects.count) · 当前任务 \(model.tasks.count)", action: nil, keyEquivalent: "")
  menu.addItem(count)
  for (title, action) in [("打开置顶窗", #selector(showFocus)), ("隐藏置顶窗", #selector(hideFocus)), ("打开管理窗口…", #selector(showManagement)), ("设置与接入…", #selector(showSettings))] {
   let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
  }
  menu.addItem(.separator())
  let quit = NSMenuItem(title: "退出 Workdesk", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
 }
 private func showMenu() {
  guard let button = item?.button else { return }
  let menu = NSMenu()
  menu.delegate = self
  populate(menu)
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
 var body: some Scene {
  Settings {
   IntegrationView(model: delegate.model)
    .frame(minWidth: 720, minHeight: 500)
    .foregroundStyle(Desk.ink).tint(Desk.green).preferredColorScheme(.light)
  }
 }
}
