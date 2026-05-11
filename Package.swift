// swift-tools-version: 6.3

import PackageDescription

// MARK: - Swift Institute Issues
//
// Each `swift-issue-*` subdirectory holds the source files for one minimum
// reproducer of a Swift toolchain or compiler bug, together with a README
// documenting the bug, its filing status, affected toolchains, and any
// known workaround.
//
// Pattern: where an issue is gated by a single SwiftPM `swiftSettings`
// feature, register a TEST TARGET PER CANDIDATE feature plus one control
// target with no settings. All targets share byte-identical source. CI
// then runs every target side-by-side; on the affected platform, exactly
// the target carrying the load-bearing feature is red — uniqueness proof.

let package = Package(
    name: "Issues",
    targets: [

        // MARK: - swift-issue-pointer-arithmetic-linux-miscompile
        //
        // Linux release-mode codegen miscompile: a `.pointee` read after a
        // user-authored `+`/`-` operator overload wrapping `.advanced(by:)`
        // returns the value at the wrong address. The bug was first
        // observed in swift-affine-primitives, which had 10 swiftSettings
        // enabled per the ecosystem-wide feature flags. Bisection landed
        // on `.enableExperimentalFeature("Lifetimes")` as a sufficient
        // single trigger; the targets below verify uniqueness by running
        // each candidate setting in isolation against the same source.
        //
        // Expected results on Linux 6.3 release / 6.4-dev nightly release:
        //   WithLifetimes                       — FAILS  (known trigger)
        //   Every other With* target            — passes (control by feature)
        //   Control (no swiftSettings)          — passes (control proper)
        //
        // On macOS / Windows / Linux debug: all targets pass.

        // The known trigger.
        .testTarget(
            name: "WithLifetimes",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithLifetimes",
            swiftSettings: [.enableExperimentalFeature("Lifetimes")]
        ),

        // Pure control: zero swiftSettings.
        .testTarget(
            name: "Control",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/Control"
        ),

        // The other 9 settings from affine-primitives, each in isolation.
        .testTarget(
            name: "WithStrictMemorySafety",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithStrictMemorySafety",
            swiftSettings: [.strictMemorySafety()]
        ),

        .testTarget(
            name: "WithExistentialAny",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithExistentialAny",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),

        .testTarget(
            name: "WithInternalImportsByDefault",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithInternalImportsByDefault",
            swiftSettings: [.enableUpcomingFeature("InternalImportsByDefault")]
        ),

        .testTarget(
            name: "WithMemberImportVisibility",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithMemberImportVisibility",
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        .testTarget(
            name: "WithNonisolatedNonsendingByDefault",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithNonisolatedNonsendingByDefault",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),

        .testTarget(
            name: "WithLifetimeDependenceExperimental",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithLifetimeDependenceExperimental",
            swiftSettings: [.enableExperimentalFeature("LifetimeDependence")]
        ),

        .testTarget(
            name: "WithSuppressedAssociatedTypes",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithSuppressedAssociatedTypes",
            swiftSettings: [.enableExperimentalFeature("SuppressedAssociatedTypes")]
        ),

        .testTarget(
            name: "WithInferIsolatedConformances",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithInferIsolatedConformances",
            swiftSettings: [.enableUpcomingFeature("InferIsolatedConformances")]
        ),

        .testTarget(
            name: "WithLifetimeDependenceUpcoming",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithLifetimeDependenceUpcoming",
            swiftSettings: [.enableUpcomingFeature("LifetimeDependence")]
        ),

        // Disambiguator target. Differs from all sibling targets only by
        // the absence of `unsafe` keyword markers in its source. If this
        // target passes on Linux release while every other target fails,
        // the `unsafe` keyword itself is the load-bearing trigger — none
        // of the swiftSettings are.
        .testTarget(
            name: "WithoutUnsafe",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithoutUnsafe"
        )
    ],
    swiftLanguageModes: [.v6]
)
