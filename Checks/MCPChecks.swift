import Foundation
import WorkdeskCore

func runMCPChecks() async throws {
 let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()).appendingPathComponent("workdesk-mcp-check-\(UUID())")
 defer { try? FileManager.default.removeItem(at: root) }
 let store = try Store(root: root)
 let project = try await store.createProject("MCP 可见")
 let hidden = try await store.createProject("MCP 不可见")
 let key = root.appendingPathComponent("credentials/fixture.key")
 _ = try await store.registerSource("fixture", project: project.id, alias: "demo", tokenFile: key)
 try await store.bind(source: "fixture", alias: "hidden", project: hidden.id)
 let server = try MCPServer(root: root, source: "fixture", credential: key)
 func request(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
  let response = await server.respond(try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]))
  guard let response, let object = try JSONSerialization.jsonObject(with: response) as? [String: Any] else { throw StoreError.missing }
  let secret = try String(contentsOf: key).trimmingCharacters(in: .whitespacesAndNewlines)
  try require(!String(decoding: response, as: UTF8.self).contains(secret), "MCP leaked private key")
  return object
 }
 func call(_ tool: String, alias: String = "demo", text: String = "MCP 动态", id: String = "stable") async throws -> [String: Any] {
  try await request("tools/call", ["name": tool, "arguments": tool == "workdesk_projects" ? [:] : ["alias": alias, "text": text, "event_id": id]])
 }
 func inner(_ response: [String: Any]) throws -> Any {
  guard let result = response["result"] as? [String: Any], let content = result["content"] as? [[String: Any]], let text = content.first?["text"] as? String else { throw StoreError.missing }
  return try JSONSerialization.jsonObject(with: Data(text.utf8))
 }
 func outcome(_ response: [String: Any]) throws -> String { (try inner(response) as? [String: Any])?["outcome"] as? String ?? "" }
 try require(try await request("tools/list")["error"] != nil, "tools allowed before initialization")
 let handshake = try await request("initialize", ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "checks", "version": "1"]])
 try require((handshake["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-11-25", "MCP handshake failed")
 let notification = await server.respond(Data("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}".utf8))
 try require(notification == nil, "notification generated response")
 let tools = try await request("tools/list")["result"] as? [String: Any]
 try require((tools?["tools"] as? [Any])?.count == 4, "unexpected tool surface")
 try require(try await (inner(call("workdesk_projects")) as? [Any])?.count == 0, "binding alone authorized MCP")
 try await store.setMCPPermission(source: "fixture", alias: "demo", enabled: true)
 let visible = try await inner(call("workdesk_projects")) as? [[String: Any]]
 try require(visible?.count == 1 && visible?.first?["title"] as? String == project.title, "project scope leaked")
 let accepted = try await call("workdesk_progress")
 try require(try outcome(accepted) == "accepted", "progress not accepted")
 try require(try await outcome(call("workdesk_progress")) == "accepted", "duplicate not idempotent")
 try require(try await store.projectProgress(project.id).count == 1, "duplicate stored twice")
 let reopened = try Store(root: root)
 try require(try await reopened.projectProgress(project.id).first?.text == "MCP 动态", "normal UI query did not read MCP progress")
 try require(try await outcome(call("workdesk_progress", text: "different")) == "conflict", "event ID payload collision not rejected")
 try require(try await outcome(call("workdesk_progress", alias: "hidden", id: "cross")) == "rejected", "unauthorized project accepted")
 try require(try await outcome(call("workdesk_task_create", id: "task")) == "rejected", "task creation not separately gated")
 try await store.setMCPPermission(source: "fixture", alias: "demo", enabled: true, createTasks: true)
 try require(try await outcome(call("workdesk_task_create", text: "待办样例", id: "task")) == "accepted", "authorized task creation failed")
 _ = try await call("workdesk_task_create", text: "待办样例", id: "task")
 let tasks = try await store.tasks(project.id)
 try require(tasks.count == 1 && tasks[0].status == "待办", "task duplicate or completion")
 try await store.setMCPPermission(source: "fixture", alias: "demo", enabled: true, createTasks: false)
 try require(try await outcome(call("workdesk_task_create", text: "待办样例", id: "task")) == "rejected", "revoked task replay accepted")
 try await store.setMCPPermission(source: "fixture", alias: "demo", enabled: false)
 try require(try await outcome(call("workdesk_progress")) == "rejected", "revoked project replay accepted")
 try await store.setMCPPermission(source: "fixture", alias: "demo", enabled: true)
 try await store.unbind(source: "fixture", alias: "demo")
 try await store.bind(source: "fixture", alias: "demo", project: project.id)
 try require(try await store.mcpPermission(source: "fixture", alias: "demo") == nil, "rebind resurrected MCP grant")
 for (name, args) in [("workdesk_progress", ["alias": "demo", "text": "", "event_id": "empty"]), ("workdesk_progress", ["alias": "demo", "text": "x", "event_id": "x", "token": "forbidden"]), ("workdesk_complete", [:])] {
  try require(try await request("tools/call", ["name": name, "arguments": args])["error"] != nil, "invalid MCP input accepted")
 }
 try require(await server.respond(Data("broken".utf8)) != nil, "parse error missing")
 // Transport marker is signed; it cannot be stripped to bypass the stricter permission gate.
 var event = ProgressEvent(sourceID: "fixture", projectID: "demo", type: "task.create", text: "bypass")
 event.transport = "mcp"
 try EventSigning.sign(&event, privateKey: String(contentsOf: key).trimmingCharacters(in: .whitespacesAndNewlines))
 event.transport = nil
 try require(try await store.receive(event).outcome == "rejected", "transport marker not authenticated")
 // Fixture-only configuration lifecycle, preserving other client settings and refusing concurrent edits.
 let fixtureHome = root.appendingPathComponent("home")
 let executable = CommandLine.arguments[0].contains("release") ? ".build/release/WorkdeskCLI" : ".build/debug/WorkdeskCLI"
 let cli = URL(fileURLWithPath: executable, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).path
 for client in [AgentClient.opencode] {
  let plan = ConnectionPlan(client: client, cli: cli, root: root, source: "fixture", credential: key, home: fixtureHome, environment: [:])
  let path = client.config(home: fixtureHome, environment: [:])!
  try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
  let original = Data("{\"existing\":\"keep\"}".utf8)
  try original.write(to: path)
  try plan.apply()
  try require(plan.configured(), "configuration readback failed")
  let installed = try Data(contentsOf: path)
  try require(String(decoding: installed, as: UTF8.self).contains("keep"), "configuration lost other values")
  try (installed + Data([32])).write(to: path)
  do { try plan.undo(); throw StoreError.missing } catch StoreError.database { }
  try require(try Data(contentsOf: path) == installed + Data([32]), "undo overwrote user edit")
  try installed.write(to: path)
  try plan.undo()
  try require(try Data(contentsOf: path) == original, "undo failed to restore original")
 }
 try await store.setMCPPermission(source: "fixture", alias: "demo", enabled: true)
 try await runMCPCreationChecks(cli: cli)
 let probe = ConnectionPlan(client: .generic, cli: cli, root: root, source: "fixture", credential: key)
 try require(try probe.probe(alias: "demo").outcome == "accepted", "real stdio subprocess probe failed")
 print("PASS: MCP handshake, scoped projects, signed accepted progress/UI query, task permissions, deduplication, revocation, invalid input, private-key non-disclosure, isolated configuration backup/undo, real stdio subprocess")
}
