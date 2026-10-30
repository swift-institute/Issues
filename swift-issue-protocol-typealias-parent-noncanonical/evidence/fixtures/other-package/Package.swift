// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BaseModule",
    products: [
        .library(name: "BaseModule", targets: ["BaseModule"]),
    ],
    targets: [
        .target(name: "BaseModule")
    ],
    swiftLanguageModes: [.v6]
)

// Add compiler flags matching swift-whatwg-html
for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
    let existing = target.swiftSettings ?? []
    target.swiftSettings = existing + [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
