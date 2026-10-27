# Swift Issue: `getMangledName` abort emitting debug info for a local whose type is a value-generic, same-type-constrained member typealias

**Upstream:** **NOT FILED.** No upstream duplicate search is recorded. Per the
standing policy cited in [`CHARACTERIZATION.md`](CHARACTERIZATION.md), this
directory is the record.

**Status:** Seen on Swift 6.3 with assertions (Windows CI, and the
`swiftlang/swift:nightly-6.3-jammy` image, 6.3.3-dev). Status on Swift 6.4 and later
is **unknown**: it was not re-tested.

**Classification:** Compiler crash. `abort()` (signal 6) in IRGen's debug-info
emission (`IRGenDebugInfo.cpp:1098`), from the debug-type round-trip check. Only
assertions-enabled compilers run that check; release toolchains compile the code.

Note on the name: the directory says "typed-throws", but nothing in the record
involves typed throws. The bug is about a value-generic typealias in debug info.
The name came from the rename in #74.

## Minimal reproducer

There is **no reproducer source** in this directory. The reproduction of record is
a real-package build: `swift-primitives/swift-dimension-primitives` at `6939cea`,
target `Dimension Primitives Tests`, built with `swift build --build-tests` on an
assertions toolchain. Its output is
[`evidence/real-package-crash-6.3.3-dev.log`](evidence/real-package-crash-6.3.3-dev.log).

The shape, from the record:

```swift
// module Axis_Primitive
public struct Axis<let N: Int> { ... }

// module Dimension_Primitives
extension Axis where N == 2 { public typealias Vertical = Dimension_Primitives.Vertical }

// test module
let v: Axis<2>.Vertical = .downward   // named local of the sugared type, built with -g
```

**Actual** (Swift 6.3.3-dev, `c83acbf89dd1298`, assertions on):

```
error: compile command failed due to signal 6 (use -v to see invocation)
Abort: function getMangledName at IRGenDebugInfo.cpp:1098
Failed to reconstruct type for $s14Axis_Primitive0A0V20Dimension_PrimitivesSiRVz$1_RszlE8Verticalay$1__GD
Pass '-Xfrontend -disable-round-trip-debug-types' to disable this assertion.
```

The decisive frame is `IRGenDebugInfoImpl::emitVariableDeclaration`: the abort
happens while emitting the debug type of a source variable.

**Expected:** the test target compiles. The mangled debug name of `Axis<2>.Vertical`
should demangle back to the same type.

## Trigger characterization

The record's ingredient model (from the real package):

| Ingredient | Removed | Result |
|---|---|---|
| value-generic type `Axis<let N: Int>` | not tested | unknown |
| member typealias in a same-type-constrained extension (`where N == 2`), in another module | not tested | unknown |
| named local whose declared type is the sugared typealias | use it in expression position | compiles (validated on the real package) |
| named local whose declared type is the sugared typealias | annotate with the underlying type | compiles, per the record's model; no run recorded |
| `-g` | dropped | compiles, per the record's model; no run recorded |
| assertions-enabled compiler | release toolchain | compiles (macOS and Linux CI) |

Which family member crashes depends on file order: the local run hit
`Axis<2>.Vertical`; the Windows run hit `Axis<3>.Depth`.

A two-module bare-`swiftc` reduction (the type in one module; the typealias and the
named local in a second) **compiled clean** with assertions. The record suggests a
third module is needed (the local in a module that imports the typealias from the
module that extends `Axis`), but that was not confirmed: no three-module reduction
is recorded.

## Toolchains

| Toolchain | Result |
|---|---|
| Swift 6.3, assertions on, Windows (CI, run `28253640439`) | **aborts** (`Axis<3>.Depth`) |
| Swift 6.3.3-dev (`c83acbf89dd1298`), assertions on, `swiftlang/swift:nightly-6.3-jammy` | **aborts** (`Axis<2>.Vertical`) |
| Swift 6.3.3 release, macOS | compiles; 268 tests pass |
| `swift:6.3` Linux release | compiles |
| Swift 6.4 and later | **unknown** |

Not run locally for this README: there is no source to run.
[swift-institute/Issues#187](https://github.com/swift-institute/Issues/issues/187),
a related `getMangledName` abort, reports that
`-Xfrontend -enable-round-trip-debug-types` turns the same check on with a macOS
release toolchain. That may allow a local re-test once a reproducer exists.

## How it was found

Windows CI on `swift-dimension-primitives` (pre-fix run `28253640439`, job
`Windows (Swift 6.3, debug)`). The library built on every platform; only the test
target crashed, at named locals in `Tests/Dimension Primitives Tests/Axis.* Tests.swift`.

## Workaround

Reference the typealias in expression position instead of as the declared type of a
named local:

```swift
// before: crashes on assertions toolchains
let axisVert: Axis<2>.Vertical = .downward
#expect(axisVert == vert)

// after
#expect(Axis<2>.Vertical.downward == Vertical.downward)
```

The compiler's own escape hatch, `-Xfrontend -disable-round-trip-debug-types`, also
avoids it; the project ruled out unsafe flags. The expression-position rewrite was
applied in `swift-dimension-primitives` `5b940ee` (2026-06-27). After it, the
assertions build completed and Windows CI run `28280214029` passed.

## Harness

None. This entry has no `Sources/` or `Tests/` and no targets in the root
`Package.swift`. A harness needs a dependency-free trigger, which does not exist yet.

## Provenance

- Investigation 2026-06-27 (swift-dimension-primitives, Windows assertions leg).
  First committed in `9d44b10` as `swift-issue-dimension-axis-typealias-windows-asserts-ice`.
- Renamed to this directory in `e60b97f` (2026-07-30) for
  [swift-institute/Issues#74](https://github.com/swift-institute/Issues/issues/74);
  the evidence log was left byte-identical.
- Inventory: [#69](https://github.com/swift-institute/Issues/issues/69) lists it as
  "not-yet-eligible: no reproducer source in checkout, only crash evidence".
- Real package: `swift-primitives/swift-dimension-primitives` `6939cea` (before the
  workaround) and `5b940ee` (after). `Axis<let N: Int>` is from `swift-axis-primitives`.
- Related, same check class: [`../swift-issue-vector-iterable-materializing-mangler-verify/`](../swift-issue-vector-iterable-materializing-mangler-verify/)
  (`Mangler::verify` in SILGen) and Issues#187 (`getMangledName`, a `Span` over a
  typealias chain).
- Full characterization: [`CHARACTERIZATION.md`](CHARACTERIZATION.md).
