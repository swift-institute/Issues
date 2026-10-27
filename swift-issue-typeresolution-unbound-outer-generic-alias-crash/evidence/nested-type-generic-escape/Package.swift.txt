// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "nested-type-generic-escape",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "nested-type-generic-escape"
        )
    ]
)
