// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "PropertyViewTagConstraint",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PropertyLib", targets: ["PropertyLib"]),
        .library(name: "SequenceLib", targets: ["SequenceLib"]),
        .library(name: "CollectionLib", targets: ["CollectionLib"]),
    ],
    targets: [
        .target(name: "PropertyLib"),
        .target(name: "SequenceLib", dependencies: ["PropertyLib"]),
        .target(name: "CollectionLib", dependencies: ["PropertyLib", "SequenceLib"]),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
    let existing = target.swiftSettings ?? []
    target.swiftSettings = existing + [
        .enableExperimentalFeature("Lifetimes"),
    ]
}
