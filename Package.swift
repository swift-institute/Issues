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

    // The macOS platform minimum mirrors the swift-primitives
    // ecosystem's deployment target (`.v26`) so that targets depending
    // on `swift-tagged-primitives` / `swift-ordinal-primitives` /
    // `swift-cardinal-primitives` resolve cleanly. Targets that do NOT
    // depend on swift-primitives products (e.g.
    // `swift-issue-pointer-arithmetic-linux-miscompile-*`) are
    // unaffected on Linux/Windows where the `platforms:` minimum is
    // not consulted.
    platforms: [.macOS(.v26)],

    // External dependencies are unusual for the Issues repo — the
    // per-issue convention prefers bare-`swiftc` single-file
    // reproducers per [ISSUE-002]. They are accommodated for issues
    // that are NOT reducible to bare `swiftc`. Currently the only
    // such issue is the Tagged + Atomic + `~Copyable` metadata
    // SIGSEGV, which is specific to the production
    // `Tagged_Primitives.Tagged` symbol's runtime materialization
    // and cannot be reduced to a local-copy reproducer (see
    // `swift-issue-tagged-noncopyable-atomic-metadata-crash/INVESTIGATION-ARC.md`
    // Arc 4 §`[ISSUE-002]`). The three deps below back ONLY that issue's
    // targets — every other issue MUST remain dependency-free.
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-tagged-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-ordinal-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-cardinal-primitives.git", branch: "main"),
    ],

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

        // MARK: - swift-issue-tagged-noncopyable-atomic-metadata-crash
        //
        // swiftlang/swift (pending filing — see PRE-FILING-BUG-REPORT.md
        // in the issue directory) — `Atomic<Tagged<Tag, Ordinal>>.advance(within:)`
        // SIGSEGVs at runtime on Apple Swift 6.3.x (Xcode 26.4.1)
        // because the type-metadata cache stub
        // `__swift_instantiateConcreteTypeFromMangledNameV2` returns
        // null for `Atomic<Tagged_Primitives.Tagged<…>>`. The runtime
        // demangler returns `TypeLookupError("unknown error")` for the
        // symbolic-mangled name's inline-encoded module-identifier
        // fragment referencing the
        // `Tagged_Primitives_Standard_Library_Integration` submodule
        // where the conditional `AtomicRepresentable` conformance lives.
        //
        // Fixed on Swift 6.4-dev nightly `2026-03-16-a` and later.
        //
        // This issue is the sole reason the Issues package declares
        // external `.package(...)` dependencies — the bug is specific
        // to the production `Tagged_Primitives.Tagged` symbol's
        // runtime materialization and cannot be reduced to a
        // local-copy / bare-`swiftc` reproducer. The reproducer
        // therefore preserves `import Tagged_Primitives` per
        // [ISSUE-002]'s "If the issue requires SwiftPM" branch.

        .testTarget(
            name: "swift-issue-tagged-noncopyable-atomic-metadata-crash-Tests",
            dependencies: [
                .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
                .product(name: "Ordinal Primitives", package: "swift-ordinal-primitives"),
                .product(name: "Cardinal Primitives", package: "swift-cardinal-primitives"),
            ],
            path: "swift-issue-tagged-noncopyable-atomic-metadata-crash/Tests"
        ),

        .executableTarget(
            name: "swift-issue-tagged-noncopyable-atomic-metadata-crash-Repro",
            dependencies: [
                .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
                .product(name: "Ordinal Primitives", package: "swift-ordinal-primitives"),
                .product(name: "Cardinal Primitives", package: "swift-cardinal-primitives"),
            ],
            path: "swift-issue-tagged-noncopyable-atomic-metadata-crash/Sources/Reproducer"
        ),
    ],
    swiftLanguageModes: [.v6]
)
