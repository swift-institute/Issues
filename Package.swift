// swift-tools-version: 6.3

import PackageDescription

// MARK: - Swift Institute Issues
//
// Each `swift-issue-*` subdirectory holds the source files for one minimum
// reproducer of a Swift toolchain or compiler bug, together with a README
// documenting the bug, its filing status, affected toolchains, and any
// known workaround. The targets below register each issue's sources for
// CI via the swift-institute universal reusable workflow at
// `.github/workflows/ci.yml`.
//
// CI semantics for an issue reproducer differ from production-package CI:
// **a permanently-failing platform leg IS the bug's running evidence**.
// When the upstream fix lands and the affected leg flips green, that is
// the signal to close the issue and remove (or convert to regression
// fixture) the reproducer.
//
// To send a single reproducer to swiftlang/swift, the reporter extracts
// the sub-directory + the relevant target slice from this file into a
// standalone repo or a single-file `swiftc -O` invocation.

let package = Package(
    name: "Issues",
    targets: [

        // MARK: - swift-issue-pointer-arithmetic-linux-miscompile
        //
        // Linux release-mode codegen miscompile: a `.pointee` read after a
        // user-authored `+`/`-` operator overload wrapping `.advanced(by:)`
        // returns the value at the wrong address. Affects Swift 6.3 stable
        // and 6.4-dev nightly Linux release builds; macOS, Windows, and
        // Linux debug all pass.
        .target(
            name: "PointerArithmeticLinuxMiscompile",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/Sources/PointerArithmetic"
        ),
        .testTarget(
            name: "PointerArithmeticLinuxMiscompileTests",
            dependencies: ["PointerArithmeticLinuxMiscompile"],
            path: "swift-issue-pointer-arithmetic-linux-miscompile/Tests/PointerArithmeticTests"
        )
    ],
    swiftLanguageModes: [.v6]
)

// Bisecting affine-primitives swiftSettings to find the minimum trigger.
// d938a26 (all 10 settings): bug FIRES on Linux release.
// This commit: only .enableExperimentalFeature("Lifetimes") — hypothesis,
// since the bug shape (release-mode optimizer reordering pointer loads)
// is most naturally an artefact of lifetime analysis.
for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .enableExperimentalFeature("Lifetimes")
    ]
}
