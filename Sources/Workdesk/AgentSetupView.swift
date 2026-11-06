import SwiftUI
import WorkdeskCore

struct AgentSetupView: View {
 @ObservedObject var model: Model
 @State private var discovery: HermesDiscovery?
 @State private var agents: [LocalAgent] = []
 @State private var source = ""
 @State private var allowProjects = false
 @State private var allowTasks = false
 @State private var includeProject = true
 @State private var creationPermission: Bool?
 @State private var authorizationRevision = 0
 @State private var loadingPermission = true
 @State private var busy = false
 @State private var result = ""
 private var credentials: URL { model.connectionCredentials }
 private var binding: SourceBinding? { model.bindings.first { $0.source == source && $0.project == model.selection } }
 var body: some View {
  VStack(alignment: .leading, spacing: 12) {
   Text("智能体连接中心").font(.title2).bold()
   Text("首次选择身份与权限并授权，之后可持续使用；客户端配置仍需你确认。任务完成仍由你确认。").font(.system(size: 13.5)).foregroundStyle(.secondary)
   Text("1 · 首次授权与权限管理").font(.headline)
   if agents.isEmpty { Text("尚无已登记身份，点击下方按钮创建。无需填写密钥。") }
   else {
    Picker("已有智能体身份", selection: $source) {
     ForEach(agents) { agent in Text(agent.name + (agent.credentialAvailable ? " · 凭据可用" : " · 凭据不在默认位置")).tag(agent.name) }
    }
   }
   Button("创建新的本机身份") {
    run {
     guard let store = model.store else { return }
     source = try await store.createAvailableLocalIdentity(credentials: credentials)
     agents = try await store.localAgents(credentials: credentials)
     result = "本机身份已登记。请勾选权限并点击授权。"
    }
   }.disabled(busy)
   ProjectChooser(model: model)
   MCPAuthorizationOptions(allowProjects: $allowProjects, allowTasks: $allowTasks, includeProject: $includeProject, hasProject: model.selection != nil)
    .disabled(busy || loadingPermission)
   Text("新项目权限：" + (creationPermission == nil ? "未授权" : creationPermission == true ? "允许创建，且可在新项目创建待办" : "允许创建，仅可上报动态"))
    .font(.system(size: 11)).foregroundStyle(.secondary)
   HStack {
    Button("授权所选范围并记住") {
     run {
      guard let store = model.store else { return }
      try await store.authorizeMCP(source: source, project: includeProject ? model.selection : nil, createProjects: allowProjects, createTasks: allowTasks, credentials: credentials)
      creationPermission = allowProjects ? allowTasks : nil
      authorizationRevision += 1
      await model.reload(); result = "授权已保存。以后在此范围内无需重复授权；继续配置客户端。"
     }
    }.frame(minHeight: 48).disabled(busy || loadingPermission || !agents.contains { $0.name == source && $0.credentialAvailable })
    Button("撤销创建新项目权限") {
     run {
      guard let store = model.store else { return }
      try await store.setMCPCreationPermission(source: source, enabled: false)
      creationPermission = nil; allowProjects = false; result = "已撤销创建新项目权限。已授权项目可在下方单独撤销。"
     }
    }.frame(minHeight: 48).disabled(busy || creationPermission == nil)
   }
   Text("同一身份的客户端共享权限。创建新项目默认关闭；已授权项目互相独立。此授权仅适用于 Workdesk，不授予任意文件访问或任务完成能力。身份失效时请选择有效身份并重新导出配置，不要恢复旧密钥。").font(.system(size: 11)).foregroundStyle(.secondary)
   Divider()
   if let root = model.connectionRoot {
    MCPConnectionView(model: model, source: source, binding: binding, root: root, credentials: credentials)
     .id(source + ":" + (binding?.id ?? "unbound") + ":" + (model.selection ?? "") + ":" + String(authorizationRevision))
   }
   if busy { ProgressView().controlSize(.small) }
   if !result.isEmpty { Text(result).font(.caption).textSelection(.enabled) }
   DisclosureGroup("高级 · Hermes 网关与原签名协议") {
    VStack(alignment: .leading, spacing: 8) {
     Text(discovery.map { $0.executable != nil ? "已发现 Hermes" : "未找到 Hermes 可执行文件" } ?? "尚未检查")
     Text("网关：" + (discovery?.gateway ?? "尚未检查"))
     Text("QQ 收发独立验证；MCP accepted 不代表 QQ 已接通。").font(.caption)
     Button("检查 Hermes 网关") { run { discovery = await Task.detached { HermesDiscovery.scan() }.value } }.disabled(busy)
     Button("检查原签名协议并写入测试动态") {
      run {
       guard let store = model.store, let binding, let root = model.connectionRoot, let inbox = model.connectionInbox else { return }
       let receipt = try await store.checkConnection(source: source, alias: binding.alias, credentials: credentials, root: root, inbox: inbox)
       result = receipt.outcome + " · " + receipt.eventID + " · " + receipt.detail
       await model.reload()
      }
     }.disabled(busy || binding == nil || !agents.contains { $0.name == source && $0.credentialAvailable })
    }.padding(.top, 8)
   }
  }.padding(16).background(Desk.wash, in: RoundedRectangle(cornerRadius: 8))
   .task { run { if let store = model.store { agents = try await store.localAgents(credentials: credentials) }; if !agents.contains(where: { $0.name == source }), let first = agents.first { source = first.name } } }
   .task(id: source + ":" + (model.selection ?? "")) {
    loadingPermission = true
    defer { loadingPermission = false }
    do {
     if let store = model.store {
      creationPermission = try await store.mcpCreationPermission(source: source)
      allowProjects = creationPermission != nil
      let currentTasks: Bool? = if let binding { try await store.mcpPermission(source: source, alias: binding.alias) } else { nil }
      allowTasks = creationPermission ?? currentTasks ?? false
     }
    } catch { result = "读取权限失败：" + error.localizedDescription }
   }
   .onChange(of: source) { _ in result = "" }
   .onChange(of: model.selection) { _ in result = "" }
 }
 private func run(_ action: @escaping () async throws -> Void) {
  busy = true
  Task { @MainActor in defer { busy = false }; do { try await action() } catch { result = "操作未完成：" + error.localizedDescription } }
 }
}

