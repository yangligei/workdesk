import Foundation
import WorkdeskCore

@main struct CLI {
 static func main() async {
  do {
   let args = Array(CommandLine.arguments.dropFirst())
   let root = ProcessInfo.processInfo.environment["WORKDESK_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Workdesk")
   guard let command = args.first else { throw StoreError.database(Self.usage) }
   switch command {
   case "mcp":
    let flags = try Self.flags(Array(args.dropFirst()))
    guard let source = flags["source"], let key = flags["token-file"], Set(flags.keys).isSubset(of: ["source", "token-file", "data-dir"]) else { throw StoreError.database("mcp --source NAME --token-file PATH [--data-dir PATH]") }
    let mcpRoot = flags["data-dir"].map { URL(fileURLWithPath: $0) } ?? root
    let server = try MCPServer(root: mcpRoot, source: source, credential: URL(fileURLWithPath: key))
    await server.run()
   case "enroll":
    let flags = try Self.flags(Array(args.dropFirst()))
    guard let name = flags["name"], let path = flags["token-file"] else { throw StoreError.database("enroll --name NAME --token-file PATH [--project PROJECT_ID --alias ALIAS]") }
    let store = try Store(root: root)
    let credential = try await store.registerSource(name, project: flags["project"] ?? "", alias: flags["alias"] ?? "", tokenFile: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
    print("已登记来源：\(credential.name)\n凭据文件：\(credential.tokenFile.path)（权限 600，请勿提交或打印）\n绑定：\(credential.alias) → \(credential.project)")
   case "grant-create":
    let flags = try Self.flags(Array(args.dropFirst()))
    guard let name = flags["name"], let allow = flags["allow"], ["yes", "no"].contains(allow) else { throw StoreError.database("grant-create --name NAME --allow yes|no（仅本机显式授权）") }
    let store = try Store(root: root)
    try await store.setProjectCreationPermission(source: name, allowed: allow == "yes")
    print("项目创建许可已设为：\(allow)")
   case "report":
    let flags = try Self.flags(Array(args.dropFirst()))
    guard let source = flags["source"], let alias = flags["alias"], let text = flags["text"] else { throw StoreError.database("report --source NAME --alias ALIAS --text TEXT [--type progress] [--token-file PATH]") }
    let path = flags["token-file"] ?? ProcessInfo.processInfo.environment["WORKDESK_TOKEN_FILE"] ?? ""
    guard !path.isEmpty else { throw StoreError.database("缺少 --token-file 或 WORKDESK_TOKEN_FILE") }
    let token = String(decoding: try InboxFiles.read(URL(fileURLWithPath: (path as NSString).expandingTildeInPath), limit: 4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    var event = ProgressEvent(sourceID: source, projectID: alias, type: flags["type"] ?? "progress", text: text)
    if let id = flags["event-id"] { event.eventID = id }
    event.taskID = flags["task-id"]
    if let version = flags["expected-version"] { guard let value = Int(version) else { throw StoreError.database("版本必须是整数") }; event.expectedVersion = value }
    try EventSigning.sign(&event, privateKey: token)
    print(try EventInbox.submit(event, root: root))
   case "submit":
    guard args.count == 2 else { throw StoreError.database("submit SIGNED_EVENT.json") }
    let event = try JSONDecoder().decode(ProgressEvent.self, from: InboxFiles.read(URL(fileURLWithPath: args[1])))
    print(try EventInbox.submit(event, root: root))
   case "receipt":
    guard args.count == 2, args[1] == URL(fileURLWithPath: args[1]).lastPathComponent, args[1].hasSuffix(".json") else { throw StoreError.database("receipt 只接受回执文件名") }
    print(String(decoding: try InboxFiles.read(root.appendingPathComponent("receipts/" + args[1])), as: UTF8.self))
   case "projects":
    let store = try Store(root: root)
    print(String(decoding: try JSONEncoder().encode(await store.projects()), as: UTF8.self))
   case "drain":
    let store = try Store(root: root); let inbox = try EventInbox(root: root, store: store)
    try await inbox.drain(); print("已处理收件箱")
   default: throw StoreError.database(Self.usage)
   }
  } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
 }
 static let usage = "WorkdeskCLI mcp --source NAME --token-file PATH [--data-dir PATH] | enroll --name NAME --token-file PATH [--project ID --alias ALIAS] | grant-create --name NAME --allow yes|no | report --source NAME --alias ALIAS --text TEXT --token-file PATH | submit SIGNED.json | receipt FILE.json | projects | drain"
 static func flags(_ args: [String]) throws -> [String: String] {
  var result: [String: String] = [:]; var index = 0
  while index < args.count {
   guard args[index].hasPrefix("--"), index + 1 < args.count else { throw StoreError.database("参数须为 --名称 值") }
   result[String(args[index].dropFirst(2))] = args[index + 1]; index += 2
  }
  return result
 }
}
