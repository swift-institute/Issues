// MARK: - Sequence.Map.Builder Consuming-Func Compiler Bug Reproducer
//
// Purpose: Isolate the "copy of noncopyable typed value. This is a compiler bug."
//          diagnostic that fires when a ~Copyable Builder struct's `consuming func`
//          returns a sibling ~Copyable type whose generic args include the
//          Builder's own generic parameter.
//
// Context: Hit while landing the swift-sequence-primitives fluent map refactor
//          (`source.map.compact { ... }`, `source.map.flat { ... }`).
//
// Toolchain: Apple Swift version 6.3.2 (default macOS)
// Platform: macOS 26 (arm64)
//
// Hypothesis space (variants below isolate one factor at a time):
//
//  V1 — Baseline: Builder ~Copyable, consuming func, returns sibling ~Copyable
//                 with shared Base generic param. EXPECTED: bug fires.
//  V2 — Drop ~Escapable on Builder only.
//  V3 — Drop @_lifetime annotations.
//  V4 — Make Builder a class (reference type, no copy semantics).
//  V5 — Make Builder Copyable (drop ~Copyable on Builder).
//  V6 — Pass Base via the function's own generic (i.e., the consuming
//        func re-introduces the generic, doesn't inherit from Builder<Base>).
//
// Result: CONFIRMED (V1: bug reproduces) + WORKAROUND IDENTIFIED (V3).
//
// Empirical findings:
//   V1 (let _base, consuming, `_base` direct): FAILS
//     "copy of noncopyable typed value. This is a compiler bug."
//     at the `_base` argument of `NS.Result(_base: _base, _t: t)`.
//
//   V2 (let _base, consuming, `consume _base`): FAILS — same bug.
//
//   V3 (var _base, consuming, `_base` direct): PASSES — clean build.
//
// Conclusion: the bug is triggered by passing a `let`-bound `~Copyable`
// stored property through `consuming self` into a sibling ~Copyable
// constructor that takes `consuming Base`. Switching the storage to
// `var _base: Base` (still effectively immutable from outside; the
// `package init` is the only mutator) bypasses the bug entirely.
//
// Workaround for swift-sequence-primitives' fluent-map refactor:
// declare Builder's `_base` as `var`, not `let`. Functional behavior
// is identical (the value is only assigned once, in the package init,
// and consumed by `apply`/`compact`/`flat`/`callAsFunction`).
//
// Toolchain stamp: Apple Swift version 6.3.2 (swiftlang-6.3.2.1.108).

// MARK: - Shared minimal "sequence" protocol substrate

public protocol SourceProto<Element>: ~Copyable, ~Escapable {
    associatedtype Element: ~Copyable
}

public struct Source<E>: SourceProto {
    public typealias Element = E
    @usableFromInline var _values: [E]
    @inlinable public init(_ values: [E]) { self._values = values }
}


// MARK: - V1: Baseline (reproduces the bug)

public enum NS {}

extension NS {
    public struct Builder<Base: SourceProto & ~Copyable & ~Escapable>: ~Copyable, ~Escapable {
        @usableFromInline var _base: Base   // V3: var instead of let

        @_lifetime(copy _base)
        @inlinable
        package init(_base: consuming Base) { self._base = _base }
    }

    public struct Result<Base: SourceProto & ~Copyable & ~Escapable, Output>: ~Copyable, ~Escapable
    where Base.Element: Copyable {
        @usableFromInline let _base: Base
        @usableFromInline let _t: (Base.Element) -> Output

        @_lifetime(copy _base)
        @inlinable
        package init(_base: consuming Base, _t: @escaping (Base.Element) -> Output) {
            self._base = _base
            self._t = _t
        }
    }
}

extension NS.Builder: Copyable where Base: Copyable & ~Escapable {}
extension NS.Builder: Escapable where Base: Escapable & ~Copyable {}

extension NS.Builder where Base: ~Copyable & ~Escapable, Base.Element: Copyable {
    // V1 — Baseline (reproduces bug per Result line above; commented out so the
    // experiment compiles for downstream variants).
    // @_lifetime(copy self)
    // @inlinable
    // public consuming func apply<Output>(
    //     _ t: @escaping (Base.Element) -> Output
    // ) -> NS.Result<Base, Output> {
    //     NS.Result(_base: _base, _t: t)
    // }

    // V2 — Use `consume self._base` explicitly to mark the move.
    @_lifetime(copy self)
    @inlinable
    public consuming func applyV2<Output>(
        _ t: @escaping (Base.Element) -> Output
    ) -> NS.Result<Base, Output> {
        NS.Result(_base: consume _base, _t: t)
    }
}

// MARK: - V4: Map itself IS the Builder (no separate Builder type)
//
// Hypothesis: with the var-storage workaround established by V3, can
// Sequence.Map<Base> itself play the Builder role + carry Eager/Compact/
// Flat as nested types? Earlier this produced cryptic "Eager specialized
// with too few type parameters (got 1, but expected 2)" errors that may
// have been masked side-effects of the let-storage bug, not a separate
// language-level constraint.

public struct MapV4<Base: SourceProto & ~Copyable & ~Escapable>: ~Copyable, ~Escapable {
    @usableFromInline var _base: Base   // var per V3 workaround

    @_lifetime(copy _base)
    @inlinable
    package init(_base: consuming Base) { self._base = _base }
}

extension MapV4: Copyable where Base: Copyable & ~Escapable {}
extension MapV4: Escapable where Base: Escapable & ~Copyable {}

extension MapV4 where Base: ~Copyable & ~Escapable, Base.Element: Copyable {
    public struct Eager<Output>: ~Copyable, ~Escapable {
        @usableFromInline var _base: Base
        @usableFromInline let _t: (Base.Element) -> Output

        @_lifetime(copy _base)
        @inlinable
        package init(_base: consuming Base, _t: @escaping (Base.Element) -> Output) {
            self._base = _base
            self._t = _t
        }
    }
}

extension MapV4.Eager: Copyable where Base: Copyable & ~Escapable {}
extension MapV4.Eager: Escapable where Base: Escapable & ~Copyable {}

extension MapV4 where Base: ~Copyable & ~Escapable, Base.Element: Copyable {
    @_lifetime(copy self)
    @inlinable
    public consuming func callAsFunction<Output>(
        _ t: @escaping (Base.Element) -> Output
    ) -> MapV4<Base>.Eager<Output> {
        MapV4<Base>.Eager(_base: _base, _t: t)
    }
}

// Smoke driver
let s1 = Source([1, 2, 3])
let b1 = NS.Builder(_base: s1)
_ = b1.applyV2 { $0 * 2 }

let m4 = MapV4(_base: Source([1, 2, 3]))
_ = m4 { $0 * 2 }   // callAsFunction trailing closure
print("V1..V4: compiled.")
