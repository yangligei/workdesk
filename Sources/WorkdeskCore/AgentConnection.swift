import Foundation

public struct LocalAgent: Identifiable, Sendable {
 public var id: String { name }
 public let name: String
 public let credentialAvailable: Bool
}

public struct HermesDiscovery: Sendable {
 public let executable: String?
 public let homeDetected: Bool
 public let gateway: String
 public static func executable(home: URL, environment: [String: String]) -> String? {
  let paths = (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/hermes" }
   + [home.appendingPathComponent(".local/bin/hermes").path, "/opt/homebrew/bin/hermes", "/usr/local/bin/hermes"]
  return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
 }
 /// Read-only public CLI query, on demand and bounded. Never returns raw CLI output.
 public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment) -> HermesDiscovery {
  let executable = executable(home: home, environment: environment)
  let hermesHome = environment["HERMES_HOME"] ?? home.appendingPathComponent(".hermes").path
  var gateway = "未确认（未找到 Hermes 可执行文件）"
  if let executable {
   let process = Process(), pipe = Pipe()
   process.executableURL = URL(fileURLWithPath: executable); process.arguments = ["gateway", "status"]
   process.environment = environment; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
   do {
    try process.run()
    let deadline = Date().addingTimeInterval(5)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if process.isRunning { process.terminate(); gateway = "检查超时，状态未知" }
    else {
     let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
     if process.terminationStatus == 0 && output.contains("Gateway is running (PID:") { gateway = "正在运行（Hermes 官方状态检查）" }
     else if output.contains("Gateway is not running") || output.contains("Gateway is stopped") { gateway = "未运行" }
     else { gateway = "未确认（状态检查未返回可识别结果）" }
    }
   } catch { gateway = "无法执行状态检查" }
  }
  return HermesDiscovery(executable: executable, homeDetected: FileManager.default.fileExists(atPath: hermesHome), gateway: gateway)
 }
}

public extension Store {
 func localAgents(credentials: URL) throws -> [LocalAgent] {
  try integrationSchema()
  _ = try query("CREATE TABLE IF NOT EXISTS sources(source TEXT PRIMARY KEY,token_hash TEXT NOT NULL,created TEXT NOT NULL,last_seen TEXT)")
  return try query("SELECT source FROM sources ORDER BY source").map { row in
   LocalAgent(name: row[0], credentialAvailable: FileManager.default.fileExists(atPath: credentials.appendingPathComponent(row[0] + ".key").path))
  }
 }
 func authorizeLocalProject(source: String, project: String, credentials: URL) throws {
  guard try localAgents(credentials: credentials).contains(where: { $0.name == source }) else { throw StoreError.missing }
  if let existing = try bindings().first(where: { $0.source == source && $0.alias == project }), existing.project != project {
   throw StoreError.database("同名映射已用于其他项目，请先在高级设置检查并撤销")
  }
  try bind(source: source, alias: project, project: project)
 }
 /// This entry point never replaces an existing identity or credential.
 func createLocalIdentity(credentials: URL) throws {
  guard try !localAgents(credentials: credentials).contains(where: { $0.name == "local-agent" }) else { throw StoreError.database("local-agent 已登记，请选择现有身份；不会更换凭据") }
  _ = try registerSource("local-agent", tokenFile: credentials.appendingPathComponent("local-agent.key"))
 }
 func checkConnection(source: String, alias: String, credentials: URL, root: URL, inbox: EventInbox) async throws -> Receipt {
  let key = String(decoding: try InboxFiles.read(credentials.appendingPathComponent(source + ".key"), limit: 4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  var event = ProgressEvent(sourceID: source, projectID: alias, type: "progress", text: "Workdesk 本机连接检查：签名测试写入（不代表任务完成或 QQ 收发验证）")
  try EventSigning.sign(&event, privateKey: key)
  let file = try EventInbox.submit(event, root: root)
  try await inbox.drain()
  let receiptURL = root.appendingPathComponent("receipts/" + file)
  for _ in 0..<50 {
   if FileManager.default.fileExists(atPath: receiptURL.path) { break }
   try await Task.sleep(nanoseconds: 100_000_000)
  }
  let receipt = try JSONDecoder().decode(Receipt.self, from: InboxFiles.read(receiptURL))
  guard receipt.eventID == event.eventID else { throw StoreError.database("回执事件不匹配") }
  return receipt
 }
}
