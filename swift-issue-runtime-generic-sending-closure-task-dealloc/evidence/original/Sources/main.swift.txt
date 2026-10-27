// MARK: - SILGen reabstraction-thunk crash on ~Copyable + sending + @Sendable capture
//
// Purpose: Reproduce the Swift 6.3.1 SIGSEGV in SILGen reabstraction-thunk
//   emission triggered when a `~Copyable & Sendable` value is moved into a
//   `var Optional` slot, captured by a `sending () throws -> sending Value`
//   thunk, and the thunk is passed into an `@Sendable` async closure.
//
// Hypothesis: Composition of three ownership/concurrency primitives at one
//   syntactic site — `~Copyable` Optional capture + `sending` thunk parameter
//   + `@Sendable` async outer closure — is the trigger. Each primitive in
//   isolation works (e.g., the canonical `var slot: V? = consume value` +
//   `slot.take()!` pattern at `swift-foundations/swift-io/Sources/IO Events/Kernel.Event.Driver.swift:117`).
//
// Toolchain: Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102)
// Platform: macOS 26.0 (arm64)
//
// Result: CONFIRMED — `swift build` crashes with `signal 11` during SILGen.
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL CRASHES
//   Stack frames 5 and 6: "While emitting reabstraction thunk in SIL function
//     '@$sBA...silgen_thunk_noncopyable_sending_capture7PayloadVIgTo_...'"
//   Crash site: `swift::Lowering::SILGenFunction::emitApplyWithRethrow` →
//               `buildThunkBody` → `createThunk`.
//   In-package adjacent variants compiled but crashed at runtime with
//     "freed pointer was not the last allocation" (SIGABRT, signal 6) on
//     the first suspension that invoked the thunk — both are symptoms of
//     the same SILGen bug class around `~Copyable` / `sending` / closure
//     reabstraction under `@Sendable`.
// Reproduction: `rm -rf .build && swift build`
// Date: 2026-04-17
//
// Provenance:
//   Surfaced during the `swift-effect-primitives` `~Copyable & Sendable`
//   widening (HANDOFF: an internal working document)
//   when attempting the canonical thunk form for `Effect.Continuation.One._resume`.
//   Workaround landed: two-callback storage (`_onValue` + `_onError`) —
//   denotationally equivalent (tagged union via two channels), avoids the
//   failing composition entirely. See:
//     - `swift-primitives/Research/effect-primitives-and-io-algebra-relation.md`
//       §"Findings (Modernization)" §14.2 / §14.3
//     - Reflection: `swift-institute/Research/Reflections/2026-04-17-effect-primitives-ncopyable-widening-silgen-workaround.md`
//
// Adjacent prior art (this is a novel runtime/SILGen variant in a known class):
//   - `copypropagation-noncopyable-switch-consume/` — different SIL phase
//     (CopyPropagation, not SILGen), different symptom (compile-time
//     "Found ownership error?!" in release only), same composition class
//     (~Copyable + ownership transfer).
//   - `noncopyable-ecosystem-state.md` (Tier 2 DECISION, 2026-04-02): documents
//     the Optional+take workaround pattern; this experiment shows the pattern
//     fails when composed with `sending` thunk + `@Sendable` async outer.
//   - Reflection `2026-04-16-io-completion-storage-elimination.md` action
//     item: pending [IMPL-093] documenting the Optional-capture reinitialization
//     pattern for ~Copyable values crossing async closure boundaries.
//
// Heuristic surfaced (Pattern 1 of the 2026-04-17 reflection):
//   When three or more ownership/concurrency primitives layer at one
//   syntactic site (e.g., ~Copyable + sending + @Sendable + typed throws +
//   consuming), expect a compiler bug before assuming the code shape is
//   wrong. The single-primitive sites (`Kernel.Event.Driver.swift:117`)
//   work cleanly; the multi-primitive composition is the trigger.
//
// Next steps (action items in the 2026-04-17 reflection):
//   1. Re-run on Swift 6.4-dev nightly. If clean: retire the two-callback
//      workaround in `Effect.Continuation.One` in favour of the thunk form
//      (closer to [IMPL-092]) and drop `@Sendable` on the storage.
//   2. If still broken on 6.4-dev: file upstream at swiftlang/swift citing
//      the reabstraction-thunk frame.
//   3. Survey other ecosystem sites where 3-or-more-primitive compositions
//      could trigger the same bug class.

struct Payload: ~Copyable, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
}

final class Sink: @unchecked Sendable {
    var received: String?
    func put(_ s: String) { received = s }
}

struct One<Value: ~Copyable & Sendable, Failure: Error>: ~Copyable, Sendable {
    let _resume: @Sendable (
        sending () throws(Failure) -> sending Value
    ) async -> Void

    init(
        _ resume: @escaping @Sendable (
            sending () throws(Failure) -> sending Value
        ) async -> Void
    ) {
        self._resume = resume
    }

    consuming func resume(returning value: consuming sending Value) async {
        var slot: Value? = consume value
        await _resume { () throws(Failure) -> sending Value in slot.take()! }
    }
}

@main
struct App {
    static func main() async {
        let sink = Sink()
        let one = One<Payload, Never> {
            @Sendable (thunk: sending () throws(Never) -> sending Payload) async in
            let payload = thunk()
            sink.put(payload.message)
        }
        await one.resume(returning: Payload("hello"))
        precondition(sink.received == "hello")
        print("OK")
    }
}
