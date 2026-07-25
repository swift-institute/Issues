# Swift Issue: EarlyPerfInliner asserts on an *escaping* `mark_dependence` over a `begin_apply` token

**Upstream:** **NOT FILED.** Standing institute policy: upstream filing at swiftlang —
issues *or* pull requests — is not a resolution step. This directory is the **terminal
record**. Do not propose, queue, or re-raise filing.

**Classification:** ICE / compiler crash (signal 6, assertion failure) in the SIL optimizer.

A **generic** function that reads a lifetime-dependent `_read` coroutine accessor and then
**constructs and returns** a value from the yield crashes the optimizer at `-O`. The
`EarlyPerfInliner` inlines the accessor's `begin_apply`; `SILInliner`'s
`BeginApplySite::preprocess` walks the `mark_dependence` users of the coroutine's **token
result** and asserts each is *non-escaping*. In this shape the dependence is **escaping**
(the constructed value outlives the borrow scope), so the assertion fires.

## Exact crash signature

```
swift-frontend: /home/build-user/swift/lib/SILOptimizer/Utils/SILInliner.cpp:167:
  void (anonymous namespace)::BeginApplySite::preprocess(SILBasicBlock *, SmallVectorImpl<SILInstruction *> &):
  Assertion `mdi.isNonEscaping()' failed.
…
3.  While evaluating request ExecuteSILPipelineRequest(Run pipelines { … } on SIL for <Module>)
4.  While running pass #N SILFunctionTransform "EarlyPerfInliner" on SILFunction "@…alignUp…"
5.  While inlining SIL function "@…underlying…vrTW…"          ← the `.read` witness thunk
6.  While ...into SIL function "@…alignUp…"
…
 #9 swift::SILInlineCloner::cloneInline(llvm::ArrayRef<swift::SILValue>)
#10 swift::SILInliner::inlineFunction(…)
#11 swift::SILInliner::inlineFullApply(…)
#12 (anonymous namespace)::SILPerformanceInliner::inlineCallsIntoFunction(swift::SILFunction*)
#13 (anonymous namespace)::SILPerformanceInlinerPass::run()
```

## Minimal reproducer

`reproducer.swift` (16 lines), built with bare `swiftc -O` — no SwiftPM, no modules:

```swift
public protocol P<U>: ~Copyable, ~Escapable {
    associatedtype U: ~Copyable & ~Escapable
    var u: U { @_lifetime(borrow self) borrowing get }
    @_lifetime(copy u) init(_ u: consuming U)
}
public struct T<U: ~Copyable & ~Escapable>: ~Copyable, ~Escapable {
    public var u: U
    @_lifetime(copy u) public init(_ u: consuming U) { self.u = u }
}
extension T: Copyable where U: Copyable & ~Escapable {}
extension T: Escapable where U: Escapable & ~Copyable {}
extension T: P where U: ~Copyable & ~Escapable {}
public struct A {
    @inlinable public func f<C: P>(_ v: C) -> C where C.U: FixedWidthInteger { C(v.u &+ 1) }
}
@inlinable public func go(_ x: T<Int64>, _ a: A) -> T<Int64> { a.f(x) }
```

```
swiftc -O -swift-version 6 \
  -enable-experimental-feature Lifetimes \
  -enable-experimental-feature SuppressedAssociatedTypes \
  reproducer.swift -c -o /tmp/x.o          # signal 6
