import SwiftUI
import AppKit
import WorkdeskCore

/// Explicit isolated packaged-app check; never reachable from ordinary UI.
@MainActor func checkMCPConnectionUI(model: Model) {
 Task { @MainActor in
  do {
   guard let override = ProcessInfo.processInfo.environment["WORKDESK_DATA_DIR"], !override.isEmpty,
         ProcessInfo.processInfo.environment["WORKDESK_MCP_CHECK"] == "1", let root = model.connectionRoot, let store = model.store else { throw StoreError.database("MCP UI check requires isolated data override") }
   guard try await store.projects().isEmpty else { throw StoreError.database("MCP UI check requires empty fixture") }
   let project = try await store.createProject("连接中心隔离验收")
   try await store.createLocalIdentity(credentials: model.connectionCredentials)
   try await store.authorizeLocalProject(source: "local-agent", project: project.id, credentials: model.connectionCredentials)
   try await store.setMCPPermission(source: "local-agent", alias: project.id, enabled: true)
   await model.reload()
   let plan = ConnectionPlan(client: .generic, cli: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/WorkdeskCLI").path, root: root, source: "local-agent", credential: model.connectionCredentials.appendingPathComponent("local-agent.key"))
   let receipt = try await Task.detached { try plan.probe(alias: project.id) }.value
   guard receipt.outcome == "accepted" else { throw StoreError.database("MCP probe rejected") }
   // Do not call reload: this assertion exercises receipt filesystem notification -> normal UI model.
   for _ in 0..<100 {
    if model.projectProgress[project.id]?.contains(where: { $0.id == "local-agent:" + receipt.eventID }) == true { break }
    try await Task.sleep(nanoseconds: 50_000_000)
   }
   guard model.projectProgress[project.id]?.contains(where: { $0.id == "local-agent:" + receipt.eventID }) == true else { throw StoreError.database("MCP accepted did not refresh normal UI model") }
   let host = NSHostingView(rootView: AgentSetupView(model: model).frame(width: 760).foregroundStyle(Desk.ink).tint(Desk.green).preferredColorScheme(.light))
   let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 760, height: 1500), styleMask: [.borderless], backing: .buffered, defer: false)
   window.contentView = host
   host.frame = NSRect(x: 0, y: 0, width: 760, height: 1500)
   try await Task.sleep(nanoseconds: 500_000_000)
   host.layoutSubtreeIfNeeded()
   guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw StoreError.database("Native snapshot failed") }
   host.cacheDisplay(in: host.bounds, to: bitmap)
   guard let png = bitmap.representation(using: .png, properties: [:]) else { throw StoreError.database("PNG failed") }
   try png.write(to: root.appendingPathComponent("connection-center.png"))
   print("PASS: packaged MCP stdio accepted -> receipt watcher -> normal Model.projectProgress; native connection-center PNG: " + root.appendingPathComponent("connection-center.png").path)
   fflush(stdout); exit(0)
  } catch { print("FAIL: MCP UI check: " + error.localizedDescription); fflush(stdout); exit(1) }
 }
}
