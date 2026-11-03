// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Workdesk", platforms: [.macOS(.v13)], products: [.executable(name: "Workdesk", targets: ["Workdesk"])], targets: [.systemLibrary(name: "CSQLite"), .target(name: "WorkdeskCore", dependencies: ["CSQLite"]), .executableTarget(name: "Workdesk", dependencies: ["WorkdeskCore"]), .executableTarget(name: "WorkdeskCLI", dependencies: ["WorkdeskCore"]), .executableTarget(name: "CoreChecks", dependencies: ["WorkdeskCore"], path: "Checks"), .testTarget(name: "WorkdeskCoreTests", dependencies: ["WorkdeskCore"])])
