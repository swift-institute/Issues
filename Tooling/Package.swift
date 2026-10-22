// swift-tools-version: 6.3

import PackageDescription

// MARK: - Toolchain report tooling
//
// The two tools behind the upstream-readiness procedure
// (UPSTREAM-PROCEDURE.md at the repository root):
//
//   issue-reduce  — mechanical reducer for a single-file toolchain failure.
//                   Deletes and simplifies syntax and command flags, keeping a
//                   step only while the original signature (assertion text,
//                   innermost pretty-stack phase, top stack frames) still
//                   appears; stops at a fixed point.
//   issue-check   — validates an issue against the "Toolchain bug" form and,
//                   with --run, reproduces it on the stated toolchain. It is
//                   the gate for the `upstream-ready` and `upstream-filed`
//                   labels.
//
// This package is separate from the root Issues package so the reproducer
// convention there (exactly two targets per issue, no dependencies) is kept.

let package = Package(
    name: "Tooling",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "issue-reduce", targets: ["issue-reduce"]),
        .executable(name: "issue-check", targets: ["issue-check"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
    ],
    targets: [
        .target(
            name: "Toolchain Report",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(name: "issue-reduce", dependencies: ["Toolchain Report"]),
        .executableTarget(name: "issue-check", dependencies: ["Toolchain Report"]),
        .testTarget(name: "Toolchain Report Tests", dependencies: ["Toolchain Report"]),
    ],
    swiftLanguageModes: [.v6]
)
