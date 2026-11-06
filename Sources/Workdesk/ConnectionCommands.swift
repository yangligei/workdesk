import SwiftUI
import AppKit

struct ConnectionCommands: View {
 let project: String
 @State private var name = "local-agent"
 @State private var alias = "project"
 private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
 private var cli: String { quote(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/WorkdeskCLI").path) }
 private var token: String { quote(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workdesk-credentials/\(name).key").path) }
 private var prefix: String { ProcessInfo.processInfo.environment["WORKDESK_DATA_DIR"].map { "WORKDESK_DATA_DIR=" + quote($0) + " " } ?? "" }
 private var enroll: String { prefix + cli + " enroll --name " + quote(name) + " --project " + quote(project) + " --alias " + quote(alias) + " --token-file " + token }
 private var report: String { prefix + cli + " report --source " + quote(name) + " --alias " + quote(alias) + " --token-file " + token + " --text '本地模拟器：已完成一步检查（不代表项目完成）'" }
 var body: some View {
  VStack(alignment: .leading, spacing: 8) {
   HStack { TextField("来源名称", text: $name); TextField("项目别名", text: $alias) }
   Text("1. 在终端登记来源。重新登记须使用新的凭据路径；轮换后旧签名立即失效。").font(.caption)
   command(enroll)
   Text("2. 显式上报一次（本地模拟器示例，非真实外部智能体连接）。返回文件名后可用 receipt 文件名查询回执。").font(.caption)
   command(report)
  }.padding(12).background(Desk.wash, in: RoundedRectangle(cornerRadius: 6))
 }
 private func command(_ value: String) -> some View {
  HStack(alignment: .top) {
   Text(value).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
   Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }.buttonStyle(.plain).foregroundStyle(Desk.green)
  }
 }
}
