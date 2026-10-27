# Swift Issue: "copy of noncopyable typed value" when `consuming self` forwards a `let` field

**Upstream:** **NOT FILED.** This directory is the institute's record.

**Classification:** Wrong diagnostic from the SIL move checker. The compiler
reports its internal "this is a compiler bug" error on valid code. It is not a
crash of `swift-frontend`. It fires at any optimization level, and only at the
SIL stage: `swiftc -typecheck` is clean.

## Minimal reproducer

`Sources/Reproducer/Bug.swift.txt` (one file, compiled as `main.swift`). The core:

```swift
extension NS {
    public struct Builder<Base: SourceProto & ~Copyable & ~Escapable>: ~Copyable, ~Escapable {
        @usableFromInline let _base: Base          // `let` is the trigger
        @_lifetime(copy _base) @inlinable
        package init(_base: consuming Base) { self._base = _base }
    }
    public struct Result<Base: SourceProto & ~Copyable & ~Escapable, Output>: ~Copyable, ~Escapable
    where Base.Element: Copyable {
        // let _base: Base, let _t: (Base.Element) -> Output
        @_lifetime(copy _base) @inlinable
        package init(_base: consuming Base, _t: @escaping (Base.Element) -> Output) { … }
    }
}

extension NS.Builder where Base: ~Copyable & ~Escapable, Base.Element: Copyable {
    @_lifetime(copy self) @inlinable
    public consuming func apply<Output>(
        _ t: @escaping (Base.Element) -> Output
    ) -> NS.Result<Base, Output> {
        NS.Result(_base: _base, _t: t)             // error here
    }
}
```

`SourceProto` is a `~Copyable, ~Escapable` protocol with a `~Copyable`
associated `Element`. `Builder` has conditional `Copyable` and `Escapable`
conformances.

```bash
xcrun swiftc -c -swift-version 6 -package-name Repro \
    -enable-experimental-feature Lifetimes \
    -enable-experimental-feature LifetimeDependence \
    -enable-experimental-feature SuppressedAssociatedTypes \
    main.swift -o main.o
```

**Actual** (Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1), macOS arm64, exit 1):

```
main.swift:45:26: error: copy of noncopyable typed value. This is a compiler bug. Please file a bug with a small example of the bug
```

Line 45, column 26 is the `_base` argument of `NS.Result(_base: _base, _t: t)`.
Full log: `evidence/diagnostic-6.4.2.txt`.

**Expected:** it compiles. `self` is consumed, so its `let` field can be moved
out into the `consuming` parameter.

## Trigger characterization

| Change | Result on 6.4.2 |
|---|---|
| `Builder._base` declared `var` instead of `let` (the workaround, `evidence/control-var-field.swift`) | compiles |
| `NS.Result(_base: consume _base, _t: t)` (V2 of the original) | same error |
| without `LifetimeDependence` | same error, so it is not needed |
| without `SuppressedAssociatedTypes` | the source no longer type-checks (the conditional `Copyable` conformance needs it), so this cannot be tested |
| `-O` instead of the default | same error |
| `-typecheck` only | no error |

On 6.4.2, `SuppressedAssociatedTypes` warns that it is deprecated in favour of
SE-503. The warning does not change the result.

## Toolchains

| `swiftc --version` | Result |
|---|---|
| Apple Swift version 6.3.2 (swiftlang-6.3.2.1.108) | error (per the original record) |
| Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1) — Xcode 27.2 | error |

Only macOS arm64 was run locally. Linux and Windows were not run; CI covers them.

## Workaround

Declare the builder's stored property `var` instead of `let`. Behaviour is the
same: the value is assigned once in the init and consumed by the `consuming`
method.

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` copy
`Bug.swift.txt` to a temp directory as `main.swift` and run `swiftc -c` with the
flags above in a child process, because the source does not compile on affected
toolchains and cannot be a compiled target. "Fired" means the output contains
`copy of noncopyable typed value`. A clean compile means absent. Anything else is
inconclusive and does not fail.

The bug fires on every release toolchain tested, so `withKnownIssue` uses
`when: { true }`. The test flips red once the source compiles.

Local evidence for the harness (6.4.2, macOS arm64):

- `swiftc main.swift -o probe && ./probe` → `BUG FIRED: …`, exit 1.
- The same probe with `Bug.swift.txt` replaced by `evidence/control-var-field.swift` → `The source compiled cleanly — the bug is FIXED.`, exit 0.

## Provenance

Ported from `swift-institute/Experiments/sequence-map-builder-consuming-bug` at
commit `f1c4db4d390c12af5ec454dfb506feaa4ec5e841`. Found while landing the
fluent map refactor in swift-sequence-primitives (`source.map.compact { … }`).
The experiment's committed file is already in its workaround state (`var`);
`Bug.swift.txt` restores the `let` field and the commented-out V1 `apply`, and
drops the unrelated `MapV4` variant. The original file is in `evidence/`.
