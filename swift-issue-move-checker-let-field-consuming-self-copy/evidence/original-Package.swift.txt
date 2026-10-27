// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "sequence-map-builder-consuming-bug",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "sequence-map-builder-consuming-bug",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableExperimentalFeature("LifetimeDependence"),
                .enableExperimentalFeature("Lifetimes"),
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
            ]
        )
    ]
)
