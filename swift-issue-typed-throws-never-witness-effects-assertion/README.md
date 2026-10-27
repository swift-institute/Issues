# Swift Issue: Sema assertion "witness has more effects than requirement" when a `throws(Never)` default `next()` competes for `IteratorProtocol.next()`

**Upstream:** **NOT FILED.** No upstream duplicate search is recorded. The bug is
fixed on the 6.4 line and on 6.5-dev, so a filing could at most ask for a 6.3.x
backport; the record chose not to (see [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md)).

**Status:** FIXED on Swift 6.4 (6.4.x snapshot 2026-07-23, with assertions) and on
6.5-dev. Seen only on Windows CI with Swift 6.3.2-RELEASE, which has assertions.

**Classification:** Compiler crash. An `assert()` in Sema
(`lib/Sema/TypeCheckProtocol.cpp:1311`) fires while resolving value witnesses. It
needs an assertions-enabled compiler; release toolchains without assertions compile
the code.

## Minimal reproducer

There is no dependency-free reproducer. [`repro.swift`](repro.swift) is a model of
the crashing test file. It depends on two swift-iterator-primitives products
(`Iterator Chunk Primitives`, `Iterable`), so it is not a target of the Issues
package. It must be dropped into a SwiftPM target with those dependencies and the
ecosystem settings listed in its header.

The crashing shape: one extension makes a nested generic iterator conform both to
a chunk-iterator protocol and to `IteratorProtocol`:

```swift
extension TestColl.Iterator: Iterator.Chunk.`Protocol`, IteratorProtocol {
    typealias Failure = Never
    mutating func next(maximumCount: some Carrier.`Protocol`<Cardinal>) -> Span<Element> { ... }
    mutating func next() -> Element? { ... }
}
```

The chunk protocol has an extension, for `Element: Copyable`, that supplies a
default `mutating func next() throws(Failure) -> Element?`. With `Failure == Never`
that default competes with the hand-written `next()` as the witness for the
non-throwing `IteratorProtocol.next()`.

**Actual** (Swift 6.3.2-RELEASE, assertions on, `x86_64-unknown-windows-msvc`):

```
Assertion failed: getEffects(req).contains(getEffects(witness)) &&
    "witness has more effects than requirement?",
    file ...\swift\lib\Sema\TypeCheckProtocol.cpp, line 1311
6. While evaluating request ResolveValueWitnessesRequest(
       <Element where Element : Sendable> TestCollection<Element>.Iterator: IteratorProtocol ...)
Exception Code: 0x80000003
```

**Expected:** the conformance type-checks. A `throws(Never)` witness is non-throwing,
and the hand-written `next()` is a valid witness in any case.

## Trigger characterization

What the record supports:

| Ingredient | Evidence |
|---|---|
| A default `next() throws(Failure)` from a second protocol's extension, with `Failure == Never` | the derived witness named in the root-cause analysis |
| Both conformances declared in one extension | the crashing declaration |
| Default witness from another module | the cross-module model is described as the faithful one |
| An assertions-enabled compiler | release toolchains compile the same code |

Not established:

- A dependency-free, same-module stand-in (an `Int` count instead of
  `Carrier.Protocol<Cardinal>`) was clean on 6.3.2 without assertions and on 6.5-dev.
  No available toolchain both predates the fix and has assertions, so it is
  **unknown** whether that stand-in triggers the bug.
- A neutral `Chunked` stand-in (single-module and cross-module) was clean on the 6.4
  and 6.5 snapshots. For the same reason it cannot be confirmed as a reproducer.
- Whether the backtick-escaped `Protocol` spelling or the `Carrier`/`Cardinal` types
  matter is **unknown**.

## Toolchains

| Toolchain | Result |
|---|---|
| Swift 6.3.2-RELEASE, assertions on, Windows x86_64 (CI) | **asserts** |
| Swift 6.3.2 snapshots without assertions, macOS | compiles (assertion compiled out) |
| Swift 6.4.x snapshot 2026-07-23, assertions on | compiles (`repro.swift`, imports updated to today's module names) |
| Swift 6.5-dev (`org.swift.64202605271a`), assertions on | compiles (`repro.swift` and the real test target) |

Not run on Xcode Swift 6.4.2 for this README: it has no assertions, and
`repro.swift` needs package dependencies.

## How it was found

`swift-primitives/swift-input-primitives` CI run `28169939296`, job `83431230550`
(`Windows (Swift 6.3, debug)`), on the test file `Input.Slice Tests.swift:31`.
macOS and Linux legs passed because their toolchains have no assertions.

## Workaround

None was applied in this record. It listed three test-side options: guard the
extension with `#if !os(Windows)`; drop the `IteratorProtocol` conformance if the
tests do not need `for-in`; or make the `next()` witness unambiguous. Since the fix
is in 6.4, none is needed once Windows CI is on 6.4 or later.

## Harness

None. This entry has no `Sources/` or `Tests/` and no targets in the root
`Package.swift`. A harness would need a dependency-free trigger and an
assertions toolchain where the bug still fires; neither exists here.

## Provenance

- Investigation 2026-06-25; first committed in `658830a` (2026-06-25).
- 6.4 re-check and closure as fixed: 2026-10-11, commit `6f5c80e`.
- Tracker: [swift-institute/Issues#75](https://github.com/swift-institute/Issues/issues/75)
  (half 2, "resolved", record `6f5c80e1d23ec02e931e0eee20550a0adff45de7`) and the
  inventory in [#69](https://github.com/swift-institute/Issues/issues/69), which
  flags `repro.swift` for Institute types in the reproducer.
- Sources named in the record: `Input.Slice Tests.swift:31`;
  `swift-iterator-primitives/Sources/Iterator Chunk Primitives/Iterator.Chunk.Protocol.swift:15-27`.
- Related, distinct: [`../swift-issue-noncopyable-assoctype-never-bodyless-witness/`](../swift-issue-noncopyable-assoctype-never-bodyless-witness/).
- Full investigation: [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md).
