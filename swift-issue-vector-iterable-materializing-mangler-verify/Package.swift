// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Vector Iterable Materializing Mangler Verify",
    targets: [
        .target(
            name: "M",
            path: ".",
            sources: ["defining.swift"],
            swiftSettings: [
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
                .enableExperimentalFeature("Lifetimes"),
                .unsafeFlags(["-whole-module-optimization"]),
            ]
        ),
        .target(
            name: "N",
            dependencies: ["M"],
            path: ".",
            sources: ["consumer.swift"],
            swiftSettings: [
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
                .enableExperimentalFeature("Lifetimes"),
                .unsafeFlags(["-whole-module-optimization"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
