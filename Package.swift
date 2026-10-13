// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MijiaBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MijiaBarApp", targets: ["MijiaBarApp"]),
        .executable(name: "mijiabar", targets: ["mijiabar"]),
    ],
    targets: [
        .target(name: "MijiaCore"),
        .executableTarget(name: "MijiaBarApp", dependencies: ["MijiaCore"]),
        .executableTarget(name: "mijiabar", dependencies: ["MijiaCore"]),
        .testTarget(name: "MijiaCoreTests", dependencies: ["MijiaCore"]),
    ]
)
