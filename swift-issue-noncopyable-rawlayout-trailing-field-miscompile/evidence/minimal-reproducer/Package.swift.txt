// swift-tools-version: 6.2

import PackageDescription

let commonSettings: [SwiftSetting] = [
    .enableExperimentalFeature("RawLayout"),
    .enableExperimentalFeature("Lifetimes"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .strictMemorySafety(),
]

let bug2Settings: [SwiftSetting] = commonSettings + [
    // Suppress Bug 1 (LLVM verifier) to expose Bug 2 (SIL ownership).
    // Bug 2 does NOT reproduce in isolation — documented here for
    // completeness and to enable future attempts with more context.
    .unsafeFlags(["-Xfrontend", "-disable-llvm-verify"],
                 .when(configuration: .release)),
]

let package = Package(
    name: "rawlayout-minimal-reproducer",
    platforms: [.macOS(.v26)],
    targets: [
        // ── Bug 1: LLVM Verifier Crash (REPRODUCES) ─────────────────────
        // Trigger: 2+ cross-module @_rawLayout+deinit fields in a struct
        .target(
            name: "Bug1Core",
            swiftSettings: commonSettings
        ),
        .target(
            name: "Bug1Middleware",
            dependencies: ["Bug1Core"],
            swiftSettings: commonSettings
        ),
        .executableTarget(
            name: "Bug1Consumer",
            dependencies: ["Bug1Core", "Bug1Middleware"],
            swiftSettings: commonSettings
        ),

        // ── Bug 2: CopyPropagation Ownership Crash (DOES NOT REPRODUCE) ─
        // Included for completeness. Requires full production dep graph.
        .target(
            name: "Bug2PropertyLib",
            dependencies: ["Bug1Core"],
            swiftSettings: bug2Settings
        ),
        .target(
            name: "Bug2Middleware",
            dependencies: ["Bug2PropertyLib"],
            swiftSettings: bug2Settings
        ),
        .executableTarget(
            name: "Bug2Consumer",
            dependencies: ["Bug2PropertyLib", "Bug2Middleware"],
            swiftSettings: bug2Settings
        ),
    ],
    swiftLanguageModes: [.v6]
)
