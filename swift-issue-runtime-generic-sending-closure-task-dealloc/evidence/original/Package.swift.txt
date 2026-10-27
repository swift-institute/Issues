// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "silgen-thunk-noncopyable-sending-capture",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    targets: [
        .executableTarget(
            name: "silgen-thunk-noncopyable-sending-capture",
            path: "Sources",
            swiftSettings: [
                .strictMemorySafety(),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableExperimentalFeature("LifetimeDependence"),
                .enableExperimentalFeature("Lifetimes"),
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