```

**Expected:** compiles cleanly (exit 0).

## Trigger characterization — verified ingredient list

Each ingredient was independently controlled. Note the first two are **mandatory by
construction** — the compiler *rejects* the alternatives, so they cannot be varied as
free ingredients (a stronger statement than "removing it makes it pass"):

| Ingredient | Required? | Control that proves it |
|---|---|---|
| `associatedtype U: ~Copyable & ~Escapable` + `var u: U { @_lifetime(borrow self) borrowing get }` | **Yes — mandatory by construction** | dropping the annotation ⇒ `error: cannot infer the lifetime dependence scope on a method with a ~Escapable parameter, specify '@_lifetime(borrow self)' or '@_lifetime(copy self)'`; dropping the suppression ⇒ `error: invalid lifetime dependence on an Escapable result` |
| **Generic** consumer `f<C: P>(_ v: C) -> C where C.U: FixedWidthInteger` | **Yes** | non-generic `f(_ v: T<Int64>) -> T<Int64>` → **CLEAN** |
| Consumer **constructs and returns `C`** from the yield (⇒ *escaping* dependence) | **Yes** | returning a plain `Int64` (`f<C>(…) -> Int64`) instead → **CLEAN** |
| `-O` | **Yes** | `EarlyPerfInliner` only runs at `-O` |
| A **nested** carrier read (`g.u.f(x)`, i.e. calling into the yield of a *second* coroutine) | **NO** | `a.f(x)` with `A` passed directly also crashes. *This corrected the initial hypothesis, which had assumed the nesting was the trigger.* |
| Cross-module / `-enable-default-cmo` / `-enable-testing` / multiple modules / `package(set)` on the stored property | **No** | single file, two feature flags, nothing else |

## Toolchain matrix (each cell verified by *running* the reducer; `swift --version`-confirmed)

| Swift version | Toolchain | Result |
|---|---|---|
| 6.3.3 | `swift-6.3.3-RELEASE`, Linux x86_64 — **the production pin** | **CLEAN** |
| 6.4-dev | `6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-17-a`, macOS | **CLEAN** |
| main (pre-6.5) | `DEVELOPMENT-SNAPSHOT-2026-05-27-a`, macOS | **CLEAN** |
| 6.5-dev | `nightly-main-jammy` — `Swift 6.5-dev (LLVM 6f2057ffeafd4c6, Swift 83c32e02f71e4bb)` | **CRASH** |

⇒ A **6.5-dev-only regression**, introduced on `main` after 2026-05-27. Independently
corroborated by the production CI run below, whose `Ubuntu (Swift 6.3, release)` leg is
**green** while only the `Swift main nightly` leg aborts.

Reproduces on **aarch64** as well as the CI's x86_64 ⇒ **architecture-independent**.

## Root cause

`LifetimeDependenceInsertion` inserts a `mark_dependence` on the **token result** of a
`begin_apply` when the coroutine yields a lifetime-dependent value. Commit
**`8396a6d8c05`** (2025-06-05, *"Fix an inliner crash when inlining begin_apply with scoped
lifetime dependence"*, rdar://151568816) made the inliner delete those token
`mark_dependence`s when inlining — guarded by `assert(mdi.isNonEscaping())`, i.e. on the
assumption that a coroutine token only ever carries a **scoped** (non-escaping) dependence.

This shape violates that assumption: the generic consumer copies the yielded value out and
**constructs a returned value from it**, so the dependence is *escaping*, not scoped. No
later commit touching `SILInliner.cpp` addresses it (checked through `main` @ 2026-07-03).

### Latent severity note — the assert is only a *guard*

`assert()` is NDEBUG-gated, so it fires only on assert-enabled toolchains (dev snapshots,
`nightly-*` images). On an assert-**disabled** toolchain the same code path deletes the
token `mark_dependence` **regardless of its escaping-ness**, which for a genuinely
`~Escapable` `Underlying` would drop a real lifetime constraint — a miscompile risk rather
than a crash. There is **no shipped-config exposure today**: 6.3.x does not produce this SIL
shape at all (the reducer is clean there), and in the observed production instance the
carried type is `Int64` (trivial, no lifetime to lose). Worth re-checking if this ever
reaches a release toolchain.

## Production manifestation

`swift-iso-9945`, target `ISO 9945 Kernel Lock`, `-c release`:

```
While running pass #16957 SILFunctionTransform "EarlyPerfInliner" on SILFunction
  "@$s16Memory_Primitive0A0O0A21_Alignment_PrimitivesE0C0V7alignUpyxx16Carrier_Protocol01_gH0Rzs17FixedWidthInteger10UnderlyingRpzlF07Tagged_D00M0Vy010Dimension_D010CoordinateO1XOy_13ISO_9945_Core0P5_9945O6KernelO4FileO5SpaceOGs5Int64VG_Tgq5"