struct MCPConnectionView: View {
 @ObservedObject var model: Model
 let source: String
 let binding: SourceBinding?
 let root: URL
 let credentials: URL
 @State private var client = AgentClient.hermes
 @State private var permission: Bool?
 @State private var allowTasks = false
 @State private var busy = false
 @State private var result = ""
 @State private var configured = false
 @State private var discovered: Set<AgentClient> = []
 @State private var configuredClients: Set<AgentClient> = []
 @State private var showPreview = false
 @State private var verification = "尚未验证 accepted"
 private var plan: ConnectionPlan { ConnectionPlan(client: client, cli: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/WorkdeskCLI").path, root: root, source: source, credential: credentials.appendingPathComponent(source + ".key")) }
 var body: some View {
  VStack(alignment: .leading, spacing: 12) {
   Text("2 · 选择连接方式").font(.headline)
   LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 8)], spacing: 8) {
    ForEach(AgentClient.allCases) { item in
     Button {
      client = item; refresh()
     } label: {
      VStack(alignment: .leading, spacing: 5) {
       Label(item.title, systemImage: item == .generic ? "point.3.connected.trianglepath.dotted" : "terminal")
        .font(.headline)
       Text(item == .generic ? "stdio 配置导出" : configuredClients.contains(item) ? "已配置 · 项目中立" : discovered.contains(item) ? "已发现 · 未配置" : "未发现可执行文件")
        .font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(10)
       .background(client == item ? Desk.green.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
       .overlay(RoundedRectangle(cornerRadius: 8).stroke(client == item ? Desk.green : Color.clear, lineWidth: 1))
       .contentShape(Rectangle())
     }.buttonStyle(.plain).disabled(busy)
    }
   }
   Text("Cursor / Cline / Roo：可按通用 MCP 配置尝试，尚未实测。WorkBuddy：接口待核实，暂未接入。").font(.caption).foregroundStyle(.secondary)
   HStack {
    Text("配置：" + (configured ? "本应用配置与写入记录一致" : "未配置或配置已变化"))
    Spacer()
    Link("官方接入说明", destination: client.docs)
   }.font(.caption)
   HStack {
    Button(client == .generic ? "查看通用配置" : "预览并配置 " + client.title) { showPreview = true }
    Button("撤销本应用配置") {
     let selected = plan
     run { try await Task.detached { try selected.undo() }.value; configured = false; result = "已撤销本应用添加的配置。项目授权保持独立，可在下方撤销。" }
    }.disabled(busy || !plan.hasBackup)
   }
   Text("配置后在客户端刷新 MCP 或重新打开会话。若未安装客户端，请先按官方说明安装；此处不会自动安装软件。").font(.caption).foregroundStyle(.secondary)
   Divider()
   Text("3 · 授予当前项目 MCP 权限").font(.headline)
   Text(binding == nil ? "请先完成上方项目绑定" : permission == nil ? "MCP 未授权" : permission == true ? "允许动态与任务创建" : "仅允许项目查询与动态")
   Toggle("另外允许创建待办任务", isOn: $allowTasks).disabled(busy || binding == nil)
   HStack {
    Button(permission == nil ? "授权当前项目 MCP" : "更新 MCP 权限") {
     run {
      guard let binding, let store = model.store else { return }
      try await store.setMCPPermission(source: source, alias: binding.alias, enabled: true, createTasks: allowTasks)
      permission = allowTasks; verification = "授权已更新，请重新验证"
     }
    }.disabled(busy || binding == nil)
    Button("撤销当前项目 MCP") {
     run {
      guard let binding, let store = model.store else { return }
      try await store.setMCPPermission(source: source, alias: binding.alias, enabled: false)
      permission = nil; verification = "授权已撤销"
     }
    }.disabled(busy || permission == nil)
   }
   Text("当前项目授权不改变全局创建新项目权限，也不允许完成任务、修改状态或自行授权。").font(.caption).foregroundStyle(.secondary)
   Divider()
   Text("4 · 验证真实 MCP 写入").font(.headline)
   Button("运行 MCP 握手并写入测试动态") {
    let selected = plan
    run {
     guard let binding else { return }
     let receipt = try await Task.detached { try selected.probe(alias: binding.alias) }.value
     verification = receipt.outcome == "accepted" ? "本机 MCP 已验证 accepted · " + receipt.eventID : "未通过 · " + receipt.outcome + " · " + receipt.detail
     await model.reload()
    }
   }.disabled(busy || permission == nil)
   Text(verification).font(.caption).textSelection(.enabled)
   Text("此按钮验证 Workdesk 自身的 stdio 子进程、签名和存储；第三方会话是否调用成功需在该客户端实际验证。").font(.caption).foregroundStyle(.secondary)
   if busy { ProgressView().controlSize(.small) }
   if !result.isEmpty { Text(result).font(.caption).textSelection(.enabled) }
  }.task { refresh() }
   .sheet(isPresented: $showPreview) {
    VStack(alignment: .leading, spacing: 14) {
     Text(client.title + " · 配置预览").font(.title2).bold()
     Text("确认后仅添加 workdesk。写入前备份；撤销时若发现用户修改会停止，不覆盖改动。不会修改项目授权。")
     ScrollView { Text(plan.preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
     HStack {
      Button("关闭") { showPreview = false }
      Button("复制配置") {
       NSPasteboard.general.clearContents()
       let selected = plan
       let object: [String: Any] = [client == .opencode ? "mcp" : client == .hermes || client == .codex ? "mcp_servers" : "mcpServers": ["workdesk": selected.entry]]
       if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) { NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string) }
      }
      Spacer()
      if client != .generic {
       Button("确认添加配置") {
        let selected = plan; showPreview = false
        run { try await Task.detached { try selected.apply() }.value; configured = selected.configured(); result = "已添加并备份配置。请在 " + selected.client.title + " 刷新 MCP 或重新打开会话，再执行下方本机验证。" }
       }.disabled(busy)
      }
     }
    }.padding(20).frame(width: 640, height: 470)
   }
 }
 private func refresh() {
  let selected = plan
  run {
   let state = await Task.detached {
    let cli = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/WorkdeskCLI").path
    let plans = AgentClient.allCases.map { ConnectionPlan(client: $0, cli: cli, root: root, source: source, credential: credentials.appendingPathComponent(source + ".key")) }
    return (selected.configured(), Set(AgentClient.allCases.filter { $0.executable(home: selected.home, environment: selected.environment) != nil }), Set(plans.filter { $0.configured() }.map { $0.client }))
   }.value
   configured = state.0; discovered = state.1; configuredClients = state.2
   if let binding, let store = model.store { permission = try await store.mcpPermission(source: source, alias: binding.alias) } else { permission = nil }
   allowTasks = permission ?? false
  }
 }
 private func run(_ action: @escaping () async throws -> Void) {
  busy = true
  Task { @MainActor in defer { busy = false }; do { try await action() } catch { result = "操作未完成：" + error.localizedDescription } }
 }
}
