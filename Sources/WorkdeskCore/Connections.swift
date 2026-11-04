import Foundation
import Darwin
import CryptoKit

public enum AgentClient: String, CaseIterable, Identifiable, Codable, Sendable {
 case hermes, codex, claude, opencode, generic
 public var id: String { rawValue }
 public var title: String { switch self { case .hermes: return "Hermes"; case .codex: return "Codex"; case .claude: return "Claude Code"; case .opencode: return "OpenCode"; case .generic: return "通用 MCP" } }
 public var docs: URL { let value = switch self {
  case .hermes: "https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp"
  case .codex: "https://developers.openai.com/codex/mcp"
  case .claude: "https://code.claude.com/docs/en/mcp"
  case .opencode: "https://opencode.ai/docs/mcp-servers/"
  case .generic: "https://modelcontextprotocol.io/docs/develop/connect-local-servers"
 }; return URL(string: value)! }
 public func executable(home: URL, environment: [String: String]) -> String? {
  guard self != .generic else { return nil }
  let paths = (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/" + rawValue } + [".local/bin/", ".opencode/bin/", ".npm-global/bin/"].map { home.appendingPathComponent($0 + rawValue).path } + ["/opt/homebrew/bin/" + rawValue, "/usr/local/bin/" + rawValue]
  return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
 }
 public func config(home: URL, environment: [String: String]) -> URL? {
  switch self {
  case .hermes: return URL(fileURLWithPath: environment["HERMES_HOME"] ?? home.appendingPathComponent(".hermes").path).appendingPathComponent("config.yaml")
  case .codex: return URL(fileURLWithPath: environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path).appendingPathComponent("config.toml")
  case .claude: return environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0).appendingPathComponent(".claude.json") } ?? home.appendingPathComponent(".claude.json")
  case .opencode: return environment["OPENCODE_CONFIG"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: environment["XDG_CONFIG_HOME"] ?? home.appendingPathComponent(".config").path).appendingPathComponent("opencode/opencode.json")
  case .generic: return nil
  }
 }
}

