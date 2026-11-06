import SwiftUI

/// Shared by the production connection center and the memory-only native render fixture.
struct MCPAuthorizationOptions: View {
 @Binding var allowProjects: Bool
 @Binding var allowTasks: Bool
 @Binding var includeProject: Bool
 let hasProject: Bool
 var body: some View {
  VStack(alignment: .leading, spacing: 4) {
   option("允许创建新项目", detail: "默认关闭。新项目自动绑定此身份，并允许上报动态。", value: $allowProjects)
   option("允许创建待办", detail: "单独授权：应用于本次选择的项目，以及以后获准创建的新项目。", value: $allowTasks)
   if hasProject {
    option("同时授权当前项目", detail: "允许查询与上报动态；待办权限按上方选择保存。", value: $includeProject)
   } else {
    Text("当前没有项目。可仅授权创建新项目，随后让智能体创建。").font(.system(size: 11)).foregroundStyle(.secondary)
   }
  }
 }
 private func option(_ title: String, detail: String, value: Binding<Bool>) -> some View {
  Button { value.wrappedValue.toggle() } label: {
   HStack(spacing: 10) {
    Image(systemName: value.wrappedValue ? "checkmark.square.fill" : "square").foregroundStyle(value.wrappedValue ? Desk.green : .secondary).font(.system(size: 16))
    VStack(alignment: .leading, spacing: 4) {
     Text(title).font(.system(size: 13.5)).foregroundStyle(.primary)
     Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
    }
    Spacer(minLength: 0)
   }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
    .contentShape(Rectangle())
  }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value.wrappedValue ? "已勾选" : "未勾选")
 }
}
