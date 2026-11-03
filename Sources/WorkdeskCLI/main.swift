import Foundation
import WorkdeskCore

@main struct CLI {
 static func main() {
  do {
   let args = Array(CommandLine.arguments.dropFirst())
   let root = ProcessInfo.processInfo.environment["WORKDESK_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Workdesk")
   guard let command = args.first else { throw StoreError.database("用法：WorkdeskCLI report SOURCE ALIAS TEXT | submit EVENT.json | receipt FILE.json | projects") }
   switch command {
   case "report":
    guard args.count == 4 else { throw StoreError.database("report SOURCE ALIAS TEXT") }
    print(try EventInbox.submit(ProgressEvent(sourceID: args[1], projectID: args[2], type: "progress", text: args[3]), root: root))
   case "submit":
    guard args.count == 2 else { throw StoreError.database("submit EVENT.json") }
    let event = try JSONDecoder().decode(ProgressEvent.self, from: InboxFiles.read(URL(fileURLWithPath: args[1])))
    print(try EventInbox.submit(event, root: root))
   case "receipt":
    guard args.count == 2, args[1] == URL(fileURLWithPath: args[1]).lastPathComponent, args[1].hasSuffix(".json") else { throw StoreError.database("receipt 只接受回执文件名") }
    print(String(decoding: try InboxFiles.read(root.appendingPathComponent("receipts/" + args[1])), as: UTF8.self))
   case "projects":
    print(String(decoding: try InboxFiles.read(root.appendingPathComponent("projects.json"), limit: 1048576), as: UTF8.self))
   default: throw StoreError.database("未知命令")
   }
  } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
 }
}
