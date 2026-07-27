// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SuiteDiscoveryGenericSpecialization",
    platforms: [.macOS(.v26)],
    targets: [
        .testTarget(name: "DiscoveryTests")
    ],
    swiftLanguageModes: [.v6]
)
