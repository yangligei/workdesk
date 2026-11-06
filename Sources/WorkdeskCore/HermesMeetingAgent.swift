import Foundation
import Darwin

public final class MeetingProcess: @unchecked Sendable {
 private let lock = NSLock()
 private var process: Process?
 private var stopped: String?
 public init() {}
 public func cancel() { stop("已取消识别；未写入任何事项") }
 private func stop(_ message: String) {
  lock.lock()
  if stopped == nil { stopped = message }
  let running = process
  lock.unlock()
  if let running, running.isRunning {
   running.terminate()
   DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
    if running.isRunning { kill(running.processIdentifier, SIGKILL) }
   }
  }
 }
 public func run(executable: String, arguments: [String], directory: URL, timeout: Double = 120, environment: [String: String]? = nil) async throws -> String {
  try await withTaskCancellationHandler(operation: {
   try await withCheckedThrowingContinuation { continuation in
    DispatchQueue.global(qos: .userInitiated).async {
     let process = Process(), output = Pipe()
     process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
     process.currentDirectoryURL = directory; process.environment = environment
     process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = FileHandle.nullDevice
     self.lock.lock()
     if let stopped = self.stopped {
      self.lock.unlock(); continuation.resume(throwing: StoreError.database(stopped)); return
     }
     self.process = process
     do { try process.run() }
     catch {
      self.process = nil; self.lock.unlock()
      continuation.resume(throwing: StoreError.database("无法启动 Hermes 公共命令")); return
     }
     self.lock.unlock()
     let timer = DispatchSource.makeTimerSource(queue: .global())
     timer.schedule(deadline: .now() + timeout)
     timer.setEventHandler { self.stop("Hermes 识别超时；未写入任何事项") }
     timer.resume()
     var collected = Data()
     while true {
      let chunk = output.fileHandleForReading.availableData
      if chunk.isEmpty { break }
      if collected.count + chunk.count > 2_000_000 { self.stop("Hermes 输出过长，已停止"); break }
      collected.append(chunk)
     }
     process.waitUntilExit(); timer.cancel()
     self.lock.lock()
     let stopped = self.stopped; self.process = nil
     self.lock.unlock()
     if let stopped { continuation.resume(throwing: StoreError.database(stopped)) }
     else if process.terminationStatus != 0 { continuation.resume(throwing: StoreError.database("Hermes 命令失败（退出码 \(process.terminationStatus)），请检查模型连接；原文已保留")) }
     else { continuation.resume(returning: String(decoding: collected, as: UTF8.self)) }
    }
   }
  }, onCancel: { self.cancel() })
 }
}

public enum HermesMeetingAgent {
 public static func executable(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
  var candidates = (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/" + name }
  candidates += [home.appendingPathComponent(".local/bin/" + name).path, "/opt/homebrew/bin/" + name, "/usr/local/bin/" + name, home.appendingPathComponent(".hermes/venv/bin/" + name).path]
  if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return found }
  let installations = home.appendingPathComponent(".hermes/installs")
  let installs = (try? FileManager.default.contentsOfDirectory(at: installations, includingPropertiesForKeys: nil)) ?? []
  var installed: [URL] = []
  for install in installs {
   let environments = (try? FileManager.default.contentsOfDirectory(at: install.appendingPathComponent("environments"), includingPropertiesForKeys: nil)) ?? []
   installed += environments.map { $0.appendingPathComponent("venv/bin/" + name) }.filter { FileManager.default.isExecutableFile(atPath: $0.path) }
  }
  return installed.sorted {
   ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
   ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
  }.first?.path
 }
 public static func extract(_ output: String) throws -> Data {
  let header = output.components(separatedBy: "📝 User Query:").first ?? output
  let counts = try NSRegularExpression(pattern: #"Available tools:\s*(\d+)"#).matches(in: output, range: NSRange(output.startIndex..., in: output))
  guard header.contains("No tools loaded"),
        counts.allSatisfy({ result in Range(result.range(at: 1), in: output).map { output[$0] == "0" } ?? false }),
        let marker = output.range(of: "🎯 FINAL RESPONSE:", options: .backwards),
        let end = output.range(of: "👋 Agent execution completed!", range: marker.upperBound..<output.endIndex) else {
   throw StoreError.database("Hermes 未返回可验证的无工具最终结果")
  }
  let body = output[marker.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
  guard body.hasPrefix("------------------------------") else { throw StoreError.database("Hermes 最终结果格式不支持") }
  let json = String(body.dropFirst(30)).trimmingCharacters(in: .whitespacesAndNewlines)
  guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], Set(object.keys) == ["items"] else {
   throw StoreError.database("Hermes 未返回严格 JSON；未生成草稿")
  }
  return Data(json.utf8)
 }
 public static func analyze(prompt: String, directory: URL, timeout: Double = 120) async throws -> Data {
  guard let hermes = executable("hermes"), let agent = executable("hermes-agent") else { throw StoreError.database("未找到已安装的 Hermes / hermes-agent") }
  let help = try await MeetingProcess().run(executable: agent, arguments: ["--help"], directory: directory, timeout: 10)
  guard ["--query", "--model", "--base-url", "--enabled-toolsets", "--max-turns"].allSatisfy(help.contains) else {
   throw StoreError.database("已安装 Hermes 不支持所需公共单次运行接口")
  }
  let configuration = try await MeetingProcess().run(executable: hermes, arguments: ["config", "get", "model"], directory: directory, timeout: 10)
  var values: [String: String] = [:]
  for line in configuration.components(separatedBy: .newlines) {
   let parts = line.split(separator: ":", maxSplits: 1)
   if parts.count == 2 { values[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces) }
  }
  guard let model = values["default"], !model.isEmpty, let endpoint = values["base_url"],
        let url = URL(string: endpoint), ["http", "https"].contains(url.scheme ?? ""), url.user == nil, url.password == nil else {
   throw StoreError.database("Hermes 公共模型配置缺少 model/default 或 base_url；请检查既有配置")
  }
  let output = try await MeetingProcess().run(executable: agent, arguments: ["--enabled-toolsets", "none", "--max-turns", "1", "--model", model, "--base-url", endpoint, "--query", prompt], directory: directory, timeout: timeout)
  try Task.checkCancellation()
  return try extract(output)
 }
}
