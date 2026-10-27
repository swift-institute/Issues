# Swift Issue: `Mangler::verify` abort in SILGen on an `@_implements` witness that returns an adapter over the conforming type's own nested iterator

**Upstream:** **NOT FILED.** No upstream duplicate search is recorded. Per the
standing policy cited in [`CHARACTERIZATION.md`](CHARACTERIZATION.md), this
directory is the record.

**Status:** Seen on Swift 6.3 with assertions (Windows CI 6.3.2, and the
`swiftlang/swift:nightly-6.3-jammy` image at 6.3.0-dev and 6.3.3-dev). Status on
Swift 6.4 and later with assertions is **unknown**: it was not re-tested.

**Classification:** Compiler crash. `abort()` (signal 6) in SILGen
(`ASTLoweringRequest`), from the mangler's round-trip self-check
(`Mangler.cpp:176`). Only assertions-enabled compilers run that check; release
toolchains compile the code.

## Minimal reproducer

Two modules, no package dependencies: [`defining.swift`](defining.swift) (module
`M`) and [`consumer.swift`](consumer.swift) (module `N`), built by
[`build.sh`](build.sh):

```bash
swiftc -swift-version 6 -enable-experimental-feature SuppressedAssociatedTypes \
  -enable-experimental-feature Lifetimes -wmo -parse-as-library \
  -emit-module -emit-module-path M.swiftmodule -module-name M defining.swift
swiftc -swift-version 6 -enable-experimental-feature SuppressedAssociatedTypes \
  -enable-experimental-feature Lifetimes -wmo -parse-as-library \
  -c consumer.swift -I . -module-name N -o n.o
```

The trigger in `consumer.swift`: `Vec` conforms to `Iterable2`, whose `Iterator` is
bound with `@_implements` to `Mat<Vec.Iterator>`, an adapter over `Vec`'s own
nested `~Copyable` iterator:

```swift
extension Vec: Iterable2 where Bound: Copyable {
    @_implements(Iterable2, Iterator)
    public typealias IterableIterator = Mat<Iterator>

    @_lifetime(borrow self)
    @_implements(Iterable2, makeIterator())
    public borrowing func iterableMakeIterator() -> Mat<Iterator> { ... }
}
```

**Actual** (Swift 6.3.3-dev, `c83acbf89dd1298`, assertions on;
[`repro-crash-6.3.3-dev.log`](repro-crash-6.3.3-dev.log)):

```
Abort: function verify at Mangler.cpp:176
Can't demangle: $s1M3VecV1NE20iterableMakeIteratorAA3MatVyAcARi_zrlE0D0Vyx_GAjA5IterPAD_HCg_GyF
3.	While evaluating request ASTLoweringRequest(Lowering AST to SIL for module N)
```

The mangler produces a name for the `iterableMakeIterator` witness and then cannot
demangle it.

**Expected:** module `N` compiles. The witness's mangled name should round-trip.

[`Package.swift`](Package.swift) is a nested manifest for the same two files
(targets `M` and `N`, with `-whole-module-optimization`), added with the lint
exception in `5d4e647`.

## Trigger characterization

From the record's ingredient matrix (assertions toolchain):

| Ingredient | Removed / replaced by | Result |
|---|---|---|
| `Iterable2` conformance with the `@_implements` witness | conformance dropped | compiles |
| `Iterable2.Iterator` bound to an adapter over `Vec`'s own nested iterator | adapter over a shared element-generic iterator | compiles |
| `Seqable` conformance | dropped | **still aborts** |
| dual `makeIterator`, `IteratorProtocol`, `Sequence` conformances | dropped | **still aborts** |

In the real package a second trait mattered: `Vector<Bound: ~Copyable>` is generic
over its element directly, and the conformance re-constrains it with
`where Bound: Copyable`. Packages with only one of the two traits compiled clean.
That second trait was not isolated in the reducer.

The record also says the result on toolchains without assertions is fragile for the
synthetic reducer (an unrelated edit could change it on an Apple host). The
assertions crash is described as robust.

## Toolchains

| Toolchain | Result |
|---|---|
| Swift 6.3.2, assertions on, Windows (CI) | **aborts** (real package) |
| Swift 6.3.0-dev (`f30e11b820448ef`), assertions on, `swiftlang/swift:nightly-6.3-jammy` | **aborts** |
| Swift 6.3.3-dev (`c83acbf89dd1298`), assertions on, same image | **aborts** (reducer and real package) |
| Apple Swift 6.3.2, macOS | compiles |
| `swift:6.3` Linux release | compiles; 106 tests pass (real package) |
| Apple Swift 6.4.2 (`swiftlang-6.4.2.1.9`), macOS arm64, 2026-10-27 | compiles (`sh build.sh .` prints `[[ALL-OK]]`). No assertions, so this says nothing about the fix. |
| Swift 6.4 or later, assertions on | **unknown** |

## How it was found

Windows CI on `swift-primitives/swift-vector-primitives` at `6b85557`, target
`Vector Primitives`. The investigation started from a presumed `Sequenceable`
cause; the abort symbol and the ingredient matrix showed it is the `Iterable`
witness (see "Reconciliation" in `CHARACTERIZATION.md`).

## Workaround

Bind the associated type to an adapter over a shared, element-generic iterator
instead of the type's own nested iterator. In `swift-vector-primitives` (applied
2026-06-26) the scalar iterator is wrapped in `Iterator.Witness<Bound, Never>`
before `Iterator.Materializing`. After it, the assertions build completed and the
macOS tests passed (106 tests in 25 suites).

## Harness

None in the Issues package. This entry has no `Sources/` or `Tests/` and no
targets in the root `Package.swift`. The reducer is already dependency-free, so a
harness is possible: compile the two files out of process, as other entries do. It
would only detect the bug on an assertions toolchain.

## Other file in this directory

[`vector-iterable-mangler-sigabrt-reproducer.swift`](vector-iterable-mangler-sigabrt-reproducer.swift)
is a **different bug**. Its header describes an abort in
`GenericSpecializationMangler.cpp:47` (`demangleAndAddAsChildren`) during the
`EarlyPerfInliner` pass at `-O`, found in swift-graph-primitives. It was added in
`274d090` (2026-07-05, "relocated from workspace root") and renamed from
`swift-graph-primitives-sigabrt-reproducer.swift` in `e60b97f`. Which toolchain it
crashed on is not recorded. On Apple Swift 6.4.2 (macOS arm64, 2026-10-27),
`swiftc -O` on it compiles cleanly (exit 0); that toolchain has no assertions.

## Provenance

- Investigation 2026-06-26; first committed in `fafcde6`. The name replaced the
  handoff's `…vector-sequenceable-windows-asserts-ice` (slug note in
  `CHARACTERIZATION.md`).
- Renamed reproducer file in `e60b97f` for
  [swift-institute/Issues#74](https://github.com/swift-institute/Issues/issues/74).
- Inventory: [#69](https://github.com/swift-institute/Issues/issues/69) lists it as
  "eligible-unfiled".
- Real package: `swift-primitives/swift-vector-primitives` `6b85557`; its log is
  [`real-package-crash-6.3.3-dev.log`](real-package-crash-6.3.3-dev.log).
- Related, same check class: [`../swift-issue-typed-throws-typealias-windows-asserts-ice/`](../swift-issue-typed-throws-typealias-windows-asserts-ice/)
  (`getMangledName` in IRGen debug info).
- Full characterization: [`CHARACTERIZATION.md`](CHARACTERIZATION.md).
