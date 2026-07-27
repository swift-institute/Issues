// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "EmitModuleBug",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EmitModuleBug", targets: ["EmitModuleBug"]),
    ],
    targets: [
        .target(
            name: "EmitModuleBug",
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
