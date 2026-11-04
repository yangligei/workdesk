import Foundation
import Darwin

/// Bounded regular-file reads use O_NOFOLLOW; protocol directories must not be symlinks.
public enum InboxFiles {
 public static func directory(_ url: URL) throws {
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
  guard values.isSymbolicLink != true, values.isDirectory == true else { throw StoreError.database("收件箱目录不可为符号链接") }
 }
 public static func read(_ url: URL, limit: Int = 65536) throws -> Data {
  let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
  guard fd >= 0 else { throw StoreError.database("无法安全打开事件文件") }
  defer { close(fd) }
  var info = stat()
  guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= limit else { throw StoreError.database("拒绝非普通文件或超大文件") }
  var bytes = [UInt8](repeating: 0, count: limit + 1)
  var total = 0
  while total < bytes.count {
   let available = bytes.count - total
   let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: total), available) }
   if count < 0 { if errno == EINTR { continue }; throw StoreError.database("读取事件失败") }
   if count == 0 { break }; total += count
  }
  guard total <= limit else { throw StoreError.database("事件文件过大") }
  return Data(bytes.prefix(total))
 }
}
public actor EventInbox {
 public let root: URL
 private let store: Store
 private var draining = false
 private var pending = false
 public init(root: URL, store: Store) throws {
  self.root = root; self.store = store
  try InboxFiles.directory(root)
  for name in ["inbox", "receipts"] { try InboxFiles.directory(root.appendingPathComponent(name)) }
 }
 public nonisolated static func submit(_ event: ProgressEvent, root: URL) throws -> String {
  try InboxFiles.directory(root)
  let directory = root.appendingPathComponent("inbox")
  try InboxFiles.directory(directory)
  let data = try JSONEncoder().encode(event)
  guard data.count <= 65536 else { throw StoreError.database("事件超过 64 KiB") }
  let name = UUID().uuidString + ".json"
  try data.write(to: directory.appendingPathComponent(name), options: .atomic)
  return name
 }
 public func drain() async throws {
  guard !draining else { pending = true; return }
  draining = true; defer { draining = false }
  repeat {
   pending = false
   try await sweep()
  } while pending
 }
 private func sweep() async throws {
  let directory = root.appendingPathComponent("inbox")
  try InboxFiles.directory(directory)
  try InboxFiles.directory(root.appendingPathComponent("receipts"))
  for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "json" {
   let receipt: Receipt
   let event: ProgressEvent
   do { event = try JSONDecoder().decode(ProgressEvent.self, from: InboxFiles.read(url)) }
   catch {
    let rejected = Receipt(eventID: "", outcome: "rejected", detail: "无效文件：" + error.localizedDescription)
    try JSONEncoder().encode(rejected).write(to: root.appendingPathComponent("receipts/" + url.lastPathComponent), options: .atomic)
    try FileManager.default.removeItem(at: url); continue
   }
   // Storage failures retain input for retry. A commit followed by receipt failure is safe to replay.
   receipt = try await store.receive(event)
   try JSONEncoder().encode(receipt).write(to: root.appendingPathComponent("receipts/" + url.lastPathComponent), options: .atomic)
   try FileManager.default.removeItem(at: url)
  }
 }
}

/// Directory notifications plus startup sweep; no timer or resident helper.
public final class InboxWatcher {
 private let source: DispatchSourceFileSystemObject
 public init(root: URL, directoryName: String = "inbox", changed: @escaping @Sendable () -> Void) throws {
  let directory = root.appendingPathComponent(directoryName)
  try InboxFiles.directory(directory)
  let fd = open(directory.path, O_EVTONLY | O_NOFOLLOW)
  guard fd >= 0 else { throw StoreError.database("无法监视收件箱") }
  source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: DispatchQueue.global(qos: .utility))
  source.setEventHandler(handler: changed)
  source.setCancelHandler { close(fd) }
  source.resume()
  changed()
 }
 deinit { source.cancel() }
}
