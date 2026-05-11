// swift-tools-version: 6.3

import PackageDescription

// MARK: - Swift Institute Issues
//
// Each `swift-issue-*` subdirectory holds the source for one minimum
// reproducer of a Swift toolchain or compiler bug, plus a README
// documenting the bug, its upstream-filing status, affected toolchains,
// and any known workaround.
//
// Per-issue layout (steady-state pattern, set by the
// pointer-arithmetic-linux-miscompile precedent — see top-level
// README.md "Per-Issue Convention" for the full spec):
//
//   swift-issue-<topic>/
//     ├── README.md
//     ├── INVESTIGATION-ARC.md      (if a multi-round investigation preceded the filing)
//     ├── Tests/Reproducer.swift     ← Swift Testing harness with `withKnownIssue` flip semantics
//     ├── Sources/Reproducer/        ← standalone executable repro + exit-code probe
//     └── evidence/                  (optional, for investigations that produced bisection artifacts)
//
// Each issue declares EXACTLY TWO SwiftPM targets:
//   • one testTarget    — wraps the repro in withKnownIssue("swiftlang/swift#NNNN", when: ...)
//                         Green on platforms where the bug fires;
//                         flips red the moment upstream lands a fix —
//                         that flip is the detection signal.
//   • one executableTarget — same repro as a standalone with
//                            `exit(0 / 1)` per expected behavior. Covers
//                            codegen surfaces that SwiftPM `swift test`
//                            masks (e.g., the macOS standalone case for #77558).

let package = Package(
    name: "Issues",
    targets: [

        // MARK: - swift-issue-pointer-arithmetic-linux-miscompile
        //
        // swiftlang/swift#77558 — pointer arithmetic release-mode
        // miscompile. ≥2 chained `.advanced(by:)` calls on
        // UnsafeMutablePointer<Int> with at least one negative offset
        // misload at `-O` / `-Osize`. Cross-platform (macOS arm64 +
        // Linux x86_64); fixed on 6.4-dev nightly-main.

        // Target names match the issue directory so `swift test --filter
        // <issue-dir-underscored>` selects exactly this issue's tests via
        // substring match on the module-name prefix. Executable target
        // adds a `-Repro` suffix to differentiate the standalone binary.

        .testTarget(
            name: "swift-issue-pointer-arithmetic-linux-miscompile-Tests",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/Tests"
        ),

        .executableTarget(
            name: "swift-issue-pointer-arithmetic-linux-miscompile-Repro",
            path: "swift-issue-pointer-arithmetic-linux-miscompile/Sources/Reproducer"
        ),
    ],
    swiftLanguageModes: [.v6]
)
