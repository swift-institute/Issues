# Swift 6.3.2 — bodyless `shared [serialized]` default-witness `read` accessor for a `~Copyable` associated-type property bound to `Never` (cross-module)

**Status**: VERIFIED — empirically reproduced with a 2-file standalone reducer on **stock Apple Swift 6.3.2 (Xcode)** using `-Xfrontend -sil-verify-all`, and on Swift 6.5-dev (`org.swift.64202605271a`) both in Embedded mode and non-Embedded. The bug is **NOT fixed on 6.5-dev**. Surfaced by `swift-serializer-primitives` (target `Serializer Trace Primitives`) crashing the Windows CI compiler and the Embedded build.

**Classification**: ICE — SIL verification failure (`SILType.h`-class invariant: a `public/package/shared` SIL function must have a body / "Must have a construct to emit for").

**Standing policy note**: per [ISSUE-008] (principal, 2026-06-11) and the standing upstream-filing policy, upstream filing at swiftlang does **not** exist as a step. This dossier is the terminal record. The parent handoff (an internal working document) requested "file the swift.org bug" — that instruction conflicts with standing policy and was **not** executed; the conflict is surfaced to the principal.

---

## Crash Signature

The crashing SIL function is the same across platforms (demangles to
`Serializer.Protocol.body.read` constrained `where Body == Never, Self: ~Copyable`):

**Windows** — `swift-primitives/swift-serializer-primitives` CI run `28169921710`, job `83431175554` (`Windows (Swift 6.3, debug)`), Swift 6.3.2-RELEASE (+Asserts), `x86_64-unknown-windows-msvc`:

```
[89/166] Compiling Serializer_Trace_Primitives exports.swift
error: emit-module command failed due to exception 3
<unknown>:0: error: fatal error encountered during compilation
<unknown>:0: note: Must have a construct to emit for
3. While evaluating request ASTLoweringRequest(Lowering AST to SIL for module Serializer_Trace_Primitives)
4. While verifying SIL function "@$s20Serializer_Primitive0A0O8ProtocolPAAs5NeverO4BodyRtzRi_zrlE4bodyAGvr".
   for read for body (in module 'Serializer_Primitive')
Exception Code: 0x80000003
```

**Local Embedded** — Swift 6.5-dev, `arm64-apple-macos26`, `-enable-experimental-feature Embedded`:

```
SIL verification failed: public/package/shared function must have a body: F->isDefinition() || F->hasForeignBody()
// Serializer.Protocol<>.body.read
sil shared [serialized] @$e20Serializer_Primitive0A0O8ProtocolPAAs5NeverO4BodyRtzRi_zrlE4bodyAGvr :
  $@yield_once @convention(method) <τ_0_0 where τ_0_0 : Serializer.`Protocol`, τ_0_0.Body == Never, τ_0_0 : ~Copyable>
  (@in_guaranteed τ_0_0) -> @yields Never
4. While verifying SIL function "...body.read" for read for body (in module 'Serializer_Primitive')
```

Same function, same module of origin (`Serializer_Primitive`), differing only in mangling prefix (`@$s` stable vs `@$e` embedded) and verifier wording.

---

## Root cause

`Serializer.Protocol` (in `Serializer_Primitive`) declares an associated type
`Body: ~Copyable` and a `var body: Body { borrowing get }` requirement. A default
implementation supplies `body` for leaf serializers (`Sources/Serializer Primitive/Serializer.Protocol.swift:73-81`):

```swift
extension Serializer.`Protocol` where Self: ~Copyable, Body == Never {
    @inlinable public var body: Never { borrowing get { fatalError(...) } }
}
```

The property's `read` accessor lowers to a `@yield_once` coroutine yielding the
**uninhabited** `Never`. When a type with `Body == Never` conforming to the protocol
appears in a **consumer** module, the consumer's witness table references this default
accessor, and the compiler emits it into the consumer module as a `shared [serialized]`
SIL function — **with no body**. The SIL verifier rejects a bodyless
public/package/shared function.

### Why the platform matrix looks the way it does

The malformed (bodyless) SIL is emitted on **every** platform. It only becomes a
*crash* when SIL verification actually runs:

| Toolchain / mode | SIL verification | Result |
|---|---|---|
| macOS / Linux RELEASE (NoAsserts) | off by default | silent success — **latent** malformed SIL |
| Windows 6.3.2-RELEASE (+Asserts) | on | **crash** |
| Embedded (any toolchain) | always | **crash** |
| Any toolchain + `-Xfrontend -sil-verify-all` | forced on | **crash** |

This is why macOS/Linux CI legs pass while Windows + Embedded fail on identical code.

---

## Reduced Trigger / Reproducer

2-file standalone reducer — see [`repro-core.swift`](./repro-core.swift) (module `M`)
and [`repro-consumer.swift`](./repro-consumer.swift) (module `N`). Reproduces on
**stock Xcode Swift 6.3.2** with `-Xfrontend -sil-verify-all`, emitting the exact
Windows note "Must have a construct to emit for". No SwiftPM, no dependencies.

```swift
// module M
public protocol P: ~Copyable {
    associatedtype Body: ~Copyable
    var body: Body { borrowing get }
}
extension P where Self: ~Copyable, Body == Never {
    @inlinable public var body: Never { borrowing get { fatalError() } }
}
public struct InCore: P { public typealias Body = Never; public init() {} }

// module N
public import M
public struct Use: P { public typealias Body = Never; public init() {} }
```

### Required ingredients ([ISSUE-004], each verified by removal-then-rebuild)

