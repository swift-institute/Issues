# `Mangler::verify` abort on the `@_implements(Iterable, makeIterator())` witness returning a nested-generic `Materializing<Vector.Iterator>`

> **STAGED terminal record** (not filed upstream — swiftlang filing does not exist as a step per [ISSUE-008] standing policy). `swift-institute/Issues` is the only destination.
>
> **Slug note**: renamed 2026-06-26 from `…vector-sequenceable-windows-asserts-ice` (the handoff's name) to reflect the actual root cause — the **`Iterable` conformance, not `Sequenceable`** (see §Reconciliation).

## Classification

**ICE / Crash** — compiler assertion abort (`abort()`, signal 6) during **AST→SIL lowering** (`ASTLoweringRequest`). Surfaces only on **+Asserts** toolchains; NoAsserts (stock macOS/Linux release) compiles and tests green.

## Environment

| | |
|---|---|
| **Crashes on** | Swift 6.3.2 `+Asserts` (Windows CI gating leg); reproduced locally on `swiftlang/swift:nightly-6.3-jammy` = Swift **6.3.0-dev** (`f30e11b820448ef`) and **6.3.3-dev** (`c83acbf89dd1298`), both `Build config: +assertions` |
| **Green on** | Swift 6.3.2 release **NoAsserts** (Apple macOS), `swift:6.3` Linux release (106 tests pass) |
| **Config** | `-Onone`, `-wmo`, two modules (defining + consumer), bare `swiftc` (no SwiftPM needed) |
| **Real package** | `swift-primitives/swift-vector-primitives` @ `6b85557`, target `Vector Primitives` |

## Observed

```
While evaluating request ASTLoweringRequest(Lowering AST to SIL for module Vector_Primitives)
Abort: function verify at Mangler.cpp:176
Can't demangle: $s16Vector_Primitive0A0V0A11_PrimitivesE20iterableMakeIterator0f1_B00F0O0f7_Chunk_C0E13MaterializingVy_AcARi_zrlEAGVyx_GAmH0F9_ProtocolE0I0AD_HCg_GyF
```

The crashing symbol demangles to:

```
Vector_Primitive.Vector.(extension in Vector_Primitives).iterableMakeIterator()
    -> Iterator_Chunk_Primitives.Iterator.Chunk.Materializing<Vector_Primitive.Vector<A>.Iterator>
```

i.e. the **`@_implements(Iterable, makeIterator())` witness** `iterableMakeIterator()` whose return type is the nested-generic `Materializing<Vector.Iterator>`. The `Ri_z` node is the `~Escapable` requirement; the trailing `…IterP…_HCg_` is an **associated-conformance** node. The compiler's own mangler emits this symbol and then its round-trip self-check (`Mangle::Mangler::verify`, `Mangler.cpp:176`) **cannot re-demangle it** and aborts.

### Stack (both real package and reducer, identical)

```
swift::Mangle::Mangler::verify(StringRef, ManglingFlavor)          ← Mangler.cpp:176, CONDITIONAL_ASSERT-gated
swift::Mangle::ASTMangler::mangleEntity(ValueDecl const*, …)
swift::SILDeclRef::mangle(ManglingKind) const
swift::SILFunctionBuilder::getOrCreateFunction(…)
swift::Lowering::SILGenModule::getFunction(SILDeclRef, …)
swift::Lowering::SILGenModule::emitOrDelayFunction(SILDeclRef)
swift::Lowering::SILGenModule::emitFunction(FuncDecl*)
SILGenExtension::visitFuncDecl(FuncDecl*)
SILGenExtension::emitExtension(ExtensionDecl*)
swift::Lowering::SILGenModule::emitSourceFile(SourceFile*)
swift::ASTLoweringRequest::evaluate(…)
```

## Root cause

The `+Asserts` mangler produces a symbol for the `iterableMakeIterator` witness — whose
signature embeds the **deep generic instantiation** `Materializing<Vector<A>.Iterator>` (a
generic adapter parameterized by the *conforming type's own nested `~Copyable` iterator*),
carrying a `~Escapable` requirement (`Ri_z`) and an associated-conformance node (`HCg`) —
that **fails its own round-trip demangle verification**. `Mangler::verify` is gated on
`CONDITIONAL_ASSERT_enabled()`, so:

- **+Asserts** (Windows 6.3.x, Embedded, `swiftlang/swift:nightly-6.3-jammy`): the verify runs → `abort()`.
- **NoAsserts** (stock macOS/Linux release): the malformed name is emitted **unverified** → silent success → latent. macOS/Linux are green.

This is the **same class as catalog §A12** — a corrupt/un-roundtrippable mangled name for a
*nested-generic iterator-adapter witness*. It is **distinct** from:
- **§A16** (bodyless `shared [serialized]` witness; "Must have a construct to emit for") — different mechanism (missing body, not a bad name).
- **§A17** (`getEffects(req).contains(getEffects(witness))` Sema assertion) — different phase (Sema, not SILGen) and fixed on 6.5-dev.

## Reconciliation — it is the **Iterable** witness, not Sequenceable

The handoff presumed the crash was "in the Sequenceable witness synthesis." It is **not**:

1. **Real-package symbol** (`real-package-crash-6.3.3-dev.log`): the abort is on
   `iterableMakeIterator → Materializing<Vector.Iterator>`, defined in **`Vector+Iterable.swift`**
   (the `Iterable` conformance), not in any Sequenceable witness. The SIL emit-module compiles all
   ops-module files together (WMO), so the diagnostic's *file* attribution lands on whichever file
   it was nominally processing (`Vector+Sequenceable.swift`) — which is why splitting the
   conformance into its own file appeared to "move" the ICE. The *function* is the Iterable witness.
2. **Reducer ingredient matrix** (asserts): every configuration that keeps the Iterable
   `@_implements` witness crashes; **removing the Sequenceable conformance does not fix it**, and
   removing the dual `makeIterator`, `Swift.IteratorProtocol`, or `Swift.Sequence` does not fix it.
3. **Isolation**: **dropping the `Iterable` conformance turns CRASH → PASS** on both +Asserts and
   NoAsserts. The Iterable `@_implements(Iterable, makeIterator())` Materializing witness is the
   sole cause.

## Reproducer

`defining.swift` (module `M`) + `consumer.swift` (module `N`), driven by `build.sh`. Models the
real three-module topology (Iterator.Protocol / Iterable+Materializing / Sequenceable in
iterator+sequence-primitives; `Vector` in "Vector Primitive"; the conformances in "Vector
Primitives"). Verified:

| Toolchain | Result |
|---|---|
| Apple Swift 6.3.2 NoAsserts (host macOS) | **PASS** (`repro-crash` not produced) — matches macOS-green |
| `swiftlang/swift:nightly-6.3-jammy` 6.3.3-dev +Asserts | **CRASH** `Mangler.cpp:176` (`repro-crash-6.3.3-dev.log`) — matches Windows |

```sh
sh build.sh .                                                              # host → PASS
docker run --rm -v "$PWD":/w -w /w swiftlang/swift:nightly-6.3-jammy sh build.sh .   # +Asserts → abort
```

**Ingredient model**: the trigger is the `Iterable` conformance whose `Iterator` associated type
is bound via `@_implements(Iterable, Iterator)` to the **nested-generic** `Materializing<Vec.Iterator>`,
with the `@_implements(Iterable, makeIterator())` witness `iterableMakeIterator` returning that
type. The surrounding conformance set (the dual `makeIterator`, `Sequenceable`, `Swift.Sequence`,
`Swift.IteratorProtocol`) is what keeps the **NoAsserts** path green: the NoAsserts latency is
*marginal* — incidental source changes (even a comment) can flip the synthetic reducer's NoAsserts
result on an asserts-enabled-mangler Apple host. The **+Asserts crash is robust**; the **real
package is robustly NoAsserts-green** (CI).

## Why Vector specifically (and no other Iterable conformer)

The `Materializing<Iterator>` + `@_implements(Iterable, makeIterator())` pattern is used by ~10
ecosystem types. Built on the +Asserts image, the closest conformers **all compile clean** —
Vector is the only crash:

| Package | +Asserts | Distinguisher |
|---|---|---|
| `swift-bit-vector-primitives` (8 types) | PASS | value-generic (`<let wordCount: Int>`, Copyable) |
| `swift-buffer-slab-primitives` | PASS | type param `S` kept `~Copyable`; only `S.Element` constrained Copyable |
| `swift-single-iterator-primitives` | PASS | binds `Materializing<Iterator.Once<Element>>` — a **shared** element-generic iterator, not its own nested one |
| **`swift-vector-primitives`** | **CRASH** | the only one with **both** traits below |
| `swift-tree-keyed-primitives` | (inconclusive) | pre-existing `~Copyable`-suppression baseline errors |

Vector uniquely combines two traits, each individually harmless:
- **Trait A — Iterable.Iterator wraps Vector's *own nested* iterator**: `Materializing<Vector<Bound>.Iterator>` (a deep generic instantiation). **Confirmed load-bearing**: swapping to a shared element-generic iterator in the reducer flips CRASH → PASS. Single dodges this (uses `Iterator.Once<Element>`).
- **Trait B — Vector re-Copyable-izes its `~Copyable` type param**: `Vector<Bound: ~Copyable>` is generic over its element directly, so Iterable's required `where Bound: Copyable` (SE-0427) re-constrains a suppressed param. Buffer-slab has Trait A but keeps `S: ~Copyable` (no B) → passes.

Buffer-slab = A without B → pass; Single = B-ish without A → pass; Vector = A and B → the mangler can't round-trip the witness name. §A12's class.

## Resolution — APPLIED & VALIDATED (the §A12 element-only-generic dodge)

**Flatten Trait A**: bind `Iterable.Iterator` to a **shared element-generic** iterator instead of Vector's own nested one — exactly what Single does. Realized by type-erasing the scalar cursor through `swift-iterator-primitives`' shared `Iterator.Witness<Element, Failure>` before materializing (lazy — `Witness` drives `next()` through a closure; no allocation, no new Vector type, all three conformances retained):

```swift
// Vector+Iterable.swift (Vector and Vector.Reversed)
public import Iterator_Witness_Primitives
@_implements(Iterable, Iterator)
public typealias IterableIterator = Iterator.Materializing<Iterator.Witness<Bound, Never>>   // was: Materializing<Iterator>
@_implements(Iterable, makeIterator())
public borrowing func iterableMakeIterator() -> Iterator.Materializing<Iterator.Witness<Bound, Never>> {
    let scalar: Iterator = makeIterator()
    return Iterator.Materializing(Iterator.Witness(scalar))                                   // was: Materializing(scalar)
}
// + Package.swift: "Vector Primitives" target depends on product "Iterator Witness Primitives"
```

`Materializing<Iterator.Witness<Bound, Never>>` mangles shallow (element-generic), dodging the verifier.

**Validation** (patched copy of the real package):
- +Asserts (`swiftlang/swift:nightly-6.3-jammy` 6.3.3-dev): `Build of target: 'Vector Primitives' complete!` — no `Mangler.cpp:176`.
- macOS release host: `swift test` → **106 tests in 25 suites passed**, zero failures.

Applied to `swift-vector-primitives` 2026-06-26. Per [ISSUE-008]: terminal dossier (this) + applied workaround; no upstream filing.
