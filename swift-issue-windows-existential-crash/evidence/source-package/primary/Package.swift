// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ExistentialCrash",
    products: [
        .library(name: "ExistentialCrash", targets: ["ExistentialCrash"]),
    ],
    dependencies: [
        // Base module in a SEPARATE PACKAGE - this is required to trigger the bug
        .package(url: "https://github.com/coenttb/swift-issue-windows-existential-crash-other-package", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "ExistentialCrash",
            dependencies: [
                .product(name: "BaseModule", package: "swift-issue-windows-existential-crash-other-package"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

// Add compiler flags matching swift-html-rendering
for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
    let existing = target.swiftSettings ?? []
    target.swiftSettings = existing + [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