1. **`associatedtype Body: ~Copyable`** — REQUIRED. With a Copyable `Body` (no `~Copyable`) it is clean. (The protocol/`Self` being `~Copyable` is *not* required — only the associated type.)
2. **A property requirement of that associated type + a `Body == Never` default returning `Never`** — REQUIRED.
3. **A `Body == Never` conformer in the *defining* module** (models `Serializer.Witness`) — REQUIRED. Removing it makes the build clean (the generic default is then never serialized into the defining `.swiftmodule`).
4. **A `Body == Never` conformer in a *consumer* module** (models `Serializer.Trace`) — REQUIRED; this is where the bodyless function is emitted/verified.
5. **SIL verification active** (+Asserts toolchain, Embedded, or `-sil-verify-all`) — required to surface the crash; otherwise latent.

NOT required (verified by removal): `@inlinable` on the default; `borrowing get` (plain `get` also crashes); the `@Serializer.Builder` result builder; the package's experimental feature flags (`Lifetimes`, `LifetimeDependence`, etc.); the protocol being `~Copyable`; generics on the conformers.

### Scope correction — this affects ALL leaf combinators, not just Trace

The Windows build halted at `[89/166] … Serializer_Trace_Primitives` simply because
Trace was the first `Body == Never` consumer module reached. A two-consumer test
(Trace + a Map-shaped consumer) crashes on **both**. Every leaf combinator in
`swift-serializer-primitives` (`Map`, `Optional`, `Many`, `Filter`, `Lazy`,
`Literal`, `Always`, `Fail`, `Trace`, `Tagged`) shares the `Body == Never` leaf
pattern and is latently affected; they pass on macOS/Linux only because verification
is off there.

---

## Workarounds attempted (on the production-faithful 2-module copy, Embedded)

| Attempt | Result |
|---|---|
| `@_optimize(none)` on the leaf-default `body` | ❌ still crashes (verification, not optimization) |
| `@inline(never)` on the leaf-default `body` | ❌ still crashes |
| `@_alwaysEmitIntoClient` on the leaf-default `body` | ❌ still crashes |
| Give the in-core `Serializer.Witness` an explicit `var body: Never` instead of the default | ❌ does not compile — the `@Serializer.Builder<Buffer>` result builder then applies to it and demands `Never: Serializer.Protocol` |
| **Remove the in-core `Body == Never` conformer from `Serializer_Primitive`** (relocate `Serializer.Witness`'s conformance to a separate target) | ✅ **CLEAN** — the only working mitigation found |

The only verified fix is structural (ingredient #3): the defining module
`Serializer_Primitive` must contain **no** `Body == Never` conformer. The leaf-default
itself can stay; consumer modules using it across the boundary are fine *as long as*
the defining module does not also instantiate it. A `#if !os(Windows) / #if !hasFeature(Embedded)`
guard does **not** apply cleanly here — guarding the leaf-default out leaves every leaf
conformer without a `body` witness (compile error), and the malformed SIL is emitted on
all platforms anyway (it is merely unverified on RELEASE).

**This is a [ISSUE-022] design decision (multiple shapes) and was NOT applied** — see
"Resolution / decisions for the principal" below.

---

## Resolution / decisions for the principal

1. **Fix shape** (structural; the only verified mitigation is relocating the in-core
   `Serializer.Witness` conformance out of `Serializer_Primitive`). Candidate shapes:
   (a) move `Serializer.Witness` + its conformance to a new sibling target;
   (b) restructure the leaf-default so the defining module never instantiates the
   serialized accessor; (c) accept Windows/Embedded RED until the toolchain advances
   (the bug is unfixed on 6.5-dev, so "wait for release" does not resolve it soon).
   **RESOLVED 2026-06-25**: principal chose option (a) — `Serializer.Witness` (type +
   conformance) relocated to a new `Serializer Witness Primitives` target. Applied + pushed
   (`swift-primitives/swift-serializer-primitives` `a652cec`); verified clean on stock Xcode
   6.3.2 + `-sil-verify-all` and Embedded on 6.5-dev. The underlying compiler bug remains
   UNFIXED upstream — this is a workaround (re-test on toolchain advances).
2. **Upstream**: standing policy forbids filing; this dossier is terminal.

## Removal / re-test condition

Re-test on each new toolchain via the 2-file reducer with `-sil-verify-all`. The bug is
**unfixed as of Swift 6.5-dev (2026-05-27 snapshot)**.

## Provenance

- Investigation: 2026-06-25, `/issue-investigation` per an internal working document.
- Windows evidence: `swift-primitives/swift-serializer-primitives` CI run `28169921710`, job `83431175554`.
- Local repro vehicle: real `Serializer Primitive` + `Serializer Trace Primitives` sources as two `swiftc` modules (Embedded, 6.5-dev) and the 2-file standalone reducer (stock Xcode 6.3.2 + `-sil-verify-all`).
- Root-cause source: `swift-serializer-primitives/Sources/Serializer Primitive/Serializer.Protocol.swift:73-81` (leaf-default `body`); in-core conformer `Serializer.Witness+Protocol.swift:13-22`.

## Cross-references

- [ISSUE-002] Standalone Reproducer · [ISSUE-004] Required Ingredient Verification · [ISSUE-005] SIL `-sil-verify-all` as disambiguator (the key technique here) · [ISSUE-008] Resolution Paths · [ISSUE-022] Ask before designing the fix · [ISSUE-028] Compiler Bug Catalog (amended)
- [PKG-BUILD-007]/[PKG-BUILD-008] Embedded build mode
- Related (distinct): `swift-issue-typed-throws-never-witness-effects-assertion` (the sibling input crash, fixed on 6.5-dev)