While inlining "…Tagged…_CarrierProtocol…underlying…read…"
```

demangling to a generic specialization of

```
(extension in Memory_Alignment_Primitives):
  Memory.Alignment.alignUp<A where A: Carrier._CarrierProtocol, A.Underlying: FixedWidthInteger>(A) -> A
    at  Tagged<Coordinate.X<ISO_9945.Kernel.File.Space>, Int64>
```

inlining the `_CarrierProtocol.underlying.read` protocol-witness thunk for `Tagged`.

The participating declarations:

- `swift-carrier-primitives/Sources/Carrier Protocol/_CarrierProtocol.swift` —
  `var underlying: Underlying { @_lifetime(borrow self) borrowing get }` and
  `@_lifetime(copy underlying) init(_ underlying: consuming Underlying)`.
- `swift-tagged-primitives/Sources/Tagged Primitives/Tagged+Carrier.Protocol.swift` —
  unconditional `Tagged: Carrier.\`Protocol\``; the requirement is satisfied by `Tagged`'s
  **stored** `underlying`, so the witness is a thunk adapting storage to the coroutine.
- `swift-memory-primitives/Sources/Memory Alignment Primitives/Memory.Alignment.swift` —
  the crashing generic: `alignUp<C: Carrier.\`Protocol\`>(_ value: C) -> C where
  C.Underlying: FixedWidthInteger { C(alignUp(value.underlying)) }`.
- Call site: `swift-iso-9945/Sources/ISO 9945 Kernel Lock/Kernel.Lock.Range.swift:74` —
  `granularity.underlying.alignUp(endOffset)`, where
  `Memory.Allocation.Granularity = Tagged<Memory.Allocation, Memory.Alignment>` and
  `ISO_9945.Kernel.File.Offset = Coordinate.X<Space>.Value<Int64> = Tagged<Coordinate.X<Space>, Int64>`.

**Reached CI** as a red `Ubuntu (Swift main nightly, release)` leg on the consumer
`swift-foundations/swift-event-loop-group-dependencies`
([run 30142392114](https://github.com/swift-foundations/swift-event-loop-group-dependencies/actions/runs/30142392114),
job 89638084182). A **standalone `swift-iso-9945` release build reproduces it** — the arc
consumer is not required to surface it.

> Attribution note: the same CI run contains **three unrelated failures**. Do not conflate
> them. (1) this inliner assert on the nightly leg; (2) a `Windows (Swift 6.3, debug)`
> failure, which is the separately-tracked `body: Never { borrowing get }` `_read`-lowering
> ICE on Windows +Asserts; (3) on the sibling `swift-server-foundation` run, a
> `FunctionSignatureOpts` `!type.hasTypeParameter()` abort — that one is
> **#89617**, a *different* bug in a *different* pass (see
> `../swift-issue-functionsignatureopts-generic-typed-throws-error`).

## Distinct from neighbouring records

- **`../swift-issue-copypropagation-nonescapable-mark-dependence`** (catalog §A3,
  `swiftlang/swift#88022`) — also `~Escapable` + `@_lifetime(borrow …)` + `mark_dependence`
  through a `_read` yield, but the crash is in **CopyPropagation** ("Found over consume?!"),
  and it is **FIXED in 6.3**. This one is in **SILInliner/EarlyPerfInliner**, has a distinct
  assertion, and appears only on **6.5-dev** — where §A3 is long fixed. Same family,
  different pass, opposite fix-status.
