// swift-tools-version:5.9
import PackageDescription

// 按 Swift 6 的并发规则检查（数据竞争以警告形式出现），为切换到 Swift 6 语言模式做准备
let strict: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
    name: "MijiaBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MijiaBarApp", targets: ["MijiaBarApp"]),
        .executable(name: "mijiabar", targets: ["mijiabar"]),
    ],
    targets: [
        .target(name: "MijiaCore", swiftSettings: strict),
        .executableTarget(name: "MijiaBarApp", dependencies: ["MijiaCore"], swiftSettings: strict),
        .executableTarget(name: "mijiabar", dependencies: ["MijiaCore"], swiftSettings: strict),
        .testTarget(name: "MijiaCoreTests", dependencies: ["MijiaCore"], swiftSettings: strict),
    ]
)
