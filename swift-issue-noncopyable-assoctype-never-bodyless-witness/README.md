# `swift-issue-noncopyable-assoctype-never-bodyless-witness`

A protocol declaring `associatedtype Body: ~Copyable` plus a property
requirement of that type, with an extension default for `Body == Never`,
causes `swift-frontend` to emit the default's `read` accessor into any
**consumer** module that adds a `Body == Never` conformance as a
`shared [serialized]` SIL function with **no body**. Wherever SIL
verification runs, compilation of the consumer module aborts (signal 6 /
exception `0x80000003` on Windows):

```
<unknown>:0: note: Must have a construct to emit for                       # 6.3-line wording
SIL verification failed: public/package/shared function must have a body:  # +assertions wording
  F->isDefinition() || F->hasForeignBody()
// P<>.body.read
sil shared [serialized] @… : $@yield_once @convention(method)
  <τ_0_0 where τ_0_0 : P, τ_0_0.Body == Never, τ_0_0 : ~Copyable>
  (@in_guaranteed τ_0_0) -> @yields Never
```

On a NoAsserts RELEASE toolchain (stock macOS/Linux) the malformed SIL is
emitted but never verified — the bug is **latent**, not absent. That is why
macOS/Linux CI legs pass while Windows (+Asserts) and Embedded legs crash on
identical code.

## Minimal reproduction

Two files, two bare `swiftc` invocations, no dependencies
(`Sources/Reproducer/Core.swift.txt` + `Consumer.swift.txt`):

```swift
// module M (Core.swift.txt)
public protocol P: ~Copyable {
    associatedtype Body: ~Copyable          // load-bearing
    var body: Body { borrowing get }
}
extension P where Self: ~Copyable, Body == Never {
    @inlinable public var body: Never { borrowing get { fatalError() } }
}
public struct InCore: P { public typealias Body = Never; public init() {} }  // load-bearing

// module N (Consumer.swift.txt)
public import M
public struct Use: P { public typealias Body = Never; public init() {} }     // crash site
```

```sh
swiftc -enable-experimental-feature SuppressedAssociatedTypes \
       -wmo -parse-as-library -emit-module \
       -emit-module-path M.swiftmodule -module-name M Core.swift    # exit 0, always
swiftc -enable-experimental-feature SuppressedAssociatedTypes \
       -Xfrontend -sil-verify-all \
       -wmo -parse-as-library -c Consumer.swift -I . -module-name N # abort
```

Load-bearing ingredients (each verified by removal-then-rebuild):
`Body: ~Copyable` on the associated type (a Copyable `Body` is clean); the
`Body == Never` default; a `Body == Never` conformer in the **defining**
module; a `Body == Never` conformer in a **consumer** module; and active SIL
verification. NOT required: `@inlinable`, `borrowing get` (plain `get` also
crashes), the protocol itself being `~Copyable`, generics on conformers.

**Module boundary is load-bearing**: compiling both declaration sets as one
module under `-sil-verify-all` is clean (checked 2026-07-30, Apple Swift
6.4). The boundary is therefore expressed as two out-of-process frontend
invocations in the harness rather than as live SwiftPM targets — live targets
would crash every verification-enabled CI leg and be silently malformed
everywhere else.

## Affected Swift versions (each row confirmed 2026-07-30 via the two-invocation probe, macOS arm64)

| Toolchain | Result |
|---|---|
| 6.3.3-RELEASE (swiftly) | **abort** — `Must have a construct to emit for` |
| Apple Swift 6.4 (Xcode) | **abort** — `shared function must have a body` |
| main-snapshot-2026-07-11 (+assertions) | **abort** — `shared function must have a body` |

Earlier records additionally confirmed: stock Xcode 6.3.2, 6.5-dev snapshot
2026-05-27 (both Embedded and non-Embedded), and Windows 6.3.2-RELEASE
(+Asserts). **Not fixed on any tested toolchain.**

## Harness

Repository two-target convention with the sillinker entry's out-of-process
two-invocation shape: `…-Tests` wraps the probe in `withKnownIssue` with
`when: { true }` (green while the bug fires; **red the moment the consumer
module compiles cleanly** — the fix-detection signal); `…-Repro` is the same
probe standalone (exit 1 = fires, 0 = fixed, 2 = inconclusive). The defining
module's clean build is the probe's positive control.

## Upstream

**Destination**: `swiftlang/swift`.
**Search (2026-07-30, `"Must have a construct to emit for"`)**: 1 hit,
[swiftlang/swift#90643](https://github.com/swiftlang/swift/pull/90643) — a
SILVerifier error-reporting PR, not this defect. Closely related family:
[swiftlang/swift#90406](https://github.com/swiftlang/swift/issues/90406)
(the sibling entry
[`swift-issue-sillinker-borrowed-protocol-default-shared-coroutine-abort`](../swift-issue-sillinker-borrowed-protocol-default-shared-coroutine-abort/README.md))
— the same "bodiless `shared [serialized]` extension-default coroutine
crossing a module boundary" verifier class, there triggered by a `@_borrowed`
requirement's defaulted subscript, here by a `~Copyable` associated type
bound to `Never`. Whether they share a fix is a maintainer determination.
**Searched, no exact match — ELIGIBLE to file** (with the #90406 relation
stated); filing remains principal-gated.

## Workaround

Structural only: the defining module must contain **no** `Body == Never`
conformer (relocate it to a separate target). Applied in
`swift-serializer-primitives` (the `Serializer.Witness` type and conformance
moved to a `Serializer Witness Primitives` target), verified clean on stock
6.3.2 + `-sil-verify-all` and Embedded 6.5-dev. Attribute suppressions
(`@_optimize(none)`, `@inline(never)`, `@_alwaysEmitIntoClient`) do not help —
the failure is verification of emitted SIL, not optimization.

## Provenance (Institute discovery context)

Surfaced by `swift-primitives/swift-serializer-primitives` (target
`Serializer Trace Primitives`) crashing the Windows CI compiler (run
`28169921710`, job `83431175554`) and the Embedded build; every
`Body == Never` leaf combinator is latently affected. Full
ingredient-by-ingredient reduction, platform-matrix explanation, and the
principal's fix decision: [INVESTIGATION-ARC.md](INVESTIGATION-ARC.md).
Related-but-distinct sibling input crash:
`swift-issue-typed-throws-never-witness-effects-assertion`.
