# `swift-issue-noncopyable-assoctype-second-protocol-bodyless-witness`

A type that conforms, in its own module, to a protocol with
`associatedtype Body: ~Copyable` and a `body` property requirement gets a
`read` accessor with **`shared` linkage** — which is therefore not carried
in that module's `.swiftmodule`. When a **consumer** module declares a
**second** conformance of that same type to a protocol with an equivalent
requirement, the consumer's witness references that accessor and emits it
as a `shared [serialized]` SIL function with **no body**. Wherever SIL
verification runs, compilation of the consumer module aborts:

```
<unknown>:0: note: Must have a construct to emit for                       # 6.3-line wording
SIL verification failed: public/package/shared function must have a body:  # +assertions wording
  F->isDefinition() || F->hasForeignBody()
// Box.body.read
sil shared [serialized] @$s1M3BoxV4bodyxvr : $@yield_once @convention(method)
  <τ_0_0 where τ_0_0 : P> (@in_guaranteed Box<τ_0_0>) -> @yields @in_guaranteed τ_0_0
```

On a NoAsserts RELEASE toolchain the malformed SIL is emitted but never
verified — the bug is **latent**, not absent. That is why stock macOS/Linux
release legs pass while the `+assertions` nightly, Embedded and Windows legs
abort on identical code.

## Minimal reproduction

Two files, two bare `swiftc` invocations, no dependencies
(`Sources/Reproducer/Core.swift.txt` + `Consumer.swift.txt`):

```swift
// module M (Core.swift.txt)
public protocol P {
    associatedtype Body: ~Copyable          // load-bearing
    var body: Body { borrowing get }
}
public struct Box<Body: P>: P {             // the `: P` conformance is load-bearing
    public let body: Body
    public init(body: Body) { self.body = body }
}

// module N (Consumer.swift.txt)
public import M
public protocol S {
    associatedtype Body: ~Copyable          // load-bearing
    var body: Body { borrowing get }
}
extension Box: S where Body: S {}           // crash site
```

```sh
swiftc -enable-experimental-feature SuppressedAssociatedTypes \
       -wmo -parse-as-library -emit-module \
       -emit-module-path M.swiftmodule -module-name M Core.swift    # exit 0, always
swiftc -enable-experimental-feature SuppressedAssociatedTypes \
       -Xfrontend -sil-verify-all \
       -wmo -parse-as-library -c Consumer.swift -I . -module-name N # abort
```

Load-bearing ingredients (each verified by removal-then-rebuild on
6.4-dev +assertions, macOS arm64, 2026-07-30):

- `associatedtype Body: ~Copyable` on **both** protocols. A Copyable `Body`
  on either side is clean: the property is then accessed directly and no
  `read` coroutine is involved at all.
- The defining module's own conformance (`Box: P`). Without it `Box.body`
  keeps ordinary linkage and the consumer compiles clean.
- The second conformance being declared in the **consumer** module.
  Declaring `extension Box: S` in module M instead is clean.
- Active SIL verification (`-sil-verify-all`, `+Asserts`, Embedded, Windows).

**Not** required: `borrowing get` (plain `get` also crashes); the property
being stored (a computed `body` also crashes); generics on the conforming
type (a non-generic `Box` with `Body == Never` also crashes); optimization
(`-Onone` and `-O` both crash); whole-module (`-primary-file` also crashes);
cross-module optimization (`-enable-default-cmo` is not involved); either
protocol itself being `~Copyable`.

**Module boundary is load-bearing**: compiling both declaration sets as one
module under `-sil-verify-all` is clean (checked 2026-07-30, 6.4-dev
+assertions). The boundary is therefore expressed as two out-of-process
frontend invocations in the harness rather than as live SwiftPM targets —
live targets would abort every verification-enabled CI leg and be silently
malformed everywhere else.

## Affected Swift versions

Each row confirmed 2026-07-30 via the two-invocation probe on the shipped
resources, macOS arm64, `swift --version`-checked.

