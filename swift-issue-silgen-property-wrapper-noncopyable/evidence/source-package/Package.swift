// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SILGenCrash",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Lib", targets: ["Lib"]),
    ],
    targets: [
        .target(name: "Lib"),
        .testTarget(name: "Tests", dependencies: ["Lib"]),
    ],
    swiftLanguageModes: [.v6]
)
