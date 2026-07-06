// swift-tools-version: 6.3
import PackageDescription

// Factor-bisection reducer for the io `__Dictionary.insert` DEBUG/RELEASE SIGSEGV
// (catalog §A9 new site — see ../README.md).
//
// Mirrors the production Registry:
//     Dictionary_Primitives.Dictionary<Kernel.Event.ID, Registration>
// where  Kernel.Event.ID  = Tagged<ISO_9945.Kernel.Event, UInt>   (a real
// `Tagged_Primitives.Tagged`) and Registration: ~Copyable, Sendable.
//
// Each target isolates one factor; run all five and read the exit codes:
//     t0-control            non-Tagged key (UInt) + ~Copyable value  → PASS (exit 0)
//     t1-tagged-copyable    Tagged key + Copyable Int value          → CRASH (139)
//     t2-tagged-noncopyable Tagged key + ~Copyable value             → CRASH (139)
//     t3-closure            t2 + @Sendable closure on a final class   → CRASH (139)
//     t4-actor              t3 + detached cooperative Task            → CRASH (139)
//
// The load-bearing factor is the Tagged KEY forcing the institute
// `__Dictionary`/`__HashIndexed`/`Hash.Entry`/`Buffer.Linear` engine's full
// type metadata. Neither the ~Copyable user value, the Sendable closure, nor
// the actor context is required (t1 crashes straight-line with a Copyable Int).
let package = Package(
    name: "reducer",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-dictionary-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-iso/swift-iso-9945.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-hash-primitives.git", branch: "main"),
    ],
    targets: [
        .executableTarget(name: "t0-control"),
        .executableTarget(name: "t1-tagged-copyable"),
        .executableTarget(name: "t2-tagged-noncopyable"),
        .executableTarget(name: "t3-closure"),
        .executableTarget(name: "t4-actor"),
    ]
)

for target in package.targets {
    target.dependencies = [
        .product(name: "Dictionary Primitives", package: "swift-dictionary-primitives"),
        .product(name: "ISO 9945 Core", package: "swift-iso-9945"),
        .product(name: "Hash Tagged Primitives", package: "swift-hash-primitives"),
    ]
    // Mirror swift-io's ecosystem SwiftSettings — SuppressedAssociatedTypes is
    // the feature whose incomplete-on-6.3 codegen is the §A9 root cause.
    target.swiftSettings = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]
}
