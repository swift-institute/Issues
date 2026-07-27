// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RawLayoutDeinitBug",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ContainerLib", targets: ["ContainerLib"]),
    ],
    targets: [
        .target(name: "ContainerLib"),
        .testTarget(name: "ContainerTests", dependencies: ["ContainerLib"]),
        .executableTarget(name: "SingleModuleTest"),  // Single-module repro (no cross-module)
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
    let existing = target.swiftSettings ?? []
    target.swiftSettings = existing + [
        .enableExperimentalFeature("RawLayout"),
    ]
}