- **Catalog §A7** — *same pass* (`EarlyPerfInliner`) on a `~Copyable` value-type `_read`
  yield, but a **different assertion** ("Cannot initialize a nonCopyable type with a
  guaranteed value") and present on 6.3.1. This entry's assertion concerns the *escaping-ness
  of a token `mark_dependence`* and is 6.5-dev-only.
- **#89617** (`../swift-issue-functionsignatureopts-generic-typed-throws-error`) — surfaced
  in the *same* fleet sweep and initially reported under one banner, but it is
  `FunctionSignatureOpts` + generic typed-throws error, present 6.2 → 6.5-dev.

## Duplicate search ([ISSUE-007])

No upstream match. `gh search issues --repo swiftlang/swift` on `isNonEscaping`,
`SILInliner.cpp`, `mark_dependence inliner`, and `begin_apply lifetime dependence crash`
returned nothing corresponding to this assertion. Nearest by text — `#48907`, `#48919`
(both inliner, unrelated asserts), `#89186` (CSE), `#81595` (escapability in autoclosure) —
all distinct.

## Workarounds

**Disposition: none adopted. No source change was made in any institute package.**

Rationale: the defect is **6.5-dev-only** while the production pin (6.3.3) is clean and the
stable CI legs are green; and the only lever that works changes *lifetime-dependence
semantics* on a core protocol with a large conformer surface. Spending that change to
satisfy an unreleased nightly is the wrong trade — it is a design decision, not a
workaround. Revisit only if this reaches a release toolchain.

Tested on the reducer (none is `@_optimize(none)`, which is forbidden by [ISSUE-008]):

| Attempt | Result |
|---|---|
| Hoist the yield into a local before constructing `C` (`let s = v.u; return C(s &+ 1)`) | **CRASH** |
| Constrain the consumer to `C: P & Copyable & Escapable` | **CRASH** |
| Hoist *and* constrain | **CRASH** |
| `borrowing` parameter (`f<C: P>(_ v: borrowing C)`) | **CRASH** |
| **`@_lifetime(copy self)` instead of `@_lifetime(borrow self)` on the `underlying` requirement** | **CLEAN** — the only working lever found |
| Requirement as a method rather than a `borrowing get` property; dropping `~Escapable` from the associated type | rejected by the compiler as written; **not fully explored** |

⚠️ **Coverage scope ([ISSUE-026]).** Every row above is **reducer-only**. **None has been
validated against the real package graph** — including the `@_lifetime(copy self)` lever.
Semantically `copy self` is *not* a free substitution: `borrow self` declares a **scoped**
dependence, `copy self` an **inherited** one, which changes the contract for every
`~Escapable` `Underlying`. It would need its own review before adoption.

## ⚠️ Method warning — a stale build silently invalidated the first workaround test

The first attempt to test the hoist workaround was run against the real package graph and
reported **CRASH**, i.e. "the workaround does not help". That result was **invalid**: the
build had reused a cached module. Evidence: the whole build emitted **one** `Compiling`
line, so the patched `@inlinable` body was never recompiled — the optimizer re-inlined the
*old* serialized body. The tell was the **pass number being byte-identical** (`#16957`)
across the patched and unpatched runs; identical SIL cannot come from changed source.

Two rules this reinforces:

- **[ISSUE-003]** — every reduction/workaround step needs a genuinely clean build. Editing
  a source file that is already serialized into a built `.swiftmodule` as `@inlinable` does
  not by itself invalidate consumers.
- **Same family as the cached-green trap:** *a cached build is not compilation evidence —
  confirm `Compiling <Module>`.* Here the absent `Compiling` line was the proof of
  invalidity, and a `grep` for the assertion alone would have "confirmed" a wrong conclusion.

The reducer results in the table above were obtained by direct single-file `swiftc`
invocations, which have no cached-module failure mode.

## Reproducing

The assertion is a plain NDEBUG-gated `assert()`, so it is **invisible on release
toolchains** (including Xcode's). An assert-enabled toolchain is required — the sanctioned
instrument is a container, which needs no local toolchain override:

```bash
docker run --rm -v "$PWD:/w" swiftlang/swift:nightly-main-jammy \
  swiftc -O -swift-version 6 \
    -enable-experimental-feature Lifetimes \
    -enable-experimental-feature SuppressedAssociatedTypes \
    /w/reproducer.swift -c -o /tmp/x.o
```

The image self-reports `Build config: +assertions`. Confirm the toolchain is 6.5-dev-class
before reading a clean compile as a fix — on 6.3/6.4 a clean compile is the *expected*
result, not evidence of repair.

## CI validation (this entry is wired into the Issues repo CI)

Because the bug aborts the compiler, the trigger ships as the resource
`Sources/Reproducer/Crash.swift.txt` and is compiled **out of process** ([ISSUE-029]):

- `Tests/Reproducer.swift` — Swift Testing harness wrapping the probe in `withKnownIssue`.
- `Sources/Reproducer/main.swift` — standalone exit-code probe (`exit(1)` fired /
  `exit(0)` absent-or-inconclusive).

⚠️ **This entry's `when:` is version-gated, unlike most entries here.** Because the bug is
6.5-dev-only, the usual `when: { true }` would make every green 6.3 leg report "known issue
was not recorded" and go **RED** — a false alarm rather than a fix signal. `when:` therefore
gates on `swift --version` ≥ 6.5:

| Toolchain | Bug | `when` | Outcome |
|---|---|---|---|
| 6.3/6.4-class | absent | false | GREEN — correct, clean is expected |
| 6.5-dev-class | fires | true | GREEN — known issue matched |
| 6.5-dev-class | absent | true | **RED — upstream fix landed** |
| 6.3/6.4-class | **fires** | false | **RED — backport or new regression** |

An undeterminable version yields `false`, so an unknown toolchain can never manufacture a
false fix-flip. The signature match is kept narrow (`isNonEscaping` /
`BeginApplySite::preprocess`) so a future rephrasing surfaces as *inconclusive* rather than
as a false flip in either direction — the three-way disposition [ISSUE-029] requires.

> ### 🛑 Do **not** "fix" this back to `when: { true }`
>
> Every *other* entry in this repo uses `when: { true }`, so this one looks like an
> oversight. It is not — it is deliberate, and reverting it breaks the harness:
>
> - The other entries reproduce on **every** supported toolchain, which is what makes
>   `{ true }` correct **for them**. This bug is **6.5-dev-only**. Copying `{ true }` here
>   because that is "the pattern" is cargo-culting it onto a case whose premise does not
>   hold.
> - Concretely, `{ true }` would make **every green 6.3 leg** — the legs actually gated on —
>   report *"known issue was not recorded"* and go **RED, permanently**. That is a standing
>   false alarm, not a fix signal, and it would train readers to ignore this entry's colour.
> - Both RED rows in the table above are **real signals, not noise**: 6.5-dev-absent means
>   upstream fixed it; 6.3-fires means a backport or a fresh regression. Encoding
>   "this must not happen *here*" as a failure is precisely a regression harness's job.
>
> Two safety properties make the gate trustworthy and must survive any edit:
> **(1)** an undeterminable version resolves to `false`, so an unknown toolchain can never
> manufacture a false fix-flip; **(2)** the signature match stays narrow, so a reworded
> diagnostic becomes *inconclusive* rather than a silent pass.
>
> If this bug ever becomes reproducible on the stable pin, the correct edit is to widen the
> version predicate — **not** to replace it with `{ true }`.
>
> *(Reviewed and approved as a deliberate deviation, 2026-07-25.)*

## Catalog status

**Not yet in `swift-compiler-bug-catalog.md`.** That file lives in the PUBLIC `Research/`
tree, so extending it is a separate, deliberate decision and was intentionally left
undone here. This directory is the authoritative record until then. When a catalog entry is
added, cross-reference §A3 and §A7 as the neighbouring-but-distinct records.

## Provenance

2026-07-25 ECO-SIL fleet lane (`/issue-investigation`). Surfaced while fact-crossing a
`!type.hasTypeParameter()` report from an arc lane; the two proved to be different bugs in
different passes. Reduction, ingredient controls, and the toolchain matrix were all run in
`swiftlang/swift:nightly-main-jammy` (assert-enabled) and `swift:6.3` containers.
