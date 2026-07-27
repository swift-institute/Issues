// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SILVerifierReadEscapable",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SILVerifierReadEscapable", targets: ["SILVerifierReadEscapable"]),
    ],
    targets: [
        .target(name: "SILVerifierReadEscapable")
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
    let existing = target.swiftSettings ?? []
    target.swiftSettings = existing + [
        .enableExperimentalFeature("Lifetimes"),
    ]
}
