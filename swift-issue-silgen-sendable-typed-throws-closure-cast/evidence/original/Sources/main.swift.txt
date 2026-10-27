// MARK: - SILGen crash on @Sendable typed-throws closure cast into generic Sendable parameter
//
// Purpose: Reproduce the Swift 6.3.1 signal-5 SILGen crash triggered when a
//   typed-throws `@Sendable` closure literal is passed — via an inline `as`
//   conversion — into a generic function parameter that requires `Sendable`.
//
// Hypothesis: The trigger is the composition of four elements at one call site:
//     (1) closure literal
//     (2) inline `as @Sendable (In) throws(E) -> Out` conversion
//     (3) typed throws (`throws(E)`) where `E` is any concrete `Error` type
//     (4) generic callee parameter requiring the argument to be `Sendable`
//   Breaking any of (1)–(4) avoids the crash:
//   - No inline `as` conversion (let-bind the closure first) → compiles
//   - No typed throws (untyped `throws` or non-throwing) → compiles
//   - Non-generic callee with concrete function-typed parameter → compiles
//     (e.g., `store.insert` overload declared as
//      `<In, Out, E> (@Sendable (In) throws(E) -> Out) -> ...`)
//
// Toolchain: Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102)
// Platform: macOS 26.0 (arm64)
//
// Result: CONFIRMED — `swift build` crashes with `signal 5` during SILGen.
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL CRASHES
//   Frame 4: `createInputFunctionArgument`
//   Frame 5: `(anonymous namespace)::LoweredParamGenerator::claimNext()`
//   Frame 6: `visitBuiltinIntegerType` — lowering the closure's `Int` parameter
//   Frame 10–12: `emitBasicProlog` → `emitProlog` → `emitClosure`
//   Crash while SILGen was building the closure's parameter prolog under the
//   `as @Sendable (Int) throws(TestError) -> Int` conversion.
//
// Reproduction:
//   cd Experiments/silgen-sendable-typed-throws-closure-cast
//   rm -rf .build
//   swift build
//
// Date: 2026-04-21
//
// Provenance:
//   Surfaced during the MOD-017 batch follow-up investigation for
//   `swift-machine-primitives` — the package's test suite could not compile
//   on Swift 6.3.1. Handoff:
//     an internal working document
//   The production workaround (test-file `fileprivate` extension overload of
//   `Machine.Capture.Store.insert`) is denotationally equivalent: the closure
//   flows through a concrete non-generic parameter type rather than a generic
//   `V: Sendable` substitution with an inline conversion, so SILGen lowers
//   it via the regular argument path.
//
// Adjacent prior art (same class of bug, different composition):
//   - `silgen-thunk-noncopyable-sending-capture/` — SILGen reabstraction-thunk
//     crash on `~Copyable` + `sending` + `@Sendable` capture. Signal 11, same
//     root phase (SILGen), different compositional driver.
//   - `Research/silgen-bug-prone-primitive-compositions.md` (Tier 2, IN_PROGRESS)
//     tracks the catalog of ≥3-primitive compositions that crash SILGen.
//
// Heuristic restated:
//   When two or more concurrency/effect primitives layer at a single call-site
//   conversion (here: `@Sendable` + typed `throws(E)` + inline `as` cast +
//   generic `Sendable` substitution), expect a SILGen bug before assuming the
//   code shape is wrong. Binding the closure to a `let` with an explicit type
//   OR introducing a concrete-typed overload of the callee avoids the crash;
//   both are cheap source-level reshapes.

struct CapturedSendable: Sendable {
    let payload: any Sendable
    init<V: Sendable>(_ value: V) { self.payload = value }
}

struct CapturedStore {
    var slots: [CapturedSendable] = []
    mutating func insert<V: Sendable>(_ value: V) -> Int {
        slots.append(CapturedSendable(value))
        return slots.count - 1
    }
}

enum TestError: Error, Sendable { case bad }

// V1 (crashing form) — the exact shape the machine-primitives tests used.
// SILGen crashes at signal 5 in `createInputFunctionArgument` while lowering
// the closure's `Int` parameter under the `as @Sendable (Int) throws(TestError) -> Int`
// conversion.
func triggerCrash() {
    var store = CapturedStore()
    let id = store.insert({ (x: Int) throws(TestError) in
        guard x >= 0 else { throw .bad }
        return x * 2
    } as @Sendable (Int) throws(TestError) -> Int)
    _ = id
}

triggerCrash()
