import Foundation
import CryptoKit
import Darwin

public struct SourceCredential: Identifiable, Sendable {
 public var id: String { name }
 public let name: String
 public let tokenFile: URL
 public let alias: String
 public let project: String
}
public extension Store {
 /// Registration creates an Ed25519 keypair. Only the public key is stored in SQLite;
 /// the private key is written once to a 0600 file outside the database.
 func registerSource(_ rawName: String, project: String = "", alias: String = "", tokenFile: URL) throws -> SourceCredential {
  let name = try title(rawName), aliasValue = alias.isEmpty ? "" : try title(alias)
  guard name.utf8.count <= 64, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { throw StoreError.database("来源名只允许字母、数字、- 和 _") }
  guard project.isEmpty == aliasValue.isEmpty else { throw StoreError.database("项目与别名须同时指定") }
  if !project.isEmpty { guard try projects().contains(where: { $0.id == project }) else { throw StoreError.missing } }
  try integrationSchema()
  let key = Curve25519.Signing.PrivateKey()
  let privateToken = key.rawRepresentation.base64EncodedString()
  let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
  _ = try query("CREATE TABLE IF NOT EXISTS sources(source TEXT PRIMARY KEY,token_hash TEXT NOT NULL,created TEXT NOT NULL,last_seen TEXT)")
  let directory = tokenFile.deletingLastPathComponent()
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  let fd = open(tokenFile.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
  guard fd >= 0 else { throw StoreError.database("凭据路径已存在或无法创建；请选择新的文件路径") }
  defer { close(fd) }
  do {
   let bytes = Data((privateToken + "\n").utf8)
   let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
   guard written == bytes.count, fsync(fd) == 0 else { throw StoreError.database("写入凭据失败") }
   _ = try query("BEGIN IMMEDIATE")
   do {
    _ = try query("INSERT INTO sources(source,token_hash,created) VALUES(?,?,?) ON CONFLICT(source) DO UPDATE SET token_hash=excluded.token_hash", [name, publicKey, ISO8601DateFormatter().string(from: Date())])
    if !project.isEmpty { try bind(source: name, alias: aliasValue, project: project) }
    _ = try query("COMMIT")
   } catch { _ = try? query("ROLLBACK"); throw error }
  } catch { try? FileManager.default.removeItem(at: tokenFile); throw error }
  return SourceCredential(name: name, tokenFile: tokenFile, alias: aliasValue, project: project)
 }
 func setProjectCreationPermission(source: String, allowed: Bool) throws {
  try integrationSchema()
  guard !(try query("SELECT source FROM sources WHERE source=?", [source])).isEmpty else { throw StoreError.missing }
  _ = try query("INSERT INTO source_capabilities(source,create_projects) VALUES(?,?) ON CONFLICT(source) DO UPDATE SET create_projects=excluded.create_projects", [source, allowed ? "1" : "0"])
 }
 func verify(source: String, message: Data, signature: String) throws -> Bool {
  try integrationSchema()
  _ = try query("CREATE TABLE IF NOT EXISTS sources(source TEXT PRIMARY KEY,token_hash TEXT NOT NULL,created TEXT NOT NULL,last_seen TEXT)")
  guard let encoded = try query("SELECT token_hash FROM sources WHERE source=?", [source]).first?.first,
        let publicData = Data(base64Encoded: encoded),
        let signatureData = Data(base64Encoded: signature),
        let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData) else { return false }
  return key.isValidSignature(signatureData, for: message)
 }
 func markSeen(_ source: String) throws { _ = try query("UPDATE sources SET last_seen=? WHERE source=?", [ISO8601DateFormatter().string(from: Date()), source]) }
}
