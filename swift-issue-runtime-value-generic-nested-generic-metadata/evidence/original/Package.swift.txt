// swift-tools-version: 6.3.3
import PackageDescription

let package = Package(
    name: "value-generic-nested-generic-metadata-crash",
    targets: [
        .executableTarget(name: "value-generic-nested-generic-metadata-crash")
    ],
    swiftLanguageModes: [.v6]
)
