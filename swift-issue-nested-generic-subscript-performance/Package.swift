// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "NestedGenericPerformance",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NestedGenericPerformance", targets: ["NestedGenericPerformance"]),
        .executable(name: "Benchmark", targets: ["Benchmark"]),
    ],
    targets: [
        .target(name: "NestedGenericPerformance"),
        .executableTarget(name: "Benchmark"),
    ],
    swiftLanguageModes: [.v6]
)
