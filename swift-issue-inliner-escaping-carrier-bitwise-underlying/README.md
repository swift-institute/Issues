# Swift Issue: EarlyPerfInliner asserts inlining Carrier.Protocol's `underlying` coroutine through the generic bitwise `&` operator

**Upstream:** **NOT FILED.** Standing institute policy: upstream filing at swiftlang —
issues *or* pull requests — is not a resolution step. This directory is the **terminal
record**. Do not propose, queue, or re-raise filing.

**Classification:** ICE / compiler crash (signal 6, assertion failure) in the SIL optimizer.
**Same root cause as
[`../swift-issue-inliner-escaping-mark-dependence-coroutine-token`](../swift-issue-inliner-escaping-mark-dependence-coroutine-token/README.md)** —
this entry records a second, independently observed trigger of that bug, not a new one.

## Tracking

Filed for swift-institute/Issues#99. Isolation lane of coordinator session e25a1d74.

## Exact crash signature (from production CI, not simulated)

```
swift-frontend: /home/build-user/swift/lib/SILOptimizer/Utils/SILInliner.cpp:167:
  void (anonymous namespace)::BeginApplySite::preprocess(SILBasicBlock *, SmallVectorImpl<SILInstruction *> &):
  Assertion `mdi.isNonEscaping()' failed.
…
3. While evaluating request ExecuteSILPipelineRequest(...) on SIL for Binary_Parse_Primitives)
4. While running pass #5250 SILFunctionTransform "EarlyPerfInliner" on SILFunction
   "@$s47Carrier_Primitives_Standard_Library_Integration1aoiyxx_xt0A9_Protocol01_aF0Rzs17FixedWidthInteger10UnderlyingRpzlF14Byte_Primitive0K0V_Tgq5".
   for '&(_:_:)' (in module 'Carrier_Primitives_Standard_Library_Integration')
5. While inlining SIL function
   "@$s14Byte_Primitive0A0V16Carrier_Protocol01_cD00a1_D11_PrimitivesAdEP10underlying10UnderlyingQzvrTW".
   for <<debugloc at "<compiler-generated>":0:0>>
6. While ...into SIL function "@...&(_:_:)...Byte_Primitive0K0V_Tgq5".
```

Toolchain: `Swift version 6.5-dev (LLVM 6f2057ffeafd4c6, Swift 83c32e02f71e4bb)`, Ubuntu
22.04.5 LTS, x86_64. Observed on two independent heads:

- swift-standards/swift-github-standard PR #15, head `9a4dd36`, run
  [30742912862](https://github.com/swift-standards/swift-github-standard/actions/runs/30742912862),
  job `ci / matrix / Ubuntu (Swift main nightly, release)` (ID 91775061827).
- swift-standards/swift-github-standard PR #17, head `62162e7`, run
  [30744204332](https://github.com/swift-standards/swift-github-standard/actions/runs/30744204332),
  same job/matrix leg.

Both crash while compiling `swift-binary-parser-primitives` — a dependency, not the
consuming repository's own source — specifically `Binary Parse Primitives` target files
(`Binary.Parse.Access+prefix.swift` et al.).

## Root cause — identical mechanism to the neighbouring entry

Demangling the crashing frames:

- Pass 4: `EarlyPerfInliner` inlining into the generic bitwise-AND operator
  `& <C: Carrier.\`Protocol\`>(lhs: C, rhs: C) -> C where C.Underlying: FixedWidthInteger`
  specialized at `Byte` — declared in
  `swift-carrier-primitives/Sources/Carrier Primitives Standard Library
  Integration/Carrier+Bitwise.swift`:

  ```swift
  @_disfavoredOverload
  @inlinable
  public func & <C: Carrier.`Protocol`>(lhs: C, rhs: C) -> C
  where C.Underlying: FixedWidthInteger {
      C(lhs.underlying & rhs.underlying)
  }
  ```

