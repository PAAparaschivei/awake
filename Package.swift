// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Awake",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Awake", targets: ["Awake"])],
    targets: [
        .target(name: "AwakeCore"),
        .executableTarget(name: "Awake", dependencies: ["AwakeCore"]),
        .testTarget(name: "AwakeCoreTests", dependencies: ["AwakeCore"]),
    ]
)
