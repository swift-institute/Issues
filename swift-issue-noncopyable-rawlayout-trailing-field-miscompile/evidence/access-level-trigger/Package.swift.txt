// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "rawlayout-test",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "main", swiftSettings: [
            .enableExperimentalFeature("RawLayout"),
        ])
    ],
    swiftLanguageModes: [.v6]
)
