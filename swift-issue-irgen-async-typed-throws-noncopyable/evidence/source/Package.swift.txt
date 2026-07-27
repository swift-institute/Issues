// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "IRGenCrash",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "IRGenCrash", targets: ["IRGenCrash"]),
    ],
    targets: [
        .target(name: "IRGenCrash")
    ],
    swiftLanguageModes: [.v6]
)
