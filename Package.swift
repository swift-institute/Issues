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
    platforms: [.macOS("27"), .iOS("27"), .tvOS("27"), .watchOS("27"), .visionOS("27")],

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

        // MARK: - swift-issue-inliner-escaping-carrier-bitwise-underlying
        //
        // NOT FILED (standing policy) — terminal record only. swift-institute/Issues#99.
        // SAME root cause and SAME assertion as
        // swift-issue-inliner-escaping-mark-dependence-coroutine-token above
        // (SILInliner.cpp:167, BeginApplySite::preprocess, assert
        // mdi.isNonEscaping()) — a second, independently observed trigger, not a
        // new bug. Here EarlyPerfInliner inlines Carrier.`Protocol`'s `underlying`
        // borrowing-get coroutine witness (Byte's conformance, UInt8-carrying)
        // into the generic bitwise `&(_:_:)` operator, which CONSTRUCTS AND
        // RETURNS a new carrier from the yielded values — an escaping
        // dependence, tripping the same assert.
        //
        // Observed live in production CI: swift-standards/swift-github-standard
        // PR #15 (run 30742912862) and PR #17 (run 30744204332), Ubuntu
        // main-nightly (Swift 6.5-dev) leg, while compiling the dependency
        // swift-binary-parser-primitives (not that package's own source — the
        // crash is entirely inside the swift-carrier-primitives ×
        // swift-byte-primitives dependency edge). See README for the full
        // disposition: structurally red for every consumer reaching this call
        // shape until the toolchain moves; no source workaround adopted.
        //
        // ⚠️ UNVERIFIED-locally: no 6.5-dev/main-nightly toolchain or working
        // docker daemon was available in the isolation lane that filed this
        // entry. Verified CLEAN on the local 6.4 toolchain (expected — this bug
        // is 6.5-dev-only per the neighbouring entry's toolchain matrix). See
        // README "Verification status" for the pending docker command.
        //
        // Bare-`swiftc` single-file per [ISSUE-002]; OUT-OF-PROCESS harness via
        // Crash.swift.txt per [ISSUE-029]. `when:` is VERSION-GATED identically
        // to the neighbouring entry — do not revert to `{ true }`.

        .testTarget(
            name: "swift-issue-inliner-escaping-carrier-bitwise-underlying-Tests",
            path: "swift-issue-inliner-escaping-carrier-bitwise-underlying/Tests"
        ),

        .executableTarget(
            name: "swift-issue-inliner-escaping-carrier-bitwise-underlying-Repro",
            path: "swift-issue-inliner-escaping-carrier-bitwise-underlying/Sources/Reproducer",
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

        // MARK: - swift-issue-sillinker-borrowed-protocol-default-shared-coroutine-abort
        //
        // swiftlang/swift#90406 — swift-frontend aborts (signal 6) compiling a
        // module that adds its own conformance to a protocol imported from another
        // module, when that protocol has a coroutine-accessor (`@_borrowed`)
        // requirement whose default implementation lives in a protocol extension of
        // the DEFINING module, and the defining module also declares a conformer.
        // The extension default's `.read` coroutine is emitted
        // `sil shared [serialized]` with NO body; the importing module's
        // MandatorySILLinker deserializes it and trips
        // `(!hasSharedVisibility(F->getLinkage()) || F->hasForeignBody())` at
        // Linker.cpp:88. Assertions-enabled toolchains catch the same malformed
        // function earlier, in the SIL verifier during ASTLoweringRequest.
        //
        // Ingredient 1 also fires WITHOUT `@_borrowed` in source, by refining a
        // stdlib collection protocol whose subscript is already `@_borrowed`.
        //
        // NOT optimization-, CMO-, whole-module-, SwiftPM- or architecture-dependent
        // (6.3.3 on macOS arm64 / Linux aarch64 / Linux x86_64, Apple 6.4,
        // 6.4.x-snapshot and main-snapshot all abort). Inherently cross-module, so
        // the trigger ships as two `.txt` resources compiled out of process.
        //
        // Reduced while characterizing the fourth signature on Issues#58.

        .testTarget(
            name: "swift-issue-sillinker-borrowed-protocol-default-shared-coroutine-abort-Tests",
            path: "swift-issue-sillinker-borrowed-protocol-default-shared-coroutine-abort/Tests"
        ),

        .executableTarget(
            name: "swift-issue-sillinker-borrowed-protocol-default-shared-coroutine-abort-Repro",
            path: "swift-issue-sillinker-borrowed-protocol-default-shared-coroutine-abort/Sources/Reproducer",
            resources: [
                .copy("LibA.swift.txt"),
                .copy("Consumer.swift.txt"),
            ]
        ),

        // MARK: - swift-issue-embedded-wasm-mandatory-perf-crash
        //
        // Swift 6.3.x wasm32 Embedded: signal 11 in the
        // MandatoryPerformanceOptimizations pass (eliminateDeadAllocations,
        // `isLegalSILType()` assertion) compiling a consumer of
        // swift-index-primitives' cross-Tagged `+` operator. Fixed on
        // 6.4-dev Embedded. The trigger irreducibly needs the production
        // dependency chain plus the wasm-embedded SDK, neither of which this
        // dependency-free package can carry — so the targets are honest
        // stubs: the Repro exits 2 (inconclusive) pointing at the README's
        // verified container invocation, and the test checks fixture
        // integrity only. See the entry README for the reduction log.

        .testTarget(
            name: "swift-issue-embedded-wasm-mandatory-perf-crash-Tests",
            path: "swift-issue-embedded-wasm-mandatory-perf-crash/Tests"
        ),

        .executableTarget(
            name: "swift-issue-embedded-wasm-mandatory-perf-crash-Repro",
            path: "swift-issue-embedded-wasm-mandatory-perf-crash/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),

        // MARK: - swift-issue-file-system-streaming-write-ownership
        //
        // CopyPropagation shortens the begin_borrow/end_borrow scope of a
        // borrowed `~Copyable` parameter so the end_borrow precedes the
        // apply consuming its projected `~Copyable` field; the SIL ownership
        // verifier aborts swift-frontend (signal 6, "Found outside of
        // lifetime use?!") at -O. Fires on 6.3.3-RELEASE; clean on Apple 6.4,
        // 6.4.x-snapshot-2026-07-23 and main-snapshot-2026-07-11. Because
        // the bug aborts the COMPILER at -O, the trigger ships as the
        // `Crash.swift.txt` resource compiled OUT OF PROCESS via `swiftc -O`;
        // the test's withKnownIssue is VERSION-GATED to probed-compiler
        // < 6.4, so a red flip on a 6.3-line leg signals the fix (or a
        // backport) reaching that line. `Workaround.swift.txt` is the
        // retained passing counterpart (@_optimize(none)).

        .testTarget(
            name: "swift-issue-file-system-streaming-write-ownership-Tests",
            path: "swift-issue-file-system-streaming-write-ownership/Tests"
        ),

        .executableTarget(
            name: "swift-issue-file-system-streaming-write-ownership-Repro",
            path: "swift-issue-file-system-streaming-write-ownership/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt"),
                .copy("Workaround.swift.txt"),
            ]
        ),

        // MARK: - swift-issue-noncopyable-assoctype-never-bodyless-witness
        //
        // A `Body == Never` extension default for a protocol's
        // `associatedtype Body: ~Copyable` property requirement is emitted
        // into consumer modules as a bodiless `shared [serialized]` `read`
        // accessor; wherever SIL verification runs (+Asserts, Embedded,
        // -sil-verify-all) the consumer module's compile aborts ("Must have
        // a construct to emit for" / "shared function must have a body").
        // Latent (emitted, unverified) on NoAsserts RELEASE toolchains. NOT
        // fixed anywhere tested (6.3.3, Apple 6.4, main-snapshot-2026-07-11
        // all abort); single-module combination is clean, so the module
        // boundary is load-bearing and expressed as two out-of-process
        // frontend invocations. Same "bodiless shared [serialized]
        // extension-default coroutine" verifier class as swiftlang/swift
        // #90406 (the sillinker entry above), different trigger.

        .testTarget(
            name: "swift-issue-noncopyable-assoctype-never-bodyless-witness-Tests",
            path: "swift-issue-noncopyable-assoctype-never-bodyless-witness/Tests"
        ),

        .executableTarget(
            name: "swift-issue-noncopyable-assoctype-never-bodyless-witness-Repro",
            path: "swift-issue-noncopyable-assoctype-never-bodyless-witness/Sources/Reproducer",
            resources: [
                .copy("Core.swift.txt"),
                .copy("Consumer.swift.txt"),
            ]
        ),

        // MARK: - swift-issue-parameterized-typealias-opaque-return-ice
        //
        // Swift 6.3.2 in-cohort ICE ("failed to produce diagnostic for
        // expression") at `var body: some P<I, O, F>` declarations in files
        // importing a module exposing a parameterized typealias or a
        // Base-constrained generic extension. Fixed on 6.4-dev. The retained
        // single-file shape has NEVER reproduced standalone (re-verified
        // clean 2026-07-30 on 6.3.3, Apple 6.4, main snapshot), so the test
        // is a CANARY, not a withKnownIssue reproducer: green while the
        // standalone shape stays clean, red the day it starts reproducing —
        // which is also the day the entry becomes upstream-fileable.

        .testTarget(
            name: "swift-issue-parameterized-typealias-opaque-return-ice-Tests",
            path: "swift-issue-parameterized-typealias-opaque-return-ice/Tests"
        ),

        .executableTarget(
            name: "swift-issue-parameterized-typealias-opaque-return-ice-Repro",
            path: "swift-issue-parameterized-typealias-opaque-return-ice/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),

        // MARK: - Batch A Group 1 — dossier index pairs (Issues#73)
        //
        // Nine dossier directories whose authoritative reproducer lives
        // under evidence/source-package (see each directory's
        // harness-justification.json; generatedIndexFilesAreAuthoritative-
        // Reproducer is false). The Repro executables print where the
        // authoritative reproduction lives; the tests pin the evidence
        // layout contract. Wiring them makes each directory reachable by
        // the per-reproducer filter convention without flattening the
        // source boundary the justification files preserve.

        .testTarget(
            name: "swift-issue-property-view-tag-constraint-cross-module-Tests",
            path: "swift-issue-property-view-tag-constraint-cross-module/Tests"
        ),
        .executableTarget(
            name: "swift-issue-property-view-tag-constraint-cross-module-Repro",
            path: "swift-issue-property-view-tag-constraint-cross-module/Sources/Reproducer"
        ),

        .testTarget(
            name: "swift-issue-rawlayout-deinit-cross-package-Tests",
            path: "swift-issue-rawlayout-deinit-cross-package/Tests"
        ),
        .executableTarget(
            name: "swift-issue-rawlayout-deinit-cross-package-Repro",
            path: "swift-issue-rawlayout-deinit-cross-package/Sources/Reproducer"
        ),

        .testTarget(
            name: "swift-issue-sil-verifier-read-escapable-lifetime-Tests",
            path: "swift-issue-sil-verifier-read-escapable-lifetime/Tests"
        ),
        .executableTarget(
            name: "swift-issue-sil-verifier-read-escapable-lifetime-Repro",
            path: "swift-issue-sil-verifier-read-escapable-lifetime/Sources/Reproducer"
        ),

        .testTarget(
            name: "swift-issue-silgen-pack-expansion-cross-module-Tests",
            path: "swift-issue-silgen-pack-expansion-cross-module/Tests"
        ),
        .executableTarget(
            name: "swift-issue-silgen-pack-expansion-cross-module-Repro",
            path: "swift-issue-silgen-pack-expansion-cross-module/Sources/Reproducer"
        ),

        .testTarget(
            name: "swift-issue-silgen-property-wrapper-noncopyable-Tests",
            path: "swift-issue-silgen-property-wrapper-noncopyable/Tests"
        ),
        .executableTarget(
            name: "swift-issue-silgen-property-wrapper-noncopyable-Repro",
            path: "swift-issue-silgen-property-wrapper-noncopyable/Sources/Reproducer"
        ),

        .testTarget(
            name: "swift-issue-testing-suite-discovery-generic-specialization-Tests",
            path: "swift-issue-testing-suite-discovery-generic-specialization/Tests"
        ),
        .executableTarget(
            name: "swift-issue-testing-suite-discovery-generic-specialization-Repro",
            path: "swift-issue-testing-suite-discovery-generic-specialization/Sources/Reproducer"
        ),

        .testTarget(
            name: "swift-issue-testing-xcode-nested-suite-filter-Tests",
            path: "swift-issue-testing-xcode-nested-suite-filter/Tests"
        ),
        .executableTarget(
            name: "swift-issue-testing-xcode-nested-suite-filter-Repro",
            path: "swift-issue-testing-xcode-nested-suite-filter/Sources/Reproducer"
        ),

        .testTarget(
            name: "swift-issue-typed-throws-autoclosure-inference-Tests",
            path: "swift-issue-typed-throws-autoclosure-inference/Tests"
        ),
        .executableTarget(
            name: "swift-issue-typed-throws-autoclosure-inference-Repro",
            path: "swift-issue-typed-throws-autoclosure-inference/Sources/Reproducer"
        ),

        // The Windows-only ICE's platform gate lives in the evidence
        // package (the local target compiles everywhere; the defect needs
        // x86_64-unknown-windows-msvc, per the harness justification).
        .testTarget(
            name: "swift-issue-windows-existential-crash-Tests",
            path: "swift-issue-windows-existential-crash/Tests"
        ),
        .executableTarget(
            name: "swift-issue-windows-existential-crash-Repro",
            path: "swift-issue-windows-existential-crash/Sources/Reproducer"
        ),

        // MARK: - Batch A Group 2 — migrated nested packages (Issues#73)
        //
        // Four directories previously carried standalone nested manifests;
        // their sources now live in the convention layout and the nested
        // Package.swift files are deleted. Where the defect was a
        // rejects-valid or emit-module failure now FIXED on every current
        // line (re-verified 2026-07-30 via bare swiftc on 6.3.3 and Apple
        // 6.4), the live library target IS the regression probe — a
        // regression turns the package build red.

        // emit-module rejects-valid (~Copyable & Protocol compound
        // constraint + conditional Sequence conformance, Lifetimes) —
        // library-shaped Repro because -emit-module is the trigger surface.
        .testTarget(
            name: "swift-issue-emit-module-noncopyable-sequence-Tests",
            path: "swift-issue-emit-module-noncopyable-sequence/Tests"
        ),
        .target(
            name: "swift-issue-emit-module-noncopyable-sequence-Repro",
            path: "swift-issue-emit-module-noncopyable-sequence/Sources/Reproducer",
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes")
            ]
        ),

        // InlineArray + value-generic capacity deinit miss (runtime).
        // Cross-module: TrackedElement lives in the test module, Container
        // in the library — the reported shape. Re-verified 2026-07-30:
        // deinits run correctly on 6.3.3 and Apple 6.4 (fixed since the
        // 6.2-era report), so the behavioral expectations pass unguarded.
        .testTarget(
            name: "swift-issue-inlinearray-deinit-value-generic-Tests",
            dependencies: [
                .target(name: "swift-issue-inlinearray-deinit-value-generic-Repro")
            ],
            path: "swift-issue-inlinearray-deinit-value-generic/Tests"
        ),
        .target(
            name: "swift-issue-inlinearray-deinit-value-generic-Repro",
            path: "swift-issue-inlinearray-deinit-value-generic/Sources/Reproducer"
        ),

        // Nested-generic subscript performance (upstream
        // swiftlang/swift#86666). The executable is the measurement
        // vehicle; the library-shaped reduced sources are a third target
        // because the benchmark file is self-contained and the two carry
        // the same type names in separate modules.
        .testTarget(
            name: "swift-issue-nested-generic-subscript-performance-Tests",
            path: "swift-issue-nested-generic-subscript-performance/Tests"
        ),
        .executableTarget(
            name: "swift-issue-nested-generic-subscript-performance-Repro",
            path: "swift-issue-nested-generic-subscript-performance/Sources/Reproducer"
        ),
        .target(
            name: "swift-issue-nested-generic-subscript-performance-Repro-Library",
            path: "swift-issue-nested-generic-subscript-performance/Sources/NestedGenericPerformance"
        ),

        // Cross-module rejects-valid (associatedtype Element vs generic
        // parameter Element confusion under conditional Sequence
        // conformance). The Ring-imports-Core module boundary is the
        // reported shape, so it is preserved as two library targets — a
        // third target beside the pair, per the boundary's load-bearing
        // role. Re-verified fixed 2026-07-30 (6.3.3, Apple 6.4).
        .testTarget(
            name: "swift-issue-noncopyable-sequence-conformance-Tests",
            path: "swift-issue-noncopyable-sequence-conformance/Tests"
        ),
        .target(
            name: "swift-issue-noncopyable-sequence-conformance-Core",
            path: "swift-issue-noncopyable-sequence-conformance/Sources/Core"
        ),
        .target(
            name: "swift-issue-noncopyable-sequence-conformance-Repro",
            dependencies: [
                .target(name: "swift-issue-noncopyable-sequence-conformance-Core")
            ],
            path: "swift-issue-noncopyable-sequence-conformance/Sources/Ring"
        ),

        // MARK: - Batch A Group 3 — wrapped loose reducers (Issues#73)
        //
        // Three directories whose reduced sources are loose files under
        // Sources/ that CANNOT be live targets: the mangling collision and
        // the rawlayout rejection fail compilation by design, and the
        // sametype reproducer SIGSEGVs at runtime. The loose files stay
        // exactly where they are (no renames — sibling sub-issues own
        // naming); the new Reproducer/Tests pairs drive them OUT OF
        // PROCESS via bare swiftc, with withKnownIssue flip semantics.
        // All three still fire on Apple Swift 6.4 (verified 2026-07-30).

        .testTarget(
            name: "swift-issue-noncopyable-extension-member-mangling-collision-Tests",
            path: "swift-issue-noncopyable-extension-member-mangling-collision/Tests"
        ),
        .executableTarget(
            name: "swift-issue-noncopyable-extension-member-mangling-collision-Repro",
            path: "swift-issue-noncopyable-extension-member-mangling-collision/Sources/Reproducer"
        ),

        .testTarget(
            name: "swift-issue-noncopyable-sametype-conditional-conformance-Tests",
            path: "swift-issue-noncopyable-sametype-conditional-conformance/Tests"
        ),
        .executableTarget(
            name: "swift-issue-noncopyable-sametype-conditional-conformance-Repro",
            path: "swift-issue-noncopyable-sametype-conditional-conformance/Sources/Reproducer"
        ),

        .testTarget(
            name: "swift-issue-rawlayout-noncopyable-extension-rejection-Tests",
            path: "swift-issue-rawlayout-noncopyable-extension-rejection/Tests"
        ),
        .executableTarget(
            name: "swift-issue-rawlayout-noncopyable-extension-rejection-Repro",
            path: "swift-issue-rawlayout-noncopyable-extension-rejection/Sources/Reproducer"
        ),

        // MARK: - swift-issue-unbound-generic-typealias-member-lookup (Issues#81)
        //
        // Member-type lookup does not look through an unbound GENERIC
        // typealias, though it does through the unbound generic nominal
        // type the alias refers to, the bound form of the same alias, a
        // non-generic alias to a concrete instantiation, and (per
        // swift-institute/.github#122 W8) a non-generic alias to an
        // unbound generic nominal. Rejects-valid; not a regression (no
        // known-good toolchain). The trigger is a TYPE-CHECK rejection,
        // not a codegen fault, so `Sources/reproducer.swift` fails to
        // typecheck by design and is NOT a live target — both harnesses
        // drive it out of process via `swiftc -typecheck -swift-version 6`.

        .testTarget(
            name: "swift-issue-unbound-generic-typealias-member-lookup-Tests",
            path: "swift-issue-unbound-generic-typealias-member-lookup/Tests"
        ),
        .executableTarget(
            name: "swift-issue-unbound-generic-typealias-member-lookup-Repro",
            path: "swift-issue-unbound-generic-typealias-member-lookup/Sources/Reproducer"
        ),

        // MARK: - swift-issue-silgencleanup-nested-closure-borrowing-noncopyable (Issues#80)
        //
        // swift-frontend aborts (signal 6, SIL ownership verifier, mandatory
        // SILGenCleanup pass) compiling a closure LITERAL whose body defines
        // a nested local closure that also captures the outer closure's
        // `borrowing ~Copyable` parameter. The identical body as a plain
        // top-level `func` is instead correctly rejected at typecheck — the
        // escaping-closure-capture check does not fire when the borrowing
        // parameter belongs to a closure literal rather than a `func`
        // declaration. Because the bug aborts the COMPILER, the trigger
        // ships as the `Crash.swift.txt` resource compiled OUT OF PROCESS.

        .testTarget(
            name: "swift-issue-silgencleanup-nested-closure-borrowing-noncopyable-Tests",
            path: "swift-issue-silgencleanup-nested-closure-borrowing-noncopyable/Tests"
        ),
        .executableTarget(
            name: "swift-issue-silgencleanup-nested-closure-borrowing-noncopyable-Repro",
            path: "swift-issue-silgencleanup-nested-closure-borrowing-noncopyable/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),

        // MARK: - swift-issue-noncopyable-assoctype-second-protocol-bodyless-witness (Issues#82)
        //
        // A type conforming, in its OWN module, to a protocol with
        // `associatedtype Body: ~Copyable` plus a `body` property
        // requirement gets a `read` accessor with `shared` linkage, which
        // is therefore not carried in that module's `.swiftmodule`. A
        // CONSUMER module that declares a SECOND conformance of the same
        // type to a protocol with an equivalent requirement emits that
        // accessor as a bodyless `shared [serialized]` SIL function, and
        // verification rejects it ("Must have a construct to emit for" /
        // "shared function must have a body"). Latent (emitted,
        // unverified) on NoAsserts RELEASE toolchains; fires on every
        // +Asserts / Embedded / Windows / `-sil-verify-all` configuration
        // tested (6.3.3, Apple 6.4, 6.4.x-snapshot-2026-07-23,
        // main-snapshot-2026-07-11). Single-module combination is clean,
        // so the module boundary is load-bearing and is expressed as two
        // out-of-process frontend invocations.
        //
        // Same "bodyless shared [serialized] coroutine across a module
        // boundary" verifier class as swiftlang/swift#90406 (the sillinker
        // entry) and the `Body == Never` entry above — but a different
        // trigger: there the bodyless function is a protocol EXTENSION
        // DEFAULT; here there is no extension default at all and the
        // bodyless function is the CONCRETE type's own accessor.
        //
        // Reduced from swift-primitives/swift-coder-primitives#2.

        .testTarget(
            name: "swift-issue-noncopyable-assoctype-second-protocol-bodyless-witness-Tests",
            path: "swift-issue-noncopyable-assoctype-second-protocol-bodyless-witness/Tests"
        ),
        .executableTarget(
            name: "swift-issue-noncopyable-assoctype-second-protocol-bodyless-witness-Repro",
            path: "swift-issue-noncopyable-assoctype-second-protocol-bodyless-witness/Sources/Reproducer",
            resources: [
                .copy("Core.swift.txt"),
                .copy("Consumer.swift.txt"),
            ]
        ),

        // MARK: - swift-issue-typed-throws-catch-clause-error-conversion (Issues#83)
        //
        // Throwing the ENCLOSING function's typed error from inside a `catch`
        // clause whose `do` block throws a DIFFERENT concrete error type
        // crashes SILGen: the throw is emitted against the do block's thrown
        // type instead of the function's, and SILGen then tries to erase a
        // non-class concrete type into an existential error box. 6.3.3
        // dereferences a bad pointer (signal 11) in emitExistentialErasure;
        // Apple 6.4 asserts in createInitExistentialRef; the 6.4.x snapshot
        // asserts on `destErrorType == SILType::getExceptionType(...)` in
        // emitThrow; 6.5-dev main emits a hard "INTERNAL ERROR: feature not
        // implemented: throw conversion" diagnostic instead of crashing. All
        // four are the same defect and the program is uncompilable on each.
        //
        // Load-bearing: the enclosing function's TYPED throws, and a
        // concrete-type catch pattern (`as T` / `is T`). NOT required: an
        // initializer, optimization, whole-module, or more than one module.
        // Because the bug aborts the COMPILER, the trigger ships as the
        // `Crash.swift.txt` resource compiled OUT OF PROCESS.
        //
        // Reduced from swift-standards/swift-sockets-standard#2, whose abort
        // is in the swift-ietf/swift-rfc-9293 dependency.

        .testTarget(
            name: "swift-issue-typed-throws-catch-clause-error-conversion-Tests",
            path: "swift-issue-typed-throws-catch-clause-error-conversion/Tests"
        ),
        .executableTarget(
            name: "swift-issue-typed-throws-catch-clause-error-conversion-Repro",
            path: "swift-issue-typed-throws-catch-clause-error-conversion/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),

        // MARK: - swift-issue-tasklocal-function-value-null-metadata (Issues#84)
        //
        // A `@TaskLocal` whose VALUE TYPE IS A FUNCTION TYPE makes the optimizer
        // emit the value type's metadata request as a LOWERED mangled name — an
        // `ImplFunctionType` carrying `ImplPatternSubstitutions` over a dependent
        // generic signature — through
        // `__swift_instantiateConcreteTypeFromMangledName`, the entry point that
        // admits only fully concrete names. Instantiation returns null and
        // `swift_task_localValuePush` faults reading the value witness table at
        // `metadata - 8` (`Bad pointer dereference at 0xfffffffffffffff8`).
        //
        // Load-bearing: `-O`, and a function-typed value. `Int?`/`String?` are
        // clean, so optionality is not part of the trigger. NOT required: async,
        // a surrounding Task, a current task at all, reading the task local in
        // the `operation:` body, a test framework, or more than one module.
        //
        // signal 11 on 6.3.3 (macOS arm64, Linux arm64, Linux x86_64); clean on
        // Apple Swift 6.4, the 6.4.x snapshot, and 6.5-dev main. Because the bug
        // crashes the PRODUCED BINARY and would take the test runner down with
        // it, the trigger ships as `Crash.swift.txt` and is compiled AND run OUT
        // OF PROCESS. `when:` is version-gated rather than `{ true }`: active
        // below 6.4 (backport detection), inactive at 6.4+ (regression
        // detection).
        //
        // Reduced from swift-primitives/swift-structured-queries-primitives#2,
        // whose `Ubuntu (Swift 6.3, release)` leg crashed in a swift-testing
        // test binding a `(@Sendable (String) -> Void)?` task local.

        .testTarget(
            name: "swift-issue-tasklocal-function-value-null-metadata-Tests",
            path: "swift-issue-tasklocal-function-value-null-metadata/Tests"
        ),
        .executableTarget(
            name: "swift-issue-tasklocal-function-value-null-metadata-Repro",
            path: "swift-issue-tasklocal-function-value-null-metadata/Sources/Reproducer",
            resources: [
                .copy("Crash.swift.txt")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
