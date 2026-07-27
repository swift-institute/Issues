// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-nested-copyable-extension-bug",
    products: [
        .library(
            name: "NestedCopyableExtensionBug",
            targets: ["NestedCopyableExtensionBug"]
        ),
    ],
    targets: [
        .target(name: "NestedCopyableExtensionBug"),
    ]
)
