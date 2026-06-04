# Swift Issue: Bogus 'does not conform' error when a conditional extension declares a typealias named after an enclosing type's generic parameter

**Upstream:** **FILED — [swiftlang/swift#89684](https://github.com/swiftlang/swift/issues/89684)** (2026-06-04). Standalone single-file `swiftc -typecheck` reducer per the [ISSUE-002] gold standard.

**Classification:** Rejects-valid (alternatively: name-lookup inconsistency + wrong diagnostic).

When a **conditional extension** of a nested generic type declares a member
`typealias` whose name matches an **enclosing type's generic parameter**,
references to that name inside the nested type's *declaring context* are
captured by the conditionally-available member: the compiler evaluates the
extension's condition against the open generic argument and emits a bogus
`type 'Substrate' does not conform to protocol 'P'` at the member's type
annotation. The annotation never asked for the member; the same reference
resolves fine everywhere else. No protocol requirement or associated type is
needed — a plain conditional `typealias` suffices.

## Minimal reproducer

`reproducer.swift` (4 declarations), checked with **bare `swiftc -typecheck`**
(no SwiftPM, no flags, no features):

```swift
public enum Outer<Element> {}

public protocol P {}

extension Outer {
    public struct Inner<Substrate> {
        internal var _x: Element   // error: type 'Substrate' does not conform to protocol 'P'
    }
}

extension Outer.Inner where Substrate: P {
    public typealias Element = Int
}
```

```
swiftc -typecheck reproducer.swift     # bogus rejection
```

**Observed:**

```
reproducer.swift:7:26: error: type 'Substrate' does not conform to protocol 'P'
 5 | extension Outer {
 6 |     public struct Inner<Substrate> {
 7 |         internal var _x: Element   // error: type 'Substrate' does not conform to protocol 'P'
   |                          `- error: type 'Substrate' does not conform to protocol 'P'
 8 |     }
 9 | }
```

**Expected:** clean compile, with `_x: Element` denoting the enclosing
`Outer`'s generic parameter — matching what the same annotation means with the
conditional extension absent, or placed in any other context (see the matrix).

## The inconsistency

Each row independently re-verified on all three toolchains below; `var`
annotated `Element` throughout. Rows 1, 2, and 4 carry discriminating
resolution probes (a `probe` function whose return type typechecks only under
the claimed resolution, plus a negative probe that must fail).

| # | Colliding member named `Element` | `var` location | Result |
|---|---|---|---|
| 1 | none | declaring context | compiles; resolves to the outer parameter |
| 2 | typealias in an **unconditional** extension | declaring context | compiles; **resolves to the member** (member-shadows-outer is the baseline rule) |
| 3 | typealias in a **conditional** extension | declaring context | **bogus error above** |
| 4 | same as 3 | a separate (unconditional) extension | compiles; resolves to the outer parameter — no capture |

Rows 3 and 4 cannot both be intended: the conditional member captures the name
in the declaring context but not in extension contexts. And under either
intended semantics row 3's behavior is wrong for an *open* generic
`Substrate`: the condition is not refuted, merely not provable, yet resolution
hard-fails instead of falling back to the outer parameter (row 1/4 behavior) —
with a diagnostic that mentions neither the name collision nor the conditional
extension.

**Variant:** the same defect reproduces with the conditional member being an
associated-type witness — `extension Outer.Inner: P2 where Substrate: P2 {
public typealias Element = Substrate.Element }` with `protocol P2 {
associatedtype Element }` rejects identically (diagnostic names `P2`). The
plain-typealias reduction above shows conformance/associated-type machinery is
incidental.

## CI validation (this entry is wired into the Issues repo CI)

Because the bug **rejects valid source**, the triggering source cannot be a
normal compiled target — it would fail the whole package build while the bug
lives. It ships as a **resource** (`Sources/Reproducer/Reject.swift.txt`) and
two harnesses typecheck it **out of process** via `swiftc -typecheck`:

- `Tests/Reproducer.swift` — Swift Testing harness wrapping the probe in
  `withKnownIssue(...)`. **Green while the bug fires; flips red the moment an
  upstream fix lands** and `Reject.swift.txt` typechecks cleanly (the weekly
  `nightly-main-jammy` cron makes the flip visible).
- `Sources/Reproducer/main.swift` — standalone exit-code probe (`exit(1)` bug
  fired / `exit(0)` absent or inconclusive).

The probe greps the subprocess stderr for the exact signature
`error: type 'Substrate' does not conform to protocol 'P'`; a rejection
*without* that signature (e.g. a future rephrased diagnostic) is treated as
inconclusive, not as a flip. The Windows leg is a no-op — the probe is
POSIX-only and `#else`-skips Windows.

## Toolchain matrix (each cell verified by running the reducer; versions `swift --version`-confirmed)

| Swift version | Toolchain | Result |
|---|---|---|
| 6.3.2 | Xcode default (`swiftlang-6.3.2.1.108 clang-2100.1.1.101`), arm64-apple-macosx26.0 | **REJECTS** (bogus error) |
| 6.4-dev | `2026-03-16-a` (`LLVM a3655ee8d8c4d74, Swift d13cbbfd336f246`), +assertions | **REJECTS** identically; no assertion fires |
| 6.5-dev | `2026-05-27-a` (`LLVM 8f81a64f6a8bcf6, Swift 4d0c97fa5b05711`), +assertions | **REJECTS** identically; no assertion fires |

Behavior is identical under `-swift-version 5` and `-swift-version 6`, and
with or without a fresh module cache. **Unfixed on the latest installed
6.5-dev snapshot.**

## Workarounds (all validated on every toolchain above)

| Workaround | Result | Notes |
|---|---|---|
| Rename the conditional member (or the generic parameter) | CLEAN | any non-colliding name compiles; `_x` resolves to the outer parameter |
| Move the member off the declaring context (row 4) | CLEAN | computed properties / methods only — **stored properties cannot move to an extension**, so a stored property typed by the outer parameter has no placement workaround |
| Associated-type-witness variant: `@_implements(P2, Element) public typealias _P2Element = Substrate.Element` | CLEAN | satisfies the requirement without introducing a member *named* `Element`; routing verified — a negative probe fails with `'Outer<String>.Inner<S>._P2Element' (aka 'Bool')`, i.e. the witness is `Substrate.Element`, not the outer parameter |

## Severity

Rejects-valid at `-typecheck` — a loud build-blocker for the affected shape,
not a miscompile. The worst-hit shape is a stored property typed by the
enclosing parameter (workaround limited to renaming). The diagnostic actively
misleads: it points at a conformance failure on an open generic argument
rather than at the name collision or the conditional extension.

## Provenance

Filed upstream 2026-06-04. This entry was landed by an **independent
verification session ("Assay", 2026-06-04)** that reproduced every claim in
the published issue body — reproducer diagnostic (byte-identical), all four
matrix rows (with positive + negative resolution probes), the
associated-type-witness variant, both environment lines, and all
workarounds including `@_implements` witness routing — on the three
toolchains in the matrix above, from clean caches, before consulting any
prior investigation records.
