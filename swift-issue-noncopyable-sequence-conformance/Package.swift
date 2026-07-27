// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "NoncopyableSequenceConformance",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Ring", targets: ["Ring"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Ring", dependencies: ["Core"]),
    ],
    swiftLanguageModes: [.v6]
)
