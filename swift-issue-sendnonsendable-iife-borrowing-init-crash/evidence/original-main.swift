// MARK: - SendNonSendable SIL crash: IIFE + ~Escapable borrowing init (cross-module)
//
// Purpose: Reproduce a Swift 6.3.1 compiler assertion failure in the
//   SendNonSendable SIL function transform. The crash fires when a function
//   body contains an IIFE that constructs a `~Copyable, ~Escapable` value
//   via a borrowing `@_lifetime` init declared in a separate module.
//
// Hypothesis: Minimum ingredients — each one, if removed, makes the crash
//   disappear:
//     1. `Target: ~Copyable` — making Target Copyable eliminates the crash
//     2. `View<Base: ~Copyable>: ~Copyable, ~Escapable` with
//        `@_lifetime(borrow base) init(_ base: borrowing Base)` declared as
//        `public`. Making View non-generic with a concrete `borrowing Target`
//        parameter eliminates the crash. ~Escapable is required — the
//        compiler rejects @_lifetime on Escapable results
//     3. BOTH Target and View must be declared in a module separate from
//        the caller. Moving either type to the caller's module eliminates
//        the crash
//     4. The call site wrapped in a non-top-level function body
//        (top-level code compiles cleanly)
//     5. The View construction wrapped in an immediately-invoked closure
//        (IIFE): `_ = { _ = View(target) }()`
//     6. The `Lifetimes` experimental feature flag (required for
//        `@_lifetime`; nothing else is required — no strict-memory-safety,
//        no `@unsafe`, no other upcoming/experimental features, no `-O`)
//
// Status: STILL CRASHES (as of Swift 6.3.1)
// Result: CONFIRMED — `swift build` aborts with signal 6 in the
//   SendNonSendable SILFunctionTransform. See Outputs/build.txt for the
//   full stack dump.
//
// Toolchain: Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), Xcode 26.4.1
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL CRASHES
// Platform: macOS 26.0 (arm64)
// Date: 2026-04-21
//
// Provenance: surfaced while writing a unit test for
//   `Property.View.init(_ base: borrowing Base)` in
//   `swift-property-primitives` (commit `2e0e624`, file
//   `Tests/Property View Primitives Tests/Property.View Tests.swift`).
//   The production workaround — binding the view at the outer scope
//   instead of inside an IIFE — preserves test semantics and compiles
//   cleanly.
//
// Crash signature (abbreviated; full stack in Outputs/build.txt):
//   While running pass #32 SILFunctionTransform "SendNonSendable"
//     on SILFunction "@$s...crashingFunction...yyF...fU_"
//   swift::Partition::merge(...)
//   swift::RegionAnalysisFunctionInfo::runDataflow() + 5540
//   swift::RegionAnalysis::newFunctionAnalysis(...) + 2884
//   (anonymous namespace)::SendNonSendable::run() + 280
//   abort (signal 6)
//
// Non-ingredients — verified individually NOT to be required:
//   - `@unsafe` attribute on the init (removed; crash persists)
//   - `unsafe` keyword on the call site (removed; crash persists)
//   - strict-memory-safety flag (removed; crash persists)
//   - Release optimization (`-c release`) — crashes in debug too
//   - Stored properties on Target or View — both types are empty
//   - Generic nesting (Property<Tag, Base>.View) — reducer is flat
//   - Async context on the enclosing function
//   - Value read back through the View — IIFE body reduced to
//     `_ = View(target)`, no property access needed
//   - Public `init()` on Target is only needed to construct it; the
//     struct body can be empty
//
// Required-pair notes (ingredients that can't be varied independently):
//   - `~Escapable` + `@_lifetime`: the compiler rejects `@_lifetime` on
//     an Escapable result ("invalid lifetime dependence on an Escapable
//     result"), and it rejects a `~Escapable` init without `@_lifetime`
//     ("an initializer cannot return a ~Escapable result"). They come
//     as a pair.
//
// REPRODUCTION:
//   $ cd Experiments/sendnonsendable-iife-borrowing-init-crash
//   $ swift package clean
//   $ swift build    # → error: compile command failed due to signal 6
//
// WORKAROUND (production): bind the view at the outer scope — the IIFE
// is the load-bearing construct:
//
//   func workaroundFunction() {
//       let target = Target()
//       _ = View(target)   // no IIFE — compiles cleanly
//   }

import ReproLib

func crashingFunction() {
    let target = Target()
    _ = { _ = View(target) }()
}

crashingFunction()
