// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "TypedThrowsAutoclosureInference",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TypedThrowsAutoclosureInference", targets: ["TypedThrowsAutoclosureInference"]),
    ],
    targets: [
        .target(name: "TypedThrowsAutoclosureInference")
    ],
    swiftLanguageModes: [.v6]
)
