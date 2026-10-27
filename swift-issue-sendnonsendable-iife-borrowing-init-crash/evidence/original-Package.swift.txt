// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "sendnonsendable-iife-borrowing-init-crash",
    platforms: [
        .macOS(.v26),
    ],
    targets: [
        .target(
            name: "ReproLib",
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
            ]
        ),
        .executableTarget(
            name: "sendnonsendable-iife-borrowing-init-crash",
            dependencies: ["ReproLib"],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
