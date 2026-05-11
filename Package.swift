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
// feature, register TWO test targets that share byte-identical sources
// and differ only in the swiftSettings list — one demonstrates the bug
// firing, the other is the control. CI then runs both side-by-side and
// the diff IS the demonstration.
//
// CI semantics for an issue reproducer differ from production-package CI:
// **a permanently-failing platform leg IS the bug's running evidence**.
// When the upstream fix lands and the affected leg flips green, that is
// the signal to close the issue and remove (or convert to regression
// fixture) the reproducer.

let package = Package(
    name: "Issues",
    targets: [

        // MARK: - swift-issue-pointer-arithmetic-linux-miscompile
        //
        // Linux release-mode codegen miscompile: a `.pointee` read after a
        // user-authored `+`/`-` operator overload wrapping `.advanced(by:)`
        // returns the value at the wrong address. Fires only when the
        // enclosing target has `.enableExperimentalFeature("Lifetimes")`
        // enabled. Affects Swift 6.3 stable and 6.4-dev nightly Linux
        // release builds; macOS, Windows, and Linux debug all pass.

        // WithLifetimes: enables `.Lifetimes` — bug fires on Linux release.
        .testTarget(
            name: "WithLifetimes",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithLifetimes",
            swiftSettings: [.enableExperimentalFeature("Lifetimes")]
        ),

        // WithoutLifetimes: no swiftSettings — control. Passes on all
        // platforms. Source file is byte-identical to WithLifetimes'.
        .testTarget(
            name: "WithoutLifetimes",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/WithoutLifetimes"
        )
    ],
    swiftLanguageModes: [.v6]
)