public struct ConnectionPlan: Sendable {
 public let client: AgentClient
 public let cli: String
 public let root: URL
 public let source: String
 public let credential: URL
 public let home: URL
 public let environment: [String: String]
 public init(client: AgentClient, cli: String, root: URL, source: String, credential: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment) {
  self.client = client; self.cli = cli; self.root = root; self.source = source; self.credential = credential; self.home = home; self.environment = environment
 }
 public var arguments: [String] { ["mcp", "--source", source, "--token-file", credential.path, "--data-dir", root.path] }
 public var entry: [String: Any] {
  client == .opencode ? ["type": "local", "command": [cli] + arguments, "enabled": true] : ["command": cli, "args": arguments]
 }
 public var preview: String {
  let object: [String: Any]
  switch client {
  case .hermes, .codex: object = ["mcp_servers": ["workdesk": entry]]
  case .opencode: object = ["mcp": ["workdesk": entry]]
  default: object = ["mcpServers": ["workdesk": entry]]
  }
  let text = String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
  return (client.config(home: home, environment: environment).map { "目标：" + $0.path + "\n" } ?? "在支持 stdio 的 MCP 客户端导入以下 JSON：\n") + (client == .codex || client == .hermes ? "通过官方 CLI 写入，下面展示等价配置内容。\n" : "") + text
 }
 private var state: URL { root.appendingPathComponent("connections/" + client.rawValue + ".json") }
 private struct Record: Codable { let path: String; let before: Data?; let installedHash: String }
 private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
 private func readConfig(_ url: URL) throws -> Data? { FileManager.default.fileExists(atPath: url.path) ? try InboxFiles.read(url, limit: 4 * 1024 * 1024) : nil }
 public func configured() -> Bool {
  guard let record = try? JSONDecoder().decode(Record.self, from: InboxFiles.read(state, limit: 8 * 1024 * 1024)), let path = client.config(home: home, environment: environment), path.path == record.path, let data = try? readConfig(path) else { return false }
  return hash(data) == record.installedHash
 }
 public var hasBackup: Bool { FileManager.default.fileExists(atPath: state.path) }
 public func apply() throws {
  guard client != .generic, let path = client.config(home: home, environment: environment), FileManager.default.isExecutableFile(atPath: cli) else { throw StoreError.database("请先安装 Workdesk，再导入通用 MCP 配置") }
  guard !hasBackup else { throw StoreError.database("已有本应用配置记录；请先撤销，或检查外部修改后重试") }
  // Refuse ambiguous overrides instead of modifying the wrong profile or JSONC file.
  if client == .claude && environment["CLAUDE_CONFIG_DIR"] != nil { throw StoreError.database("自定义 Claude 配置目录请使用通用 MCP 导入，避免写错配置") }
  if client == .opencode && FileManager.default.fileExists(atPath: path.deletingPathExtension().appendingPathExtension("jsonc").path) { throw StoreError.database("检测到 JSONC 配置，请使用通用 MCP 手动合并，现有注释不会改写") }
  let before = try readConfig(path)
  if let before, String(decoding: before, as: UTF8.self).contains("workdesk") { throw StoreError.database("已有 workdesk 配置或同名内容；请先在客户端检查，不会覆盖") }
  let directory = state.deletingLastPathComponent()
  try InboxFiles.directory(directory)
  // Persist a backup before any mutation; interrupted operations remain recoverable locally.
  let pending = directory.appendingPathComponent(client.rawValue + ".backup")
  try (before ?? Data()).write(to: pending, options: [.atomic])
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pending.path)
  do {
  if client == .hermes || client == .codex || client == .claude {
   guard let executable = client.executable(home: home, environment: environment) else { throw StoreError.database("未找到客户端可执行文件，请先安装或使用通用 MCP 配置") }
   let args: [String]
   switch client {
   case .hermes: args = ["mcp", "add", "workdesk", "--command", cli, "--args"] + arguments
   case .codex: args = ["mcp", "add", "workdesk", "--", cli] + arguments
   default: args = ["mcp", "add", "--transport", "stdio", "--scope", "user", "workdesk", "--", cli] + arguments
   }
   try Self.run(executable, args: args, environment: environment)
  } else {
   var object: [String: Any] = [:]
   if let before {
    guard let parsed = try JSONSerialization.jsonObject(with: before) as? [String: Any] else { throw StoreError.database("配置根节点必须是 JSON 对象") }
    object = parsed
   }
   let key = client == .opencode ? "mcp" : "mcpServers"
   guard object[key] == nil || object[key] is [String: Any] else { throw StoreError.database("现有 MCP 配置格式不兼容") }
   var servers = object[key] as? [String: Any] ?? [:]; servers["workdesk"] = entry; object[key] = servers
   // Detect edits since preview/read immediately before writing.
   guard try readConfig(path) == before else { throw StoreError.database("配置已在其他程序修改，请重新预览") }
   try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
   try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: path, options: .atomic)
   try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
  }
  guard let installed = try readConfig(path) else { throw StoreError.database("客户端未写入预期配置；请使用通用 MCP") }
  let text = String(decoding: installed, as: UTF8.self)
  guard text.contains("workdesk"), text.contains(credential.path) else { throw StoreError.database("客户端未写入完整 workdesk 配置；请检查官方命令或改用通用 MCP") }
  var inEntry = false
  for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
   let indent = line.prefix { $0 == " " }.count
   if line.contains("workdesk:") || line.contains("[mcp_servers.workdesk]") { inEntry = true; continue }
   if inEntry, indent <= 2, !line.trimmingCharacters(in: .whitespaces).isEmpty, !line.hasPrefix("#") { inEntry = false }
   if inEntry, line.contains("enabled: false") || line.contains("enabled = false") { throw StoreError.database("客户端将 workdesk 存为禁用；请在客户端检查连接错误后重试") }
  }
  } catch {
   // Do not leave a broken or disabled entry behind after an official CLI failure.
   if let before { try? before.write(to: path, options: [.atomic]) } else { try? FileManager.default.removeItem(at: path) }
   try? FileManager.default.removeItem(at: pending)
   throw error
  }
  try JSONEncoder().encode(Record(path: path.path, before: before, installedHash: hash(try readConfig(path) ?? Data()))).write(to: state, options: .atomic)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: state.path)
 }
 public func undo() throws {
  let record = try JSONDecoder().decode(Record.self, from: InboxFiles.read(state, limit: 8 * 1024 * 1024))
  guard let path = client.config(home: home, environment: environment), path.path == record.path, let data = try readConfig(path), hash(data) == record.installedHash else { throw StoreError.database("配置已有用户修改或路径改变，已停止撤销以保留改动；请在客户端只移除 workdesk") }
  if client == .hermes || client == .codex || client == .claude {
   guard let executable = client.executable(home: home, environment: environment) else { throw StoreError.database("找不到客户端；请在客户端移除 workdesk") }
   try Self.run(executable, args: ["mcp", "remove", "workdesk"] + (client == .claude ? ["--scope", "user"] : []), environment: environment)
  } else if let before = record.before { try before.write(to: path, options: .atomic) }
  else { try FileManager.default.removeItem(at: path) }
  try FileManager.default.removeItem(at: state)
  try? FileManager.default.removeItem(at: state.deletingPathExtension().appendingPathExtension("backup"))
 }
 public func probe(alias: String) throws -> Receipt {
  let eventID = "mcp-check-" + UUID().uuidString
  let requests: [[String: Any]] = [
   ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "Workdesk connection check", "version": "1"]]],
   ["jsonrpc": "2.0", "method": "notifications/initialized"],
   ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
   ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "workdesk_progress", "arguments": ["alias": alias, "text": "Workdesk MCP 本机连接检查（不代表第三方客户端或 QQ 收发验证）", "event_id": eventID]]]
  ]
  let process = Process(), input = Pipe(), output = Pipe()
  process.executableURL = URL(fileURLWithPath: cli); process.arguments = arguments
  process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
  try process.run()
  for request in requests { input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: request) + Data([10])) }
  // Read three live responses before closing stdin; closing early would hide a server that only answers at EOF.
  var pending = Data(), frames: [[String: Any]] = []
  let deadline = Date().addingTimeInterval(10)
  while frames.count < 3 && Date() < deadline {
   var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
   guard poll(&descriptor, 1, 200) >= 0 else { break }
   guard descriptor.revents & Int16(POLLIN) != 0 else { continue }
   var bytes = [UInt8](repeating: 0, count: 4096)
   let count = bytes.withUnsafeMutableBytes { Darwin.read(output.fileHandleForReading.fileDescriptor, $0.baseAddress!, 4096) }
   guard count > 0 else { continue }
   pending.append(contentsOf: bytes[0..<count])
   while let newline = pending.firstIndex(of: 10) {
    let line = pending[..<newline]
    if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { frames.append(object) }
    pending = pending[pending.index(after: newline)...]
   }
  }
  try input.fileHandleForWriting.close()
  while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
  guard !process.isRunning else { process.terminate(); throw StoreError.database("MCP 检查超时") }
  let responses = frames
  guard process.terminationStatus == 0, responses.count == 3, responses[0]["result"] != nil,
        let tools = (responses[1]["result"] as? [String: Any])?["tools"] as? [[String: Any]], tools.count == 3,
        let content = (responses[2]["result"] as? [String: Any])?["content"] as? [[String: Any]], let text = content.first?["text"] as? String else { throw StoreError.database("MCP 握手或工具检查失败") }
  let receipt = try JSONDecoder().decode(Receipt.self, from: Data(text.utf8))
  guard receipt.eventID == eventID else { throw StoreError.database("MCP 回执不匹配") }
  return receipt
 }
 private static func run(_ executable: String, args: [String], environment: [String: String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable); process.arguments = args; process.environment = environment
  process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
  try process.run()
  let deadline = Date().addingTimeInterval(60)
  while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
  if process.isRunning { process.terminate(); throw StoreError.database("官方配置命令超时，请在客户端检查 workdesk 配置") }
  guard process.terminationStatus == 0 else { throw StoreError.database("官方配置命令失败，请检查客户端版本或使用通用 MCP 导入") }
 }
}
