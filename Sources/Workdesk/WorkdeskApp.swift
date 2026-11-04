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
 private var clicks = StatusClickTracker(interval: NSEvent.doubleClickInterval)
 private var singleTimer: Timer?
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
  item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Workdesk：单击置顶窗，双击菜单")
  item.button?.target = self; item.button?.action = #selector(clicked)
  // Handle presses before AppKit's button tracking can consume the matching release.
  item.button?.sendAction(on: [.leftMouseDown])
  self.item = item
  if statusCheck { runStatusCheck() } else { FloatingWindow.shared.show(model) }
 }
 // MARK: status-bar self-checks (only reachable through --check-status-*)

 private func after(_ delay: TimeInterval, _ selector: Selector, _ info: Any? = nil) {
  let timer = Timer(timeInterval: delay, target: self, selector: selector, userInfo: info, repeats: false)
  RunLoop.main.add(timer, forMode: .common)
 }

 /// Send one real press/release pair through the status bar window.
 private func injectClick(clickCount: Int) {
  guard let button = item?.button, let window = button.window else { exit(2) }
  let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
  let stamp = ProcessInfo.processInfo.systemUptime
  for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
   guard let event = NSEvent.mouseEvent(with: type, location: center, modifierFlags: [], timestamp: stamp, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1) else { continue }
   window.sendEvent(event)
  }
 }
 @objc private func injectClickTimer(_ timer: Timer) { injectClick(clickCount: (timer.userInfo as? Int) ?? 1) }

 // MARK: menu persistence (real menu, no forced cancel)

 private func runMenuPersistenceCheck() {
  after(0.3, #selector(menuCheckFirst))
 }
 @objc private func menuCheckFirst() {
  injectClick(clickCount: 1)
  after(0.12, #selector(menuCheckSecond))
 }
 @objc private func menuCheckSecond() {
  injectClick(clickCount: 1)
  // A .common-mode Timer still fires while the menu tracks modally.
  after(0.9, #selector(menuCheckVerify))
 }
 @objc private func menuCheckVerify() {
  let ok = checkMenus == 1 && !menuClosedEarly
  print("\(ok ? "PASS" : "FAIL"): menu stays open after double click — menus=\(checkMenus) closedEarly=\(menuClosedEarly) attachedMenu=\(item?.menu != nil)")
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
   print("SKIP: CG double click — Accessibility permission not granted, HID events blocked")
   fflush(stdout)
   exit(3)
  }
  guard let button = item?.button, let window = button.window else { exit(2) }
  let local = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
  let screen = window.convertPoint(toScreen: local)
  let top = NSScreen.screens.first?.frame.maxY ?? 0
  cgPoint = CGPoint(x: screen.x, y: top - screen.y)
  print("trusted=\(AXIsProcessTrusted()) point=\(cgPoint)")
  post(.leftMouseDown, clickState: 1)
  after(0.05, #selector(cgRelease1))
 }
 @objc private func cgRelease1() {
  post(.leftMouseUp, clickState: 1)
  after(0.09, #selector(cgSecondDown))
 }
 @objc private func cgSecondDown() {
  post(.leftMouseDown, clickState: 2)
  after(0.05, #selector(cgRelease2))
 }
 @objc private func cgRelease2() {
  post(.leftMouseUp, clickState: 2)
  after(1.1, #selector(cgVerify))
 }
 private func post(_ type: CGEventType, clickState: Int64) {
  guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cgPoint, mouseButton: .left) else { return }
  event.setIntegerValueField(.mouseEventClickState, value: clickState)
  event.post(tap: .cghidEventTap)
 }
 @objc private func cgVerify() {
  let ok = checkActions == 2 && checkMenus == 1 && !menuClosedEarly
  print("\(ok ? "PASS" : "FAIL"): CG double click — actions=\(checkActions) menus=\(checkMenus) closedEarly=\(menuClosedEarly)")
  fflush(stdout)
  exit(ok ? 0 : 1)
 }

 // MARK: click scenarios

 private struct StatusScenario {
  let name: String
  let presses: [(delay: TimeInterval, clickCount: Int)]
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
  // currentEvent. Only the "AppKit paired" scenario fabricates clickCount 2.
  let interval = NSEvent.doubleClickInterval
  scenarios = [
   StatusScenario(name: "首次单击", presses: [(0, 1)], menus: 0, focus: 1),
   StatusScenario(name: "快速双击(clickCount 均为1)", presses: [(0, 1), (0.12, 1)], menus: 1, focus: 0),
   StatusScenario(name: "快速双击(第二次clickCount=2)", presses: [(0, 1), (0.12, 2)], menus: 1, focus: 0),
   StatusScenario(name: "间隔超时两次单击", presses: [(0, 1), (interval + 0.35, 1)], menus: 0, focus: 2),
   StatusScenario(name: "连续三击", presses: [(0, 1), (0.12, 1), (0.24, 1)], menus: 1, focus: 0),
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
  clicks.reset(); cancelSingle(); gate.reset()
  var last: TimeInterval = 0
  for press in scenario.presses {
   last = max(last, press.delay)
   after(0.05 + press.delay, #selector(injectClickTimer(_:)), press.clickCount)
  }
  // Settle past the double-click window so a wrongly-held single click would fire.
  after(0.05 + last + NSEvent.doubleClickInterval + 0.45, #selector(scenarioSettleTimer(_:)), index)
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
  let now = ProcessInfo.processInfo.systemUptime
  switch clicks.press(at: now, clickCount: eventClickCount()) {
  case .double:
   cancelSingle()
   // This action runs on mouse-down. Opening a menu here lets the menu's modal
   // tracking loop consume the release that belongs to this very click, which
   // dismisses the menu instantly. Wait for the physical release first.
   presentMenuAfterRelease()
  case .pendingSingle:
   scheduleSingle()
  case .ignored:
   break
  }
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
 private func scheduleSingle() {
  singleTimer?.invalidate()
  // Target/selector Timer: fires on the main run loop in .common mode, so a
  // held single click still resolves while a menu or window is tracking.
  let timer = Timer(timeInterval: clicks.interval, target: self, selector: #selector(singleTimerFired), userInfo: nil, repeats: false)
  RunLoop.main.add(timer, forMode: .common)
  singleTimer = timer
 }
 @objc private func singleTimerFired() {
  singleTimer = nil
  guard clicks.expire(at: ProcessInfo.processInfo.systemUptime) else { return }
  checkFocus += 1
  FloatingWindow.shared.show(model)
 }
 private func cancelSingle() {
  singleTimer?.invalidate(); singleTimer = nil
  clicks.cancel()
 }
 /// `NSEvent.clickCount` raises for non-mouse events (status-item actions can be
 /// delivered from a Kit-defined system event), so only read it for real presses.
 private func eventClickCount() -> Int {
  guard let event = NSApp.currentEvent else { return 1 }
  switch event.type {
  case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
   return event.clickCount
  default:
   return 1
  }
 }
 private func showMenu() {
  guard let button = item?.button else { return }
  let menu = NSMenu()
  menu.delegate = self
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
 var body: some Scene {
  Settings {
   IntegrationView(model: delegate.model)
    .frame(minWidth: 720, minHeight: 500)
    .foregroundStyle(Desk.ink).tint(Desk.green).preferredColorScheme(.light)
  }
 }
}
