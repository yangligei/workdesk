import Foundation
import CoreFoundation
import Darwin

public struct MCPProject: Codable, Sendable {
 public let alias: String
 public let title: String
 public let canCreateTasks: Bool
}

public extension Store {
 func mcpSchema() throws {
  try integrationSchema()
  _ = try query("CREATE TABLE IF NOT EXISTS mcp_grants(source TEXT NOT NULL,alias TEXT NOT NULL,create_tasks INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(source,alias))")
 }
 /// Only local UI calls this; no MCP tool can enroll, bind or grant.
 func setMCPPermission(source: String, alias: String, enabled: Bool, createTasks: Bool = false) throws {
  try mcpSchema()
  guard try bindings().contains(where: { $0.source == source && $0.alias == alias }) else { throw StoreError.missing }
  if enabled {
   _ = try query("INSERT INTO mcp_grants(source,alias,create_tasks) VALUES(?,?,?) ON CONFLICT(source,alias) DO UPDATE SET create_tasks=excluded.create_tasks", [source, alias, createTasks ? "1" : "0"])
  } else { _ = try query("DELETE FROM mcp_grants WHERE source=? AND alias=?", [source, alias]) }
 }
 func mcpPermission(source: String, alias: String) throws -> Bool? {
  try mcpSchema()
  return try query("SELECT create_tasks FROM mcp_grants WHERE source=? AND alias=?", [source, alias]).first.map { $0[0] == "1" }
 }
 func mcpProjects(proof: ProgressEvent) throws -> [MCPProject] {
  guard let signature = proof.signature, try verify(source: proof.sourceID, message: proof.signingPayload, signature: signature) else { throw StoreError.database("MCP 身份无效或已撤销") }
  try mcpSchema()
  return try query("SELECT b.alias,p.title,g.create_tasks FROM bindings b JOIN mcp_grants g ON g.source=b.source AND g.alias=b.alias JOIN projects p ON p.id=b.project WHERE b.source=? ORDER BY p.title,b.alias", [proof.sourceID]).map { MCPProject(alias: $0[0], title: $0[1], canCreateTasks: $0[2] == "1") }
 }
}

