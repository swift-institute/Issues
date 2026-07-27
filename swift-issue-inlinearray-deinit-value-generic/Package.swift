// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "InlineArrayDeinitBug",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ContainerLib", targets: ["ContainerLib"]),
    ],
    targets: [
        .target(name: "ContainerLib"),
        .testTarget(name: "ContainerTests", dependencies: ["ContainerLib"]),
    ],
    swiftLanguageModes: [.v6]
)