- Pass 5: the function being inlined is `Byte`'s protocol-witness thunk for
  `Carrier.\`Protocol\`.underlying` — declared in
  `swift-byte-primitives/Sources/Byte Protocol Primitives/Byte+Carrier.swift`
  (`extension Byte: Carrier.\`Protocol\` { public typealias Underlying = UInt8 ... }`),
  witnessing the coroutine-shaped requirement in
  `swift-carrier-primitives/Sources/Carrier Protocol/_CarrierProtocol.swift`:

  ```swift
  var underlying: Underlying {
      @_lifetime(borrow self)
      borrowing get
  }
  ```

This is **exactly** the ingredient set documented in
`../swift-issue-inliner-escaping-mark-dependence-coroutine-token/README.md`: a
`@_lifetime(borrow self) borrowing get` coroutine requirement on a `~Copyable & ~Escapable`
associated type, witnessed by a concrete stored-property thunk, inlined by
`EarlyPerfInliner` into a **generic** caller that **constructs and returns** a new carrier
value built from the yielded value (`C(lhs.underlying & rhs.underlying)` — construction,
not pass-through). `SILInliner`'s `BeginApplySite::preprocess` asserts every
`mark_dependence` on the coroutine's token result is non-escaping; this shape's dependence
is escaping (the constructed return value outlives the borrow scope), so the assertion
fires — same as the `alignUp`/`Tagged` trigger already on file, just a different generic
consumer (`&` instead of `alignUp`) and a different concrete conformer (`Byte`, `UInt8`
carrier, instead of `Tagged<_, Int64>`).

`swift-binary-parser-primitives` depends on `swift-byte-primitives` (hence `Byte`'s
`Carrier.\`Protocol\`` conformance) and, transitively through the primitives layer, on
`swift-carrier-primitives`'s bitwise standard-library integration. Both are L1/L2
primitives widely re-exported, so this is not specific to `swift-binary-parser-primitives`
— it is specific to compiling *any* code that calls the generic Carrier bitwise `&`/`|`/`^`
operators (or the mirrored `<<`/`>>`) on a concrete `Carrier.\`Protocol\`` conformer at
`-O` on a 6.5-dev-class toolchain, of which `swift-binary-parser-primitives` happens to be
the first module in the dependency graph to reach that call shape during a release build.

## Minimal reproducer

`reproducer.swift` (also staged as `Sources/Reproducer/Crash.swift.txt` for the
out-of-process harness):

```swift
public protocol Carrying<Underlying>: ~Copyable, ~Escapable {
    associatedtype Underlying: ~Copyable & ~Escapable
    var underlying: Underlying {
        @_lifetime(borrow self)
        borrowing get
    }
    @_lifetime(copy underlying)
    init(_ underlying: consuming Underlying)
}

public struct Byte: Carrying {
    public typealias Underlying = UInt8
    public let underlying: UInt8
    public init(_ underlying: consuming UInt8) { self.underlying = underlying }
}

@_disfavoredOverload
@inlinable
public func & <C: Carrying>(lhs: C, rhs: C) -> C
where C.Underlying: FixedWidthInteger {
    C(lhs.underlying & rhs.underlying)
}

@inlinable
public func maskedByte(_ a: Byte, _ b: Byte) -> Byte { a & b }
```

```bash
swiftc -O -swift-version 6 \
  -enable-experimental-feature Lifetimes \
  -enable-experimental-feature SuppressedAssociatedTypes \
  reproducer.swift -c -o /tmp/x.o
```

**Expected on a bugged toolchain:** `swift-frontend` aborts (signal 6) with
`Assertion \`mdi.isNonEscaping()' failed` at `SILInliner.cpp:167`.
**Expected on an unaffected toolchain:** compiles cleanly (exit 0).

## Verification status — ⚠️ UNVERIFIED-locally

**No 6.5-dev / main-nightly toolchain is available on this machine**
(`/Library/Developer/Toolchains` does not exist; the local `xcrun swift --version`
resolves to `swift-driver version 1.168.5 Apple Swift version 6.4
(swiftlang-6.4.0.27.1 clang-2100.3.27.1)`), and the sanctioned container instrument used
by the neighbouring entry (`docker run --rm -v "$PWD:/w" swiftlang/swift:nightly-main-jammy
swiftc ...`) could not be run either — the local `docker` CLI is installed but its daemon
is not running in this lane's environment.

