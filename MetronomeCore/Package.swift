// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MetronomeCore",
    platforms: [.watchOS(.v10), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MetronomeCore", targets: ["MetronomeCore"])
    ],
    targets: [
        .target(name: "MetronomeCore"),
        .testTarget(name: "MetronomeCoreTests", dependencies: ["MetronomeCore"])
    ]
)
