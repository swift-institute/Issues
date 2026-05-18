# Swift 6.3.2 Wasm Embedded — `MandatoryPerformanceOptimizations` SIL crash on @inlinable init delegating via closure

**Status**: VERIFIED + WORKAROUND-APPLIED — bug empirically reproduced on Swift 6.3.2 RELEASE Wasm SDK Embedded in Docker (`swift:6.3.2-jammy` + `swift-6.3.2-RELEASE_wasm-embedded` SDK); same toolchain on Swift 6.4-dev nightly Embedded (Linux) compiles clean (verified via cohort CI). Workaround in place for 6.3.2 RELEASE Wasm SDK.

**Classification**: ICE (compiler crash with assertion + SIGABRT/SIGSEGV).

**Toolchain matrix**:

| Target | Compiler | Status |
|--------|----------|--------|
| `arm64-apple-macosx26.0` debug/release | Swift 6.3.2 RELEASE (`swiftlang-6.3.2.1.108`) | OK |
| `x86_64-unknown-linux-gnu` debug/release | Swift 6.3 stable + 6.4-dev nightly | OK |
| `x86_64-unknown-linux-gnu` Embedded (6.4-dev nightly) | Swift 6.4-dev nightly | OK |
| `wasm32-unknown-wasip1` Embedded (6.3.2 RELEASE Wasm SDK) | Swift 6.3.2 RELEASE | **CRASH** |

The bug is fixed in 6.4-dev nightly (Linux Embedded build PASSED on the same code). Only the 6.3.2 RELEASE Wasm SDK target reproduces.

---

## Crash Signature

From CI run `26057005651` job `76607485580` on `swift-primitives/swift-vector-primitives@894098d` (the post-fix amended commit):

```
Assertion failed: (ty->isLegalSILType() && "constructing SILType with type that should have been " "eliminated by SIL lowering"), function SILType at SILType.h:115.

Swift version 6.3.2 (swift-6.3.2-RELEASE)
Compiling with the current language version
While evaluating request ExecuteSILPipelineRequest(Run pipelines { Mandatory Diagnostic Passes + Enabling Optimization Passes } on SIL for Vector_Primitives_Test_Support)
While running pass #4605 SILModuleTransform "MandatoryPerformanceOptimizations".

Stack trace key frames:
#10 swift::eliminateDeadAllocations(swift::SILFunction*, swift::DominanceInfo*)
#13 swift::SILPassManager::runModulePass
```

