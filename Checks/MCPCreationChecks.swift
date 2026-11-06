import Foundation
import WorkdeskCore

func runMCPCreationChecks(cli: String) async throws {
 let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()).appendingPathComponent("workdesk-create-check-\(UUID())")
 defer { try? FileManager.default.removeItem(at: root) }
 let store = try Store(root: root)
 let credentials = root.appendingPathComponent("credentials")
 let source = try await store.createAvailableLocalIdentity(credentials: credentials)
 let key = credentials.appendingPathComponent(source + ".key")
 let originalKey = try Data(contentsOf: key)
 // Real newline-framed stdio, no server.respond shortcut. Output goes to fixture files to avoid pipe deadlocks.
 func rpc(_ calls: [(String, [String: String])]) throws -> [[String: Any]] {
  let output = root.appendingPathComponent(UUID().uuidString + ".stdout")
  FileManager.default.createFile(atPath: output.path, contents: nil)
  let out = try FileHandle(forWritingTo: output), input = Pipe()
  defer { try? out.close() }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: cli)
  process.arguments = ["mcp", "--source", source, "--token-file", key.path]
  var environment = ProcessInfo.processInfo.environment
  environment["WORKDESK_DATA_DIR"] = root.path
  process.environment = environment
  process.standardInput = input; process.standardOutput = out; process.standardError = FileHandle.nullDevice
  try process.run()
  var frames: [[String: Any]] = [
   ["jsonrpc": "2.0", "id": 0, "method": "initialize", "params": ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "creation-fixture", "version": "1"]]],
   ["jsonrpc": "2.0", "method": "notifications/initialized"],
   ["jsonrpc": "2.0", "id": 1, "method": "tools/list"]
  ]
  for (index, call) in calls.enumerated() { frames.append(["jsonrpc": "2.0", "id": index + 2, "method": "tools/call", "params": ["name": call.0, "arguments": call.1]]) }
  for frame in frames { try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: frame) + Data([10])) }
  try input.fileHandleForWriting.close()
  let deadline = Date().addingTimeInterval(8)
  while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
  if process.isRunning { process.terminate(); throw StoreError.database("stdio creation timeout") }
  let data = try Data(contentsOf: output)
  try require(!String(decoding: data, as: UTF8.self).contains(String(decoding: originalKey, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)), "stdio leaked credential")
  let replies = try data.split(separator: 10).map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] }
  try require(process.terminationStatus == 0 && replies.count == calls.count + 2, "stdio lifecycle failed")
  let tools = (replies[1]["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
  try require(Set(tools.compactMap { $0["name"] as? String }) == Set(["workdesk_projects", "workdesk_project_create", "workdesk_progress", "workdesk_task_create"]), "four tool contract changed")
  return Array(replies.dropFirst(2))
 }
 func content(_ response: [String: Any]) throws -> Any {
  let result = response["result"] as? [String: Any]
  let text = (result?["content"] as? [[String: Any]])?.first?["text"] as? String ?? "null"
  return try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
 }
 func expect(_ response: [String: Any], _ outcome: String) throws {
  try require((try content(response) as? [String: Any])?["outcome"] as? String == outcome, "expected \(outcome): \(response)")
  try require((response["result"] as? [String: Any])?["isError"] as? Bool == (outcome != "accepted"), "isError mismatch")
 }
 let create = ("workdesk_project_create", ["alias": "new", "title": "隔离新项目", "event_id": "create-1"])
 try expect(rpc([create])[0], "rejected")
 try require(try await store.projects().isEmpty, "default denial created project")
 // Legacy CLI capability alone must not grant MCP creation.
 try await store.setProjectCreationPermission(source: source, allowed: true)
 try expect(rpc([create])[0], "rejected")
 try await store.authorizeMCP(source: source, project: nil, createProjects: true, createTasks: false, credentials: credentials)
 let first = try rpc([create, ("workdesk_projects", [:]), ("workdesk_progress", ["alias": "new", "text": "真实 stdio 动态", "event_id": "progress-1"]), ("workdesk_task_create", ["alias": "new", "text": "未授权待办", "event_id": "task-1"]), create])
 try expect(first[0], "accepted"); try expect(first[2], "accepted"); try expect(first[3], "rejected"); try expect(first[4], "accepted")
 let visible = try content(first[1]) as? [[String: Any]]
 try require(visible?.count == 1 && visible?[0]["alias"] as? String == "new" && visible?[0]["canCreateTasks"] as? Bool == false, "new project not immediately scoped")
 let created = try await store.projects()[0]
 try require(try await store.projects().count == 1, "duplicate project")
 try require(try await store.projectProgress(created.id).count == 1, "progress not visible in normal query")
 try require(try await store.tasks(created.id).isEmpty, "tasks granted without selection")
 try expect(rpc([("workdesk_project_create", ["alias": "other", "title": "隔离新项目", "event_id": "create-1"])])[0], "conflict")
 try expect(rpc([("workdesk_project_create", ["alias": "new", "title": "修改标题", "event_id": "create-1"])])[0], "conflict")
 try expect(rpc([("workdesk_project_create", ["alias": "new", "title": "覆盖别名", "event_id": "collision"])])[0], "rejected")
 try await store.setMCPCreationPermission(source: source, enabled: false)
 try expect(rpc([create])[0], "rejected")
 try await store.authorizeMCP(source: source, project: nil, createProjects: true, createTasks: true, credentials: credentials)
 // Existing projects retain their separately selected permissions.
 try require(try await store.mcpPermission(source: source, alias: "new") == false, "global update elevated existing project")
 let taskCreate = ("workdesk_task_create", ["alias": "with-tasks", "text": "授权待办", "event_id": "task-2"])
 let allowed = try rpc([("workdesk_project_create", ["alias": "with-tasks", "title": "含待办权限", "event_id": "create-2"]), taskCreate, taskCreate])
 for response in allowed { try expect(response, "accepted") }
 let taskProject = try await store.bindings().first { $0.alias == "with-tasks" }!.project
 try require(try await store.tasks(taskProject).count == 1, "task duplicated")
 try await store.setMCPPermission(source: source, alias: "with-tasks", enabled: true, createTasks: false)
 try expect(rpc([taskCreate])[0], "rejected")
 try await store.setMCPPermission(source: source, alias: "new", enabled: false)
 try expect(rpc([create])[0], "rejected")
 let hidden = try await store.createProject("其他项目")
 try await store.bind(source: source, alias: "hidden", project: hidden.id)
 try expect(rpc([("workdesk_project_create", ["alias": "hidden", "title": "越权绑定", "event_id": "hidden-create"])])[0], "rejected")
 try expect(rpc([("workdesk_progress", ["alias": "hidden", "text": "越权动态", "event_id": "hidden-progress"])])[0], "rejected")
 try require(try await store.mcpPermission(source: source, alias: "hidden") == nil, "creation elevated unrelated project")
 // UI authorization rollback: invalid project must not persist a changed global scope.
 do { try await store.authorizeMCP(source: source, project: "missing-project", createProjects: false, createTasks: false, credentials: credentials); throw StoreError.missing } catch StoreError.database { }
 try require(try await store.mcpCreationPermission(source: source) == true, "authorization was not atomic")
 // Rebinding the alias to another project cannot replay the original accepted creation.
 try await store.bind(source: source, alias: "new", project: hidden.id)
 try await store.setMCPPermission(source: source, alias: "new", enabled: true)
 try expect(rpc([create])[0], "conflict")
 for args in [["alias": " x", "title": "x", "event_id": "invalid"], ["alias": "x", "title": " ", "event_id": "invalid"], ["alias": "x", "title": "x", "event_id": "invalid", "createTasks": "true"]] {
  try require(try rpc([("workdesk_project_create", args)])[0]["error"] != nil, "invalid creation accepted")
 }
 // A stale key is unavailable; discovery does not register/restore it.
 try Data("stale\n".utf8).write(to: key)
 try require(try await store.localAgents(credentials: credentials).first?.credentialAvailable == false, "stale credential considered usable")
 try require((try rpc([create])[0]["result"] as? [String: Any])?["isError"] as? Bool == true, "invalid identity replay accepted")
 try originalKey.write(to: key)
 let next = try await store.createAvailableLocalIdentity(credentials: credentials)
 try require(next != source && (try Data(contentsOf: key)) == originalKey, "identity creation rotated old credential")
 print("PASS: real MCP stdio create -> list -> progress accepted -> task denied/accepted; four tools, default denial, CLI-only denial, atomic onboarding, inherited scopes, duplicate/conflict, alias isolation, revoked replay, stale identity; isolated fixtures only")
}
