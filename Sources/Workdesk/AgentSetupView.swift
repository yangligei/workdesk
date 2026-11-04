import SwiftUI
import WorkdeskCore

struct AgentSetupView: View {
 @ObservedObject var model: Model
 @State private var discovery: HermesDiscovery?
 @State private var agents: [LocalAgent] = []
 @State private var source = "local-agent"
 @State private var busy = false
 @State private var result = ""
 private var credentials: URL { model.connectionCredentials }
 private var binding: SourceBinding? { model.bindings.first { $0.source == source && $0.project == model.selection } }
 var body: some View {
  VStack(alignment: .leading, spacing: 12) {
   Text("智能体接入").font(.title2).bold()
   Text("1 · 识别本机 Hermes").font(.headline)
   Text(discovery.map { $0.executable != nil ? "已检测到 Hermes 可执行文件" : ($0.homeDetected ? "仅检测到 Hermes 目录，未找到可执行文件" : "未检测到 Hermes") } ?? "正在识别…")
   Text("网关：" + (discovery?.gateway ?? "检查中…"))
   Text("QQ 收发：此向导尚未验证。网关运行不代表 QQ 已接通。").font(.caption).foregroundStyle(.secondary)
   Button("重新识别") { refresh() }.disabled(busy)
   Divider()
   Text("2 · 选择身份与项目").font(.headline)
   if agents.isEmpty { Text("尚无已登记身份，点击下方按钮创建本机身份。") }
   else {
    Picker("已有智能体身份", selection: $source) {
     ForEach(agents) { agent in Text(agent.name + (agent.credentialAvailable ? " · 可测试" : " · 凭据不在默认位置")).tag(agent.name) }
    }
   }
   Button("创建本机身份 local-agent") {
    run {
     guard let store = model.store else { return }
     try await store.createLocalIdentity(credentials: credentials)
     agents = try await store.localAgents(credentials: credentials); source = "local-agent"
     result = "本机身份已登记，凭据由程序管理。请继续选择项目并授权。"
    }
   }.disabled(busy || agents.contains { $0.name == "local-agent" })
   ProjectChooser(model: model)
   Text("授权状态：" + (binding == nil ? "未授权当前项目" : "已绑定当前项目 · " + (binding?.alias ?? "")))
   Button("授权所选身份接入当前项目") {
    run {
     guard let project = model.selection, let store = model.store else { return }
     // Project ID aliases cannot overwrite another project's existing alias.
     try await store.authorizeLocalProject(source: source, project: project, credentials: credentials)
     await model.reload(); result = "已授权当前项目。可点击下方按钮检查签名写入。"
    }
   }.disabled(busy || model.selection == nil || binding != nil || !agents.contains { $0.name == source })
   Text("仅本机点击授予所选项目写入权；不会授予创建项目权限。检测本身不会授权。可在下方撤销绑定。").font(.caption).foregroundStyle(.secondary)
   Divider()
   Text("3 · 检查连接").font(.headline)
   Button("检查连接并写入测试动态") {
    run {
     guard let store = model.store, let binding, let root = model.connectionRoot, let inbox = model.connectionInbox else { return }
     let receipt = try await store.checkConnection(source: source, alias: binding.alias, credentials: credentials, root: root, inbox: inbox)
     result = receipt.outcome == "accepted" ? "签名写入已接受 · 回执 " + receipt.eventID : "检查未通过：" + receipt.outcome + " · " + receipt.detail
     await model.reload()
    }
   }.disabled(busy || binding == nil || !agents.contains { $0.name == source && $0.credentialAvailable })
   if busy { ProgressView().controlSize(.small) }
   if !result.isEmpty { Text(result).font(.caption).textSelection(.enabled) }
   Text("本向导识别 Hermes，并提供本机签名协议接入。其他工具尚不支持自动发现。成功测试证明本机身份可写入当前项目；智能体后续仍需主动上报，不会读取聊天或自动同步所有消息。").font(.caption).foregroundStyle(.secondary)
  }.padding(16).background(Desk.wash, in: RoundedRectangle(cornerRadius: 8))
   .task { refresh() }
   .onChange(of: source) { _ in result = "" }
   .onChange(of: model.selection) { _ in result = "" }
   .onChange(of: model.bindings.map { $0.id + ":" + $0.project }) { _ in result = "" }
 }
 private func refresh() {
  run {
   discovery = await Task.detached { HermesDiscovery.scan() }.value
   if let store = model.store { agents = try await store.localAgents(credentials: credentials) }
   if !agents.contains(where: { $0.name == source }), let first = agents.first { source = first.name }
  }
 }
 private func run(_ action: @escaping () async throws -> Void) {
  busy = true
  Task { @MainActor in
   defer { busy = false }
   do { try await action() } catch { result = "操作未完成：" + error.localizedDescription }
  }
 }
}