/// No network listener, shell, or model runtime. Lifetime belongs to the MCP client.
public final class MCPServer {
 private let store: Store
 private let root: URL
 private let source: String
 private let credential: URL
 private var initialized = false
 private var ready = false
 public init(root: URL, source: String, credential: URL) throws {
  self.root = root; self.source = source; self.credential = credential
  store = try Store(root: root)
 }
 private func signed(alias: String, type: String, text: String, eventID: String = UUID().uuidString) throws -> ProgressEvent {
  let key = String(decoding: try InboxFiles.read(credential, limit: 4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  var event = ProgressEvent(sourceID: source, projectID: alias, type: type, text: text)
  event.eventID = eventID; event.transport = "mcp"
  try EventSigning.sign(&event, privateKey: key)
  return event
 }
 public func respond(_ data: Data) async -> Data? {
  func encoded(_ object: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
  func failure(_ id: Any, _ code: Int, _ message: String) -> Data? { encoded(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]) }
  guard let raw = try? JSONSerialization.jsonObject(with: data) else { return failure(NSNull(), -32700, "Parse error") }
  guard let request = raw as? [String: Any], request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else { return failure(NSNull(), -32600, "Invalid Request") }
  let id = request["id"] ?? NSNull()
  if request["id"] == nil {
   if method == "notifications/initialized", initialized { ready = true }
   return nil
  }
  guard id is String || (id is NSNumber && CFGetTypeID(id as CFTypeRef) != CFBooleanGetTypeID()) else { return failure(NSNull(), -32600, "Invalid request id") }
  guard request["params"] == nil || request["params"] is [String: Any] else { return failure(id, -32602, "Invalid params") }
  let params = request["params"] as? [String: Any] ?? [:]
  var result: [String: Any]
  switch method {
  case "initialize":
   guard !initialized, let version = params["protocolVersion"] as? String, params["capabilities"] is [String: Any], params["clientInfo"] is [String: Any] else { return failure(id, -32602, "Invalid initialize params") }
   initialized = true
   result = ["protocolVersion": ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"].contains(version) ? version : "2025-11-25", "capabilities": ["tools": [:]], "serverInfo": ["name": "workdesk", "version": "1.0.0"], "instructions": "先列出授权项目，使用返回的 alias 上报。进度不代表任务完成。每次操作提供稳定 event_id；重试使用相同 ID。仅 accepted 表示已存储。没有授权时请用户在 Workdesk 连接中心操作。"]
  case "ping": result = [:]
  case "tools/list":
   guard ready else { return failure(id, -32002, "Initialize first") }
   result = ["tools": Self.tools]
  case "tools/call":
   guard ready else { return failure(id, -32002, "Initialize first") }
   guard let name = params["name"] as? String, let arguments = params["arguments"] as? [String: Any] ?? (params["arguments"] == nil ? [:] : nil) else { return failure(id, -32602, "Invalid tool params") }
   guard Self.tools.contains(where: { $0["name"] as? String == name }) else { return failure(id, -32602, "Unknown tool") }
   do {
    let content: Data
    if name == "workdesk_projects" {
     guard arguments.isEmpty else { return failure(id, -32602, "No arguments expected") }
     content = try JSONEncoder().encode(await store.mcpProjects(proof: signed(alias: "", type: "progress", text: "identity proof")))
    } else {
     guard Set(arguments.keys) == Set(["alias", "text", "event_id"]), let alias = arguments["alias"] as? String, let text = arguments["text"] as? String, let eventID = arguments["event_id"] as? String,
           !alias.isEmpty, alias.utf8.count <= 128, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 32000, !eventID.isEmpty, eventID.utf8.count <= 128 else { return failure(id, -32602, "Require alias, nonempty text (max 32000 UTF-8 bytes), event_id (max 128 bytes); no extra arguments") }
     let event = try signed(alias: alias, type: name == "workdesk_progress" ? "progress" : "task.create", text: text, eventID: eventID)
     let receipt = try await store.receive(event)
     content = try JSONEncoder().encode(receipt)
     // Receipt notification refreshes the normal project view even when no inbox drainer is running.
     let directory = root.appendingPathComponent("receipts")
     try InboxFiles.directory(directory)
     try content.write(to: directory.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
     result = ["content": [["type": "text", "text": String(decoding: content, as: UTF8.self)]], "isError": receipt.outcome != "accepted"]
     return encoded(["jsonrpc": "2.0", "id": id, "result": result])
    }
    result = ["content": [["type": "text", "text": String(decoding: content, as: UTF8.self)]], "isError": false]
   } catch {
    // Never echo keys, arbitrary file paths, SQLite errors or request contents to clients.
    result = ["content": [["type": "text", "text": "Workdesk 操作失败：请在本机检查身份、授权和存储；重试沿用同一 event_id。"]], "isError": true]
   }
  default: return failure(id, -32601, "Method not found")
  }
  return encoded(["jsonrpc": "2.0", "id": id, "result": result])
 }
 public func run() async {
  // Bounded newline framing; discard oversized lines without allocating unbounded memory.
  // POSIX read returns available bytes for a live pipe; FileHandle.read(upToCount:) can wait for a full buffer.
  var line = Data(), overflow = false
  var buffer = [UInt8](repeating: 0, count: 4096)
  while true {
   let count = buffer.withUnsafeMutableBytes { Darwin.read(0, $0.baseAddress!, 4096) }
   if count < 0 { if errno == EINTR { continue }; break }
   if count == 0 { break }
   for byte in buffer[0..<count] {
    if byte == 10 {
     let response = overflow ? Data("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Message exceeds 64 KiB\"}}".utf8) : await respond(line)
     if let response { FileHandle.standardOutput.write(response + Data([10])) }
     line.removeAll(keepingCapacity: true); overflow = false
    } else if !overflow {
     if line.count >= 65536 { overflow = true; line.removeAll(keepingCapacity: true) } else { line.append(byte) }
    }
   }
  }
 }
 public static var tools: [[String: Any]] {
  let schema: [String: Any] = ["type": "object", "properties": ["alias": ["type": "string", "description": "workdesk_projects 返回的授权别名"], "text": ["type": "string", "minLength": 1, "maxLength": 32000], "event_id": ["type": "string", "minLength": 1, "maxLength": 128]], "required": ["alias", "text", "event_id"], "additionalProperties": false]
  return [
   ["name": "workdesk_projects", "description": "只列出当前身份被本机授权的 MCP 项目", "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false], "annotations": ["readOnlyHint": true]],
   ["name": "workdesk_progress", "description": "记录项目动态并返回真实回执；不改变任务状态", "inputSchema": schema, "annotations": ["idempotentHint": true, "destructiveHint": false]],
   ["name": "workdesk_task_create", "description": "仅在单独获得任务创建许可后新建待办；不能完成任务", "inputSchema": schema, "annotations": ["idempotentHint": true, "destructiveHint": false]]
  ]
 }
}
