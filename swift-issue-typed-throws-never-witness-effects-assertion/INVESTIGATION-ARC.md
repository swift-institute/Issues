# Swift 6.3.2 — Sema assertion `getEffects(req).contains(getEffects(witness))` resolving `IteratorProtocol.next()` against a `throws(Never)` competing witness

**Status**: VERIFIED on Windows (CI). **FIXED on Swift 6.5-dev** — the real
`swift-input-primitives` test target and a faithful cross-module model both build clean
on 6.5-dev (`org.swift.64202605271a`, +Asserts). A +Asserts-only Sema assertion; not
reproducible on the NoAsserts RELEASE toolchains available locally, and not on 6.5-dev
(fixed). Surfaced by `swift-input-primitives` test `Input.Slice Tests.swift:31`.

**Classification**: ICE — Sema assertion (`assert()` in `lib/Sema/TypeCheckProtocol.cpp:1311`), `+Asserts` builds only.

**Standing policy note**: per [ISSUE-008] / the standing upstream-filing policy, no upstream filing. The parent handoff's "file the swift.org bug" instruction conflicts with policy and was not executed (surfaced to principal). Since the bug is fixed on dev, a filing would be a 6.3.x-backport ask at most — not pursued.

---

## Crash Signature

`swift-primitives/swift-input-primitives` CI run `28169939296`, job `83431230550`
(`Windows (Swift 6.3, debug)`), Swift 6.3.2-RELEASE (+Asserts), `x86_64-unknown-windows-msvc`:

```
Assertion failed: getEffects(req).contains(getEffects(witness)) &&
    "witness has more effects than requirement?",
    file ...\swift\lib\Sema\TypeCheckProtocol.cpp, line 1311
3. While evaluating request TypeCheckPrimaryFileRequest(... Input.Slice Tests.swift)
4. While type-checking extension of TestCollection.Iterator (... :31:1)
5. While type-checking protocol conformance TestCollection<Element>.Iterator: IteratorProtocol (... :31:1)
6. While evaluating request ResolveValueWitnessesRequest(
       <Element where Element : Sendable> TestCollection<Element>.Iterator: IteratorProtocol ...)
Exception Code: 0x80000003
```

---

## Root cause

The crashing declaration (`Tests/Input Primitives Tests/Input.Slice Tests.swift:31`)
co-conforms a nested generic iterator to two protocols in one extension:

```swift
extension TestCollection.Iterator: Iterator.Chunk.`Protocol`, IteratorProtocol {
    typealias Failure = Never
    @_lifetime(&self)
    mutating func next(maximumCount: some Carrier.`Protocol`<Cardinal>) -> Span<Element> { ... }
    mutating func next() -> Element? { ... }
}
```

`Iterator.Chunk.`Protocol`` (= `__IteratorChunkProtocol`, in `swift-iterator-primitives`)
provides, for `Element: Copyable`, a *derived* scalar witness
(`Iterator.Chunk.Protocol.swift:15-27`):

```swift
extension Iterator.Chunk.`Protocol` where Self: ~Copyable & ~Escapable, Element: Copyable {
    @inlinable public mutating func next() throws(Failure) -> Element? { ... }   // throws(Never)
}
```

When the compiler resolves the witness for stdlib `IteratorProtocol.next()` (a
**non-throwing** requirement), the `throws(Failure)` = `throws(Never)` derived `next()`
is a candidate. Its effect set carries a `throws` effect that the requirement's does
not, and the effects-containment sanity assertion
(`getEffects(req).contains(getEffects(witness))`) fires before the `throws(Never)` is
reduced to "non-throwing". (The explicitly-written `next() -> Element?` is also present,
making this a witness-contention situation under typed throws.)

### Why the platform matrix looks the way it does

The assertion is a `+Asserts`-only check. On NoAsserts RELEASE toolchains (stock
macOS/Linux) it is compiled out, so those CI legs pass; only the +Asserts Windows
toolchain trips it. On Swift 6.5-dev the underlying handling is fixed, so even +Asserts
no longer asserts.

