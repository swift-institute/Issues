// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CopyToBorrowBug",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "BugLib",
            path: "Sources/BugLib"
        ),
        .executableTarget(
            name: "BugTest",
            dependencies: ["BugLib"],
            path: "Sources/BugTest"
        ),
    ]
)
