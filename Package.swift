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
    platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26), .visionOS(.v26)],

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

        // MARK: - swift-issue-borrowing-actor-closure
        //
        // swift-institute/Issues#3 — `swift-frontend` crashes in
        // MoveOnlyTypeEliminator when an actor method captures a `borrowing`
        // class parameter in a non-escaping closure. The triggering source is
        // compiled out of process so the compiler crash does not abort the
        // Issues package build itself.

        .testTarget(
            name: "swift-issue-borrowing-actor-closure-Tests",
            path: "swift-issue-borrowing-actor-closure/Tests"
        ),

        .executableTarget(
            name: "swift-issue-borrowing-actor-closure-Repro",
            path: "swift-issue-borrowing-actor-closure/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),

        // MARK: - swift-issue-irgen-nonthrowing-typed-throws-closure-crash
        //
        // swiftlang/swift#87030 — an assertions-enabled compiler aborts in
        // IRGen when debug information describes an error-result slot for a
        // non-throwing closure converted to a nested-generic typed-throws
        // function. Fixed on main by swiftlang/swift#90789.
        //
        // The compiler-aborting sources are resources compiled out of process.
        // Pre-6.5 assertions toolchains remain known-affected; 6.5+ exercises
        // the merged fix as ordinary regression coverage.

        .testTarget(
            name: "swift-issue-irgen-nonthrowing-typed-throws-closure-crash-Tests",
            path: "swift-issue-irgen-nonthrowing-typed-throws-closure-crash/Tests"
        ),

        .executableTarget(
            name: "swift-issue-irgen-nonthrowing-typed-throws-closure-crash-Repro",
            path: "swift-issue-irgen-nonthrowing-typed-throws-closure-crash/Sources/Reproducer",
            resources: [
                .copy("ConstrainedExtension.swift.txt"),
                .copy("DirectInitialization.swift.txt")
            ]
        ),

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

        // MARK: - swift-issue-noncopyable-rawlayout-trailing-field-miscompile
        //
        // swiftlang/swift (pending filing) — a `~Copyable` type that stores a
        // generic `@_rawLayout(likeArrayOf: Element, count:)` buffer FOLLOWED BY
        // a trailing fixed-size scalar field, with a `deinit` present, makes
        // IRGen emit the synthesized `destroy` / `assignWithTake` value
        // witnesses with an SSA dominance violation (the trailing-field offset
        // `mul stride, capacity` lands in the loop-exit block while `stride` is
        // loaded only inside the loop). `swiftc -O` aborts (signal 6) with the
        // LLVM module verifier "Instruction does not dominate all uses" on
        // every toolchain >= 6.3.1, macOS + Linux. Workaround: declare the
        // scalar field before the buffer.
        //
        // Because the bug aborts the COMPILER, the triggering source cannot be
        // a compiled target (it would abort the whole package build). It ships
        // as the `Crash.swift.txt` resource and both harnesses compile it OUT
        // OF PROCESS via `swiftc -O`, reporting the verifier abort as the
        // signal. The test wraps the probe in `withKnownIssue` (green while the
        // out-of-process build crashes; red on upstream fix).

        .testTarget(
            name: "swift-issue-noncopyable-rawlayout-trailing-field-miscompile-Tests",
            path: "swift-issue-noncopyable-rawlayout-trailing-field-miscompile/Tests"
        ),

        .executableTarget(
            name: "swift-issue-noncopyable-rawlayout-trailing-field-miscompile-Repro",
            path: "swift-issue-noncopyable-rawlayout-trailing-field-miscompile/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),

        // MARK: - swift-issue-functionsignatureopts-generic-typed-throws-error
        //
        // swiftlang/swift#89617 — FunctionSignatureOpts asserts at -O on
        // a generic function whose typed-throws error type carries the function's
        // own abstract type parameter (`func f<T>(…) throws(E<T>)`), with a
        // same-module caller and an eliminable (dead) argument. swift-frontend
        // aborts (signal 6) building the signature-optimized clone: it constructs
        // the indirect typed-error-result SILArgument with the unsubstituted
        // interface type `E<T>` (still carrying the type parameter). On 6.3.1+ the
        // always-on ASSERT(!type.hasTypeParameter()) (SILArgument.cpp:40) fires; on
        // 6.2/6.2.3 (asserts off) the SIL verifier rejects the try_apply error
        // destination. Present on EVERY tested toolchain 6.2 -> 6.5-dev — NOT a 6.3
        // regression, NOT fixed on latest dev. Distinct from #87030 (IRGen, clean on
        // 6.3.2) and its fix #88931 (SILGen/IRGen, not FunctionSignatureOpts).
        //
        // Because the bug aborts the COMPILER, the triggering source ships as the
        // `Crash.swift.txt` resource; both harnesses compile it OUT OF PROCESS via
        // `swiftc -O` and report the abort. The test wraps the probe in
        // `withKnownIssue` (green while it crashes; red on upstream fix). No external
        // dependencies — bare-`swiftc` single-file per [ISSUE-002].

        .testTarget(
            name: "swift-issue-functionsignatureopts-generic-typed-throws-error-Tests",
            path: "swift-issue-functionsignatureopts-generic-typed-throws-error/Tests"
        ),

        .executableTarget(
            name: "swift-issue-functionsignatureopts-generic-typed-throws-error-Repro",
            path: "swift-issue-functionsignatureopts-generic-typed-throws-error/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),

        // MARK: - swift-issue-conditional-extension-typealias-name-capture
        //
        // swiftlang/swift#89684 — bogus `type 'Substrate' does not conform to
        // protocol 'P'` when a conditional extension of a nested generic type
        // declares a member typealias named after an ENCLOSING type's generic
        // parameter. References to that name inside the nested type's
        // declaring context are captured by the conditionally-available
        // member; the compiler evaluates the extension's `where` condition
        // against the open generic argument and rejects valid source at
        // `-typecheck`. Present on 6.3.2 → 6.5-dev. The same member in an
        // UNCONDITIONAL extension (member-shadows-outer baseline) and the
        // same annotation in a separate extension context both compile — see
        // the entry README's inconsistency matrix.
        //
        // Because the bug REJECTS VALID SOURCE, the triggering source cannot
        // be a compiled target (it would fail the whole package build while
        // the bug lives). It ships as the `Reject.swift.txt` resource; both
        // harnesses typecheck it OUT OF PROCESS via `swiftc -typecheck` and
        // report the bogus rejection. The test wraps the probe in
        // `withKnownIssue` (green while it rejects; red on upstream fix). No
        // external dependencies — bare-`swiftc` single-file per [ISSUE-002].

        .testTarget(
            name: "swift-issue-conditional-extension-typealias-name-capture-Tests",
            path: "swift-issue-conditional-extension-typealias-name-capture/Tests"
        ),

        .executableTarget(
            name: "swift-issue-conditional-extension-typealias-name-capture-Repro",
            path: "swift-issue-conditional-extension-typealias-name-capture/Sources/Reproducer",
            resources: [
                .copy("Reject.swift.txt")
            ]
        ),

        // MARK: - swift-issue-extension-table-uint16-datalength-overflow
        //
        // swiftlang/swift#90319 — ExtensionTableInfo serializes the per-base-name
        // extension-table `dataLength` as a uint16_t (Serialization.cpp:239). When a
        // nominal type is extended enough times that Σ(8 + mangledNameSize) for its
        // base name exceeds 65535, the length overflows. On ASSERTS toolchains
        // `swiftc -emit-module` aborts (signal 6); on RELEASE toolchains it emits a
        // SILENTLY TRUNCATED module and downstream consumers cannot resolve the
        // dropped members ("type '…' has no member 'Artikel N'"). Present 6.3.3 →
        // 6.5-dev. Natural trigger: a statute-book namespace whose ~700 articles are
        // each declared in their own `extension Book { struct `Artikel i` }` (one
        // file per statutory provision — the idiomatic legal encoding).
        //
        // The asserts manifestation aborts the compiler mid-emit, so the trigger
        // ships as the `Crash.swift.txt` resource; both harnesses drive `swiftc`
        // OUT OF PROCESS and detect BOTH the crash and the release-truncation.
        // bare-`swiftc` single-file per [ISSUE-002].

        .testTarget(
            name: "swift-issue-extension-table-uint16-datalength-overflow-Tests",
            path: "swift-issue-extension-table-uint16-datalength-overflow/Tests"
        ),

        .executableTarget(
            name: "swift-issue-extension-table-uint16-datalength-overflow-Repro",
            path: "swift-issue-extension-table-uint16-datalength-overflow/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),

        // MARK: - swift-issue-inliner-escaping-mark-dependence-coroutine-token
        //
        // NOT FILED (standing policy) — terminal record only. EarlyPerfInliner
        // aborts at -O on an ESCAPING `mark_dependence` attached to the token
        // result of a `begin_apply`. `LifetimeDependenceInsertion` puts a
        // mark_dependence on a coroutine's token when it yields a
        // lifetime-dependent value; commit 8396a6d8c05 made the inliner delete
        // those, guarded by `assert(mdi.isNonEscaping())` — i.e. assuming a token
        // only ever carries a SCOPED dependence. A generic consumer that reads a
        // `@_lifetime(borrow self) borrowing get` accessor and then CONSTRUCTS AND
        // RETURNS a value from the yield makes that dependence escaping, tripping
        // the assert (SILInliner.cpp:167, BeginApplySite::preprocess).
        //
        // 6.5-dev-ONLY regression: CLEAN on 6.3.3-RELEASE (the production pin),
        // 6.4.x-dev, and main 2026-05-27. Architecture-independent. Distinct from
        // catalog §A3 / #88022 (CopyPropagation, fixed in 6.3) and §A7 (same pass,
        // different assertion). No source change adopted — see the README.
        //
        // The assert aborts the compiler mid-pipeline, so the trigger ships as the
        // `Crash.swift.txt` resource and both harnesses drive `swiftc` OUT OF
        // PROCESS ([ISSUE-029]); bare-`swiftc` single-file per [ISSUE-002]. The
        // probe passes `-enable-experimental-feature Lifetimes` and
        // `SuppressedAssociatedTypes` — both load-bearing.
        //
        // ⚠️ Unlike the other entries, the testTarget's `when:` is VERSION-GATED
        // (`swift --version` >= 6.5), because `when: { true }` would flip every
        // green 6.3 leg RED. See the flip-semantics table in the README.

        .testTarget(
            name: "swift-issue-inliner-escaping-mark-dependence-coroutine-token-Tests",
            path: "swift-issue-inliner-escaping-mark-dependence-coroutine-token/Tests"
        ),

        .executableTarget(
            name: "swift-issue-inliner-escaping-mark-dependence-coroutine-token-Repro",
            path: "swift-issue-inliner-escaping-mark-dependence-coroutine-token/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),

        // MARK: - swift-issue-silcloner-pack-conformance-forabstract-abort
        //
        // swiftlang/swift#90275 — SILCloner, remapping a substitution map that
        // carries a pack conformance inside an active pack expansion, projects
        // a pack element lane onto the conforming pack archetype;
        // ProtocolConformanceRef::forAbstract cannot represent the resulting
        // PackElementType subject and swift-frontend aborts (signal 6) with
        // "Abort: function forAbstract at ASTContext.cpp:5924 / Abstract
        // conformance with bad subject type". Fires on the 6.3 line (verified
        // 6.3.3-RELEASE, pass CapturePromotion in the minimal shape;
        // CrossModuleOptimization in the Institute production shape — see
        // swift-institute/Issues#58). Fixed by swiftlang/swift#89916
        // ([SILCloner] Preserve expansion level when cloning pack
        // conformances), merged to release/6.4.x only — clean on Apple Swift
        // 6.4, 6.4.x-snapshot-2026-07-23 and main-snapshot-2026-07-11 (both
        // +assertions). Load-bearing: `sending` on the escaping closure
        // parameter, the `false || …` autoclosure nesting inside the pack
        // expansion, and the `each o != each o` apply carrying the pack
        // conformance.
        //
        // Because the bug aborts the COMPILER, the triggering source ships as
        // the `Crash.swift.txt` resource; both harnesses compile it OUT OF
        // PROCESS via `swiftc -emit-sil` and report the abort. The test wraps
        // the probe in `withKnownIssue` VERSION-GATED to probed-compiler
        // < 6.4 (the fix is on 6.4+; an ungated `when: { true }` would flip
        // every 6.4+ leg red today). The red flip on a 6.3-line leg is the
        // signal that the #89916 fix (or a backport) reached that line — the
        // event Issues#58's blocked Swift 6.3 release gates wait on. No
        // external dependencies — bare-`swiftc` single-file per [ISSUE-002].

        .testTarget(
            name: "swift-issue-silcloner-pack-conformance-forabstract-abort-Tests",
            path: "swift-issue-silcloner-pack-conformance-forabstract-abort/Tests"
        ),

        .executableTarget(
            name: "swift-issue-silcloner-pack-conformance-forabstract-abort-Repro",
            path: "swift-issue-silcloner-pack-conformance-forabstract-abort/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
