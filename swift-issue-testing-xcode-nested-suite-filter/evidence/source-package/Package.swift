// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "swift-issue-testing-xcode-nested-suite-filter",
    platforms: [.macOS(.v26)],
    targets: [
        .testTarget(name: "Tests"),
    ],
    swiftLanguageModes: [.v6]
)