What **was** verified locally, with `swiftc -O -swift-version 6 -enable-experimental-feature
Lifetimes -enable-experimental-feature SuppressedAssociatedTypes reproducer.swift -c -o
/tmp/x.o` against the local Swift 6.4 toolchain:

- The reproducer **type-checks and compiles cleanly, exit 0** (only a deprecation warning
  for `SuppressedAssociatedTypes`, matching the deprecation noted on the neighbouring
  6.4-dev-CLEAN row). This is the expected result on a stable/6.4-class toolchain per the
  version-gated nature of this bug family — it is **not** evidence the bug is fixed or
  absent, only that this reduction does not depend on anything 6.4 rejects.
- No local instrument exists to force `-Xfrontend -sil-verify-all` reproduction of the
  `EarlyPerfInliner` pass on a non-nightly toolchain, since the pass and the SIL shape it
  operates on are themselves 6.5-dev-only in this family (per the neighbouring entry's
  toolchain matrix).

**Pending verification step (for CI or a Linux/nightly-capable machine):**

```bash
docker run --rm -v "$PWD:/w" swiftlang/swift:nightly-main-jammy \
  swiftc -O -swift-version 6 \
    -enable-experimental-feature Lifetimes \
    -enable-experimental-feature SuppressedAssociatedTypes \
    /w/reproducer.swift -c -o /tmp/x.o
```

Confirm `Build config: +assertions` is reported by the image and that the failure text
contains `mdi.isNonEscaping()` / `BeginApplySite::preprocess` before treating a crash as
confirmation, and confirm `swift --version` resolves to a 6.5-dev-class snapshot before
treating a clean compile as evidence of a fix.

The **CI-observed crash log itself** (quoted above, from runs 30742912862 / 30744204332) is
already primary evidence that the bug fires in production on 6.5-dev; this local step would
only additionally confirm the *reduced* reproducer is faithful.

## Disposition

The nightly (`Swift main nightly`) leg is **structurally red for every consumer of
`swift-binary-parser-primitives`** — and, more broadly, for every consumer of
`swift-carrier-primitives`'s bitwise standard-library integration on a concrete
`Carrier.\`Protocol\`` conformer at `-O` — **until the 6.5-dev toolchain moves past this
regression**. This is not specific to `swift-binary-parser-primitives`'s own source; the
crash is entirely inside a widely-shared L1/L2 dependency edge
(`swift-carrier-primitives` × `swift-byte-primitives`) that many other primitives packages
also exercise, so any of them reaching this call shape under `-enable-default-cmo -O` on
the nightly leg will hit the same assertion. No source change in
`swift-binary-parser-primitives`, `swift-byte-primitives`, or `swift-carrier-primitives` is
warranted: the trigger is the identical, already-catalogued
`../swift-issue-inliner-escaping-mark-dependence-coroutine-token` regression, whose
disposition (no workaround adopted; 6.5-dev-only; production pin 6.3.3 and stable CI legs
are green) applies unchanged here.

## Distinct from neighbouring records

- **`../swift-issue-inliner-escaping-mark-dependence-coroutine-token`** — same root cause,
  same assertion, same pass; different generic caller (`Memory.Alignment.alignUp` vs. the
  Carrier bitwise `&` operator here) and different concrete conformer (`Tagged<_, Int64>`
  vs. `Byte`/`UInt8` here). Read that entry first for the full mechanism, ingredient
  controls, and toolchain matrix — they are not re-derived here to avoid duplicating a
  verified record; this entry only establishes that the same bug reaches a second,
  independently-discovered call site through a different dependency path.
- **Issues#94** — a distinct crash site per the tracking issue (#99) description; not
  re-investigated here.

## Provenance

2026-08-03. Filed for swift-institute/Issues#99 by the isolation lane of coordinator
session e25a1d74, from the 2026-08-03 diagnosis lane records on
swift-standards/swift-github-standard PR #15 (run 30742912862) and PR #17 (run
30744204332).