| Toolchain | With SIL verification | NoAsserts default |
|---|---|---|
| 6.3.3-RELEASE (swiftly) | **abort** — `Must have a construct to emit for` | clean (latent) |
| Apple Swift 6.4 (Xcode, swiftlang-6.4.0.27.1) | **abort** — `shared function must have a body` | clean (latent) |
| 6.4.x-snapshot-2026-07-23 (+assertions) | **abort** — `shared function must have a body` | n/a (verification on) |
| main-snapshot-2026-07-11, 6.5-dev (+assertions) | **abort** — `shared function must have a body` | n/a (verification on) |

**Not fixed on any tested toolchain, including 6.5-dev `main`.** Not a
regression: 6.3.3 aborts too once verification is enabled. The reason the
Institute first saw it on a 6.4.x nightly leg and not on the 6.3 release leg
is purely that the nightly image is built `+assertions`.

## Differentiation

Same **verifier class** as two existing entries — a bodyless
`shared [serialized]` coroutine crossing a module boundary — but a
different **trigger**:

| Entry | Bodyless function is… | Pulled across the boundary by… |
|---|---|---|
| [`…-sillinker-borrowed-protocol-default-shared-coroutine-abort`](../swift-issue-sillinker-borrowed-protocol-default-shared-coroutine-abort/README.md) (swiftlang/swift#90406) | a protocol extension **default** for a `@_borrowed` requirement | the consumer's own conformance to that protocol |
| [`…-noncopyable-assoctype-never-bodyless-witness`](../swift-issue-noncopyable-assoctype-never-bodyless-witness/README.md) | a protocol extension **default** for `Body == Never` | the consumer's own `Body == Never` conformance |
| **this entry** | the **concrete type's own** accessor — there is no extension default anywhere | a **second** protocol conformance for the same type, declared in the consumer |

Whether the three share one fix is a maintainer determination.

## Harness

Repository two-target convention with the sibling entries' out-of-process
two-invocation shape: `…-Tests` wraps the probe in `withKnownIssue` with
`when: { true }` (green while the bug fires; **red the moment the consumer
module compiles cleanly** — the fix-detection signal); `…-Repro` is the same
probe standalone (exit 1 = fires, 0 = fixed, 2 = inconclusive). The defining
module's clean build is the probe's positive control.

## Upstream

**Destination**: `swiftlang/swift`. Closely related family: #90406 and the
`Body == Never` sibling above. **Filing remains principal-gated** and no
filing has been made from this record.

## Workaround

Structural. Either keep the second conformance in the module that owns the
property, or give the second protocol a Copyable associated type where the
domain allows it. Attribute suppressions do not help — the failure is
verification of emitted SIL, not optimization.

## Provenance (Institute discovery context)

Surfaced by `swift-primitives/swift-coder-primitives`, gating leg
`Ubuntu (Swift 6.4.x nightly, release)`, tracked on
[swift-primitives/swift-coder-primitives#2](https://github.com/swift-primitives/swift-coder-primitives/issues/2).
The failing frontend invocation compiles the `Coder Parser Primitives`
target and aborts (signal 6, `SILModule::verify` inside
`ASTLoweringRequest`) on:

```
// Parser.OneOf.Sequence.body.read
sil shared [serialized] @$s16Parser_Primitive0A0O0A17_OneOf_PrimitivesE0cD0O8SequenceV4bodyq0_vr
  : $@yield_once @convention(method) <τ_0_0, τ_0_1, τ_0_2 …> … -> @yields @in_guaranteed τ_0_2
```

which is exactly this shape:

- `Parser.OneOf.Sequence` (module `Parser_OneOf_Primitives`) has
  `public let body: Body` and conforms there to `Parser.Protocol`, whose
  requirement is `@Parser.Builder<Input> var body: Body { borrowing get }`
  with `associatedtype Body: ~Copyable`;
- `Coder Parser Primitives` adds
  `extension Parser.OneOf.Sequence: @retroactive Serializer.Protocol` —
  a second protocol whose requirement is
  `@Serializer.Builder<Buffer> var body: Body { borrowing get }`, also with
  `associatedtype Body: ~Copyable`;
- so the consumer's witness reaches for `Sequence.body.read`, which has
  `shared` linkage in the defining module.

Result builders, `~Escapable` inputs, typed throws, `-O`,
`-enable-default-cmo` and `-enable-testing` all appear in the production
invocation and none of them are part of the trigger.
