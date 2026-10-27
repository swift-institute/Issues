// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "CopyToBorrowBug",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../swift-foundations/swift-kernel"),
        .package(path: "../swift-foundations/swift-async"),
        .package(path: "../swift-primitives/swift-ownership-primitives"),
        .package(path: "../swift-primitives/swift-buffer-primitives"),
    ],
    targets: [
        .target(
            name: "BugModule",
            dependencies: [
                .product(name: "Kernel", package: "swift-kernel"),
                .product(name: "Async", package: "swift-async"),
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
                .product(name: "Buffer Primitives Core", package: "swift-buffer-primitives"),
            ],
            path: "Sources/BugModule",
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
            ]
        ),
        .executableTarget(
            name: "BugTest",
            dependencies: ["BugModule"],
            path: "Sources/BugTest"
        ),
    ]
)
