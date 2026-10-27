// MARK: - release-mode GenericSpecializer crash on @Sendable closure cast into generic Sendable parameter
//
// Purpose: Reproduce a Swift 6.4 `swift-frontend` abort (signal 6) in the
//   `GenericSpecializer` SIL pass, triggered only under optimization
//   (`-O`, i.e. a release build / `swift test -c release`), when a
//   non-throwing `@Sendable` closure literal is passed — via an inline `as`
//   conversion — into a generic function parameter that requires `Sendable`.
//
// Assertion:
//   swift-frontend: .../swift/SIL/TypeSubstCloner.h:121:
//   TypeSubstCloner<GenericCloner>::ApplySiteCloningHelper::ApplySiteCloningHelper(...):
//   Assertion `Subs.empty() || SubstCalleeSILType == Callee->getType().substGenericArgs(...)' failed.
//
// Relationship to the adjacent SILGen crash:
//   `silgen-sendable-typed-throws-closure-cast/` in this repo reproduces a
//   *different*, `-Onone`-reproducible SILGen crash (signal 5,
//   `createInputFunctionArgument`) that additionally requires typed throws
//   (`throws(E)`) on the closure. This experiment is the non-throwing
//   sibling: typed throws is NOT required, `-Onone` does NOT crash, and the
//   crashing pass is `GenericSpecializer` (SIL optimization), not SILGen.
//   Same family of bug (inline `as @Sendable (...) -> ...` cast into a
//   generic `Sendable`-constrained callee), different compositional trigger
//   and different compiler phase — tracked separately rather than folded
//   into the SILGen record.
//
// Hypothesis: The trigger is the composition of three elements at one call
//   site, compiled with `-O`:
//     (1) closure literal
//     (2) inline `as @Sendable (In) -> Out` conversion
//     (3) generic callee parameter requiring the argument to be `Sendable`,
//         where the callee's return type also embeds the generic parameter
//         (`ID<Value>`)
//   Breaking any of (1)-(3), or dropping `-O`, avoids the crash:
//   - No inline `as` conversion (let-bind the closure first) → compiles
//   - Non-generic callee with concrete function-typed parameter → compiles
//     (the production workaround: an overload declared as
//      `<In, Out> (@Sendable (In) -> Out) -> ID<@Sendable (In) -> Out>`)
//   - `-Onone` (debug) build → compiles; the assertion only fires once
//     `GenericSpecializer` runs
//
// Toolchain: Swift 6.4-dev (LLVM 885b338ea38aee1, Swift db4e13695491982),
//   Ubuntu 24.04.4 LTS x86_64 (GitHub Actions runner). Apple Swift 6.4
//   (swiftlang-6.4.0.27.1) on macOS arm64 does NOT reproduce — this is a
//   Linux/Ubuntu-toolchain-specific reproduction; the macOS 6.4 release
//   toolchain was checked and does not crash on the identical source.
//
// Result: CONFIRMED in production — `swift-machine-primitives` test targets
//   (Machine Node/Transform/Frame/Next/Combine/Program Primitives Tests)
//   crashed the Ubuntu 6.4 release CI leg on this exact shape, at five
//   independent call sites across five files, until each was routed through
//   the concrete-function-typed overload workaround.
//
// Reproduction (on an affected Linux toolchain):
//   cd Experiments/generic-specializer-sendable-closure-cast-release
//   rm -rf .build
//   swift build -c release
//
// Date: 2026-08-09
//
// Provenance:
//   Surfaced fixing swift-primitives/swift-machine-primitives#5 (baseline
//   CI health). Original crash reported by a fleet-wide probe as a bare
//   "Build failed / fatalError" on the gating Ubuntu 6.4 release leg with no
//   diagnosis; job log read to isolate the exact assertion and SIL function.
//   Fix landed at swift-primitives/swift-machine-primitives#6.
//
// Adjacent prior art (same call-site shape, different compiler phase):
//   - `silgen-sendable-typed-throws-closure-cast/` — the typed-throws,
//     `-Onone`-reproducible SILGen sibling described above.
//
// Heuristic restated:
//   An inline `as @Sendable (...) -> ...` cast flowing directly into a
//   `<Value: Sendable>`-generic callee is release-mode-fragile in this
//   toolchain family, independent of whether throws is involved. Prefer a
//   `let`-bound closure or (when the callee cannot be changed) a
//   concrete-function-typed overload that absorbs the cast before it
//   reaches the generic substitution.

struct CapturedSendable: Sendable {
    let payload: any Sendable
    init<V: Sendable>(_ value: V) { self.payload = value }
}

struct CapturedID<Value: Sendable>: Sendable {
    let index: Int
}

struct CapturedStore {
    var slots: [CapturedSendable] = []
    mutating func insert<Value: Sendable>(_ value: Value) -> CapturedID<Value> {
        slots.append(CapturedSendable(value))
        return CapturedID(index: slots.count - 1)
    }
}

// V1 (crashing form under `-O`) — the exact shape the machine-primitives
// tests used. `GenericSpecializer` aborts specializing
// `CapturedStore.insert<Value: Sendable>` against the closure literal cast
// inline as `@Sendable (Int) -> Int`.
func triggerCrash() {
    var store = CapturedStore()
    let id = store.insert({ (x: Int) in x * 2 } as @Sendable (Int) -> Int)
    _ = id
}

triggerCrash()