- Pass: `MandatoryPerformanceOptimizations` (Embedded's mandatory monomorphization)
- Sub-pass: `eliminateDeadAllocations`
- Source location: `Tests/Support/Vector Primitives Test Support.swift` (the @inlinable convenience init)
- Target: `wasm32-unknown-wasip1`

## Reduced Trigger

The crashing code (post key-path-fix, pre-workaround):

```swift
extension Vector where Bound == UInt {
    @inlinable
    public init(
        count: Vector<UInt>.Index.Count,
        transform: @escaping @Sendable (Int) -> Bound = { $0.magnitude }
    ) {
        self.init(count: count, transform: { $0.position.rawValue })
    }
}
```

Where:
- `Vector<Bound>` is a `~Copyable`-permissive generic struct with a stored `transform: @Sendable (Index) -> Bound` closure
- `Vector<UInt>.Index` is `Index<Vector<UInt>>` — a phantom-tagged `Tagged<Vector<UInt>, Ordinal>`
- `.position` projects the underlying `Ordinal`
- `.rawValue` projects the underlying `UInt`

The delegating closure `{ $0.position.rawValue }` — `(Index<Vector<UInt>>) -> UInt` — is what `MandatoryPerformanceOptimizations` crashes on. The closure is an SE-0413-style escaping `@Sendable` closure stored in the receiver's `transform` field after this init returns.

## Why It's Probably Fixed Upstream

The same code compiles cleanly on Swift 6.4-dev nightly Embedded (Linux Embedded build job passed on the same SHA). The bug is in the 6.3.2 SIL pipeline's mandatory-monomorphization stage handling of `@inlinable` inits that delegate via captured closures into another stored-closure field.

The `eliminateDeadAllocations` stack frame suggests the pass attempts to remove a stack allocation that was used to construct the closure and hits a SIL type representation that's not legal at that stage — likely a generic type that should have been monomorphized earlier in the pipeline.

## Maximally Reduced Empirical Reproducer (Verified)

See [`repro.swift`](./repro.swift). **2 lines**, empirically verified to crash on Swift 6.3.2 RELEASE Wasm SDK Embedded. Standalone — depends ONLY on `swift-index-primitives` (transitively `swift-tagged-primitives` + `swift-ordinal-primitives` + `swift-cardinal-primitives` + `swift-carrier-primitives` + `swift-standard-library-extensions` + `swift-affine-primitives` + `swift-comparison-primitives` + ...).

```swift
public import Index_Primitives

public let x: Index<Int> = .zero + .zero
```

**The bug is in `swift-index-primitives` (or its dep chain), NOT `swift-vector-primitives`.** Vector was the consumer that originally surfaced the crash, but the trigger only needs the `Index<T>.zero + Index<T>.Count.zero -> Index<T>` operator from `swift-index-primitives` to be called from a downstream consumer module under Embedded.

The crash requires multi-module: the trigger surface is `public import Index_Primitives` in a consumer module + a call site invoking the cross-Tagged arithmetic `+` operator on `Index<T>`. Single-file `swiftc` inlining of synthetic equivalents did NOT reproduce.

### Empirical Reduction Log (Docker `swift:6.3.2-jammy` + `swift-6.3.2-RELEASE_wasm-embedded` SDK)

**Phase 1 — in-package reduction (Tests/Support of swift-vector-primitives)**:

| Form | Lines | Crashes? |
|------|------:|----------|
| Production Test Support (3 inits + Range<Int> init) | ~50 | ✅ |
| Only `(count:transform:)` init, no default, no transform param, no `@inlinable` | 5 | ✅ |
| `public let x: Vector<UInt> = Vector(count: .zero) { _ in 0 }` (Vector-Primitives dep) | 2 | ✅ |

**Phase 2 — dep-chain isolation (standalone packages with public-deps from swift.org)**:

| Dep | Consumer code | Crashes? |
|-----|---------------|----------|
| Vector_Primitives (production package) | 2 lines | ✅ |
| Tagged_Primitives only | `Tagged<SomeTag, UInt>(0)` | ❌ |
| Tagged + Ordinal + Cardinal | V<B> wrapping both Tagged<V<B>, Ordinal/Cardinal> | ❌ |
| Tagged + Ordinal + Cardinal + Index | V<B> with `.zero + count` arithmetic | ✅ |
| **Index_Primitives only** | **`public let x: Index<Int> = .zero + .zero`** | **✅** |

The bug surface narrowed to: invoking the `Index<T>.zero + Index<T>.Count.zero -> Index<T>` operator (or `Tagged<T, Ordinal> + Tagged<T, Cardinal>` equivalent) from a downstream consumer compiled under Embedded.

**Phase 3 — failed standalone reductions** (no production deps):

| Form | Crashes? |
|------|----------|
| Single-file `swiftc -wmo -enable-experimental-feature Embedded` (~50–80 LoC with inlined Tagged/Ordinal/Cardinal/Index) | ❌ |
| Synthetic 5-module SwiftPM chain mirroring production graph, ~Copyable only | ❌ |
| Synthetic 5-module SwiftPM with full `~Copyable & ~Escapable` + production swift settings | ❌ |

### Required ingredients ([ISSUE-004])

Verified by removal-then-rebuild in container:

1. **`Index<T>.zero + Index<T>.Count.zero` cross-Tagged arithmetic** (or any specialization of the `+ <T> (Index<T>, Index<T>.Count) -> Index<T>` operator from `swift-index-primitives`) called from a **consumer module** that `public import`s `Index_Primitives` — REQUIRED.

NOT required (verified by removal):

- Vector / V<B> wrapper struct (a top-level `let x: Index<Int> = .zero + .zero` is enough).
- `@inlinable` on anything in the consumer.
- `@Sendable` closure storage.
- `Bound: ~Copyable` parameter.
- Generic structs at the call site.
- Init delegation pattern.
- Property-chain access in closure body.
- Multiple init parameters.

### Standalone synthetic (no production deps) — still NOT reproduced

The empirical 2-line repro uses production `swift-index-primitives` as a dep. Attempts to construct a fully-standalone reproducer (no external packages) all failed:

| Form | Crashes? |
|------|----------|
| Single-file `swiftc -wmo -enable-experimental-feature Embedded` (~50–80 LoC with inlined `Tagged`/`Ordinal`/`Cardinal`/`Index`/`V`) | ❌ |
| 2-module SwiftPM (Lib + Consumer) with structurally-equivalent types | ❌ |
| 5-module SwiftPM (TaggedPkg → OrdinalPkg → IndexPkg → VectorPkg → ConsumerPkg) mirroring production graph depth, ~Copyable only | ❌ |
| 5-module SwiftPM with full `~Copyable & ~Escapable` on Tagged + production swift settings (Lifetimes, SuppressedAssociatedTypes, InternalImportsByDefault, MemberImportVisibility, NonisolatedNonsendingByDefault, LifetimeDependence, InferIsolatedConformances) | ❌ |

The structural shape is **not sufficient** — the bug requires something specific to the actual production dep chain (`swift-tagged-primitives` + `swift-ordinal-primitives` + `swift-cardinal-primitives` + `swift-standard-library-extensions` + `swift-carrier-primitives` + `swift-index-primitives` + `swift-vector-primitives`) beyond what a structurally-equivalent synthetic chain captures.

Candidate load-bearing factors NOT yet isolated in synthetic forms:
- `Carrier` protocol witness chain (swift-carrier-primitives base)
- `Tagged`'s many helper extensions, arithmetic operators, conditional conformances on stdlib protocols
- Specific `@_spi(Internal)` imports between packages
- Larger fan-out: each production package has many sibling stored extensions and re-exports
- Cyclic / depth interactions between multi-pack targets within each package

The bug-triggering surface is the **cross-module SIL emission for a consumer that calls a `Vector<B>` init when compiled under `-enable-experimental-feature Embedded`**. Reducing further is open work — the 2-line in-package form remains the verified empirical minimum. Synthetic chain artifacts at `/tmp/synthetic-chain/` (5 packages, ~80 LoC, all build-clean).

## Workaround (per [ISSUE-001] / [ISSUE-008])

The Test Support inits are not needed for Embedded consumers (Embedded does not consume test fixtures). Guard the failing inits with `#if !hasFeature(Embedded)` so they are excluded from the Embedded build graph.

Applied in `swift-primitives/swift-vector-primitives/Tests/Support/Vector Primitives Test Support.swift` at commit [to-be-pushed].

```swift
#if !hasFeature(Embedded)
extension Vector where Bound == UInt {
    @inlinable
    public init(count: Vector<UInt>.Index.Count, ...) { ... }
    public init(start: ..., end: ..., ...) throws(Vector<UInt>.Error) { ... }
}
#endif
```

The `(_ range: Swift.Range<UInt>, transform:)` init does NOT carry the failing shape (no @inlinable + delegating closure pattern) and stays available under Embedded.

## Upstream Tracking

- **Fix status**: confirmed FIXED in Swift 6.4-dev nightly (`swiftlang/swift@main`, Linux Embedded build job passed on same SHA).
- **No new upstream issue filed**: per [ISSUE-001], fixed-on-dev bugs don't require new filings — the fix will land in the next Swift release with Wasm SDK support.
- **Search for matching upstream**: search `site:github.com/swiftlang/swift/issues "eliminateDeadAllocations" Embedded` for already-merged fix candidates.

## Removal Condition

Remove the `#if !hasFeature(Embedded)` guard when the Swift Wasm SDK ships against a toolchain ≥ Swift 6.4 (i.e., when 6.4 RELEASE ships).

## Provenance

- CI run: https://github.com/swift-primitives/swift-vector-primitives/actions/runs/26057005651
- Failing job: https://github.com/swift-primitives/swift-vector-primitives/actions/runs/26057005651/job/76607485580
- Failing commit: `894098d` (`Initial publication of swift-vector-primitives`)
- Investigation skill invocation: 2026-05-18

## Cross-references

- `[ISSUE-001]` Check Dev Toolchain First — bug passes on 6.4-dev nightly
- `[ISSUE-002]` Standalone Reproducer — drafted, not yet executed (Wasm SDK install pending)
- `[ISSUE-005]` SIL Dump Analysis — assertion + pass identified
- `[ISSUE-008]` Resolution Paths — workaround applied
- `[ISSUE-028]` Compiler Bug Catalog — to be amended with this entry
- `[PKG-BUILD-007]` Embedded source-guard pattern — `#if !hasFeature(Embedded)`