---

## Reproducer

[`repro.swift`](./repro.swift) — a faithful cross-module model (depends on the real
`Iterator Chunk Primitives` + `Iterable`). It reproduces the *shape* exactly but builds
clean on every toolchain available in this workspace (6.3.2 snapshots are NoAsserts;
6.5-dev has the fix). The assertion therefore only manifests on a 6.3.2 **+Asserts**
toolchain — the Windows CI run is the reproduction of record.

A self-contained, dependency-free variant (`Int` count instead of
`Carrier.Protocol<Cardinal>`, same-module protocol) was also tried and is clean on
6.3.2-NoAsserts and 6.5-dev; the cross-module derived-`next()` form above is the faithful
one.

### Verification that it is FIXED on 6.5-dev ([ISSUE-001])

- `TOOLCHAINS=org.swift.64202605271a swift build --build-tests` on the **real**
  `swift-input-primitives` → `Build complete!`, zero crash markers; `Input.Slice Tests.swift`
  compiled (an unrelated warning is emitted from line 36, proving the file type-checked).
- The cross-module `repro.swift` model also builds clean on 6.5-dev (+Asserts).

### Coverage scope ([ISSUE-026])

Confirmed FIXED on 6.5-dev; confirmed PRESENT on 6.3.2 (+Asserts, Windows CI). The exact
6.4-stable status was **not** locally verifiable (no 6.3.2/6.4 +Asserts toolchain on this
machine; the local 6.3.2 snapshots are NoAsserts). Conclusion: present on the shipping
Windows 6.3.2 toolchain, fixed by 6.5-dev.

---

## Resolution ([ISSUE-008]: fixed-on-dev)

Because the Windows toolchain is 6.3.2-RELEASE (+Asserts) and will not receive the fix
until it advances to ≥ a toolchain carrying it, a **test-code workaround** is needed to
turn Windows CI green now. This is TEST code, so options are low-stakes but still a shape
choice (decision for the principal):

1. `#if !os(Windows)` guard the dual-conformance extension (and any test using it) —
   disables those tests on Windows until the toolchain advances.
2. Drop the explicit `IteratorProtocol` conformance from `TestCollection.Iterator` if the
   tests do not rely on stdlib `for-in` over it (the crash is on that conformance).
3. Disambiguate the `next()` witness so the `throws(Never)` derived candidate is not
   considered.

**Not applied** — surfaced for a principal decision per [ISSUE-022].

## Removal / re-test condition

Remove any workaround once the Windows CI toolchain ships a Swift carrying the 6.5-dev
fix. Re-test with `repro.swift` against a 6.3.2/6.4 +Asserts toolchain if one becomes
available locally.

## Provenance

- Investigation: 2026-06-25, `/issue-investigation` per an internal working document.
- Windows evidence: `swift-primitives/swift-input-primitives` CI run `28169939296`, job `83431230550`.
- Fix confirmation: `swift build --build-tests` on the real package, 6.5-dev (`org.swift.64202605271a`).
- Sources: crashing conformance `Input.Slice Tests.swift:31`; derived witness `swift-iterator-primitives/Sources/Iterator Chunk Primitives/Iterator.Chunk.Protocol.swift:15-27`; protocol `__IteratorChunkProtocol.swift:42-65`; `Iterable.swift:46`.

## Cross-references

- [ISSUE-001] Check Dev Toolchain First (bug passes on 6.5-dev) · [ISSUE-008] Resolution Paths · [ISSUE-022] Ask before designing the fix · [ISSUE-026] Negative-experiment coverage scope · [ISSUE-028] Compiler Bug Catalog (amended)
- Related (distinct, UNFIXED): `swift-issue-noncopyable-assoctype-never-bodyless-witness` (the sibling serializer crash)
- The sibling typed-throws-in-`#expect` SIL crash already worked around in `Input.Buffer Tests.swift` / `Input.Slice Tests.swift:377-381` is a *third*, distinct bug.
