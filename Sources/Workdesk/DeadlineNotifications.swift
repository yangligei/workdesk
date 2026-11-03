import Foundation
import UserNotifications
import Security
import WorkdeskCore

@MainActor final class DeadlineNotifications: ObservableObject {
 @Published var status = "尚未检查通知权限"
 private var reconciling = false
 private var latest: ([Project], [String: [WorkTask]])?
 private var disabled: Bool { ProcessInfo.processInfo.environment["WORKDESK_DISABLE_NOTIFICATIONS"] == "1" }
 private var supported: Bool {
  var code: SecCode?
  guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
  var staticCode: SecStaticCode?
  guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
  var info: CFDictionary?
  guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
        let flags = (info as? [String: Any])?[kSecCodeInfoFlags as String] as? NSNumber else { return false }
  return flags.uint32Value & 2 == 0 // CS_ADHOC
 }
 func request() async {
  guard !disabled else { status = "隔离测试：系统通知已禁用"; return }
  guard supported else { status = "本地 ad-hoc 或未签名构建不支持可靠系统通知；请使用应用内截止提示。"; return }
  do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
  catch { status = "无法申请通知：\(error.localizedDescription)"; return }
  if let latest { await reconcile(latest.0, tasks: latest.1) }
 }
 func reconcile(_ projects: [Project], tasks: [String: [WorkTask]]) async {
  latest = (projects, tasks)
  guard !disabled else { status = "隔离测试：系统通知已禁用"; return }
  guard supported else { status = "本地 ad-hoc 或未签名构建：仅应用内截止提示，未申请系统通知。"; return }
  guard !reconciling else { return }
  reconciling = true
  repeat {
   guard let snapshot = latest else { break }; latest = nil
   let center = UNUserNotificationCenter.current()
   let settings = await center.notificationSettings()
   let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
   let plan = allowed ? DeadlinePlan.reminders(projects: snapshot.0, tasks: snapshot.1, now: Date()) : []
   let pending = await center.pendingNotificationRequests()
   let wanted = Set(plan.map(\.id))
   center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("ddl.") && !wanted.contains($0.identifier) }.map(\.identifier))
   let delivered = await center.deliveredNotifications()
   center.removeDeliveredNotifications(withIdentifiers: delivered.filter { !wanted.contains($0.request.identifier) && $0.request.identifier.hasPrefix("ddl.") }.map { $0.request.identifier })
   status = allowed ? "系统通知已授权 · 最多安排最近 60 条" : (settings.authorizationStatus == .denied ? "通知被拒绝；请在系统设置中允许。逾期仍在应用内显示。" : "未授权；点击启用后由系统询问")
   for item in plan {
    let content = UNMutableNotificationContent(); content.title = item.title; content.body = "项目截止时间即将到达，请查看工作进度台。"; content.sound = .default
    // Stable identifiers replace requests on rename and prevent duplicates.
    let interval = item.fire.timeIntervalSinceNow
    guard interval > 0 else { continue }
    do { try await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false))) }
    catch { status = "通知安排失败：\(error.localizedDescription)；请查看应用内截止时间" }
   }
   if latest == nil { latest = snapshot; break }
  } while true
  reconciling = false
 }
}
