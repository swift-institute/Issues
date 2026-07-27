// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SILGenPackExpansionCrash",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LibraryA", targets: ["LibraryA"]),
        .library(name: "LibraryB", targets: ["LibraryB"]),
    ],
    targets: [
        .target(name: "LibraryA"),
        .target(name: "LibraryB", dependencies: ["LibraryA"]),
    ],
    swiftLanguageModes: [.v6]
)
