// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "actor-state-inline-fallback-repro",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "actor-state-inline-fallback-repro"
        )
    ]
)
