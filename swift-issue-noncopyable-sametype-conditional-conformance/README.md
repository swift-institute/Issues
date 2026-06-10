# Runtime cannot verify a conditional conformance whose same-type requirement RHS is a noncopyable type

> **STATUS: STAGED — NOT FILED.** Upstream filing requires a fresh principal YES.
> Drafted 2026-06-10 from the `/issue-investigation` of the slotmap DEBUG wall
> (catalog §A15). The issue body below is written to be copy-pasteable.

---

**Classification**: Miscompile / runtime defect (two symptoms: null-metadata SIGSEGV at `-Onone`; silent wrong `is` results at any optimization level)

**Environment**: macOS 26.2 (Darwin 25.2.0) arm64. Reproduces with Apple Swift 6.3.2 (`swift-6.3.2-RELEASE`), 6.3.1, 6.2.3, 6.2, and the 2026-05-27 main-branch development snapshot (reports `6.5-dev`), against both the macOS 26.2 OS `libswiftCore` and the snapshot toolchain's own `libswiftCore` (which exports `swift_runtimeSupportsNoncopyableTypes`). Not a regression: broken on every compiler × runtime combination tested.

## Reproducer

Single file, no flags, no dependencies (`Sources/reproducer.swift`):

```swift
protocol P {}
struct Pool: ~Copyable {}
struct Gen<A: ~Copyable> {}
extension Gen: P where A == Pool {}          // same-type conditional conformance, ~Copyable RHS
struct W<S: P> { var s: S; var c: Int { 42 } }
let w = W<Gen<Pool>>(s: .init())             // construction succeeds
print(w.c)                                   // SIGSEGV
```

**Command**: `swiftc reproducer.swift -o repro && ./repro`

**Observed**: `constructed` prints, then `EXC_BAD_ACCESS (code=1, address=0x10)` inside the `W.c` getter — `ldr x8, [x0, #0x10]` with `x0 == 0` (null type metadata). With `SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1`:

```
failed type lookup for <symbolic>: subject type x does not conform to protocol P
```

**Expected**: prints `42`. `Gen<Pool>: P` holds — the program type-checks precisely because the conditional conformance applies.

**Second symptom (no crash, wrong answer)** — `Sources/dynamic-cast-probe.swift`:

```swift
let a: Any = Gen<Pool>()
a is any P            // → false   (WRONG; should be true)
// controls:
Gen2<PoolC>() as Any is any P   // same-type to a Copyable RHS  → true (correct)
Gen3<Pool>()  as Any is any P   // inverse-only condition       → true (correct)
```

## Investigation

**Ingredient list** (removing any one makes it pass; each verified independently):

1. The conditional conformance's condition is a **same-type requirement** (`A == Pool`). An inverse-only condition (`where A: ~Copyable`) passes.
2. The same-type RHS is **noncopyable**. A Copyable RHS passes.
3. A generic context **bounded on the protocol** (`W<S: P>`). An unbounded `W<S>` passes.
4. For the crash symptom: the wrapper **stores a field** of the bound parameter and a member is accessed at `-Onone` (a class wrapper crashes at instantiation; `-O` passes for this shape because static specialization avoids runtime instantiation — but `_mangledTypeName(W<Gen<Pool>>.self)` crashes even at `-O`).

Not required: protocol requirements (P can be empty), associated types, any experimental feature, `~Copyable` on the conforming type or wrapper (only the phantom parameter bound and the RHS need it), module boundaries, SwiftPM.

**lldb trace of the crash path** (6.3.2, OS runtime):

```
__swift_instantiateConcreteTypeFromMangledName ($s…1WVyAA3GenVyAA4PoolVGGMD)
└─ swift_getTypeByMangledNameInContextImpl
   └─ _gatherGenericParameters → _checkGenericRequirements   (W's S: P)
      └─ swift_conformsToProtocol(Gen<Pool>, P)
         └─ TargetProtocolConformanceDescriptor::getWitnessTable
            └─ _checkGenericRequirements (conditional reqs of Gen: P)
               ├─ subject "x" resolves (substitutions from Gen<Pool>) ✓
               └─ same-type RHS resolves — Pool's metadata accessor FIRES ✓
                  … yet the check fails; error swallowed (getWitnessTable → nullptr)
→ lookup returns null; the caller's stub has no null check; first deref faults at +0x10
```

Both sides of `A == Pool` demonstrably resolve (breakpoints on `$s…4PoolVMa` fire from inside the conditional check), so the failure is at/after the resolution-and-compare step in `checkGenericRequirement`'s `GenericRequirementKind::SameType` case (`stdlib/public/runtime/ProtocolConformance.cpp:1843` at `6f5d855aedf`). The inner `TypeLookupError` is discarded by `getWitnessTable`, so the outer check misreports the conformance as absent.

**Probably-related runtime property** (`Sources/typebyname-probe.swift`): noncopyable nominals are invisible to textual by-name lookup on every runtime tested — `_typeByName` of a plain `struct Pool: ~Copyable {}` returns nil (its descriptor record is segregated into `__swift5_types2` by `IRGenModule::addRuntimeResolvableType`, `lib/IRGen/GenDecl.cpp:977`, and no runtime scans that section — `ImageInspectionCommon.h:35` appears to be its only mention in the tree). Symbolic references make plain `Gen<Pool>` metadata instantiation work; it is specifically the conditional-conformance same-type check that fails.

**Suggested defect framing** (either or both):
- Runtime: `checkGenericRequirement`'s SameType case fails for a noncopyable RHS even when both sides resolve; the error is silently swallowed by `getWitnessTable`, converting a checkable conformance into "does not conform" and a null metadata result.
- IRGen: `__swift_instantiateConcreteTypeFromMangledName` results are dereferenced without a null check, so any runtime-side refusal becomes a wild SIGSEGV instead of a diagnostic. (Compare the guarded treatment of `MangledTypeRefRole::FieldMetadata` in `lib/IRGen/GenReflection.cpp` vs the unguarded `Metadata` role.)

## Workaround

Respell the conditional conformance via a marker protocol (`Sources/workaround-marker-protocol.swift`, verified):

```swift
protocol Marker: ~Copyable {}
extension Pool: Marker {}
extension Gen: P where A: Marker, A: ~Copyable {}   // explicit ~Copyable is load-bearing (SE-0427 re-default)
```

Protocol-conditional requirements with noncopyable subjects verify correctly at runtime.

## Related (distinct mechanisms, same observable family)

- swiftlang/swift#89389 / PR #87066 (`bc44d42f11`): missing `Rj`/`RJ` demangler cases — runtime message is `unknown error`, fixed by the 6.4-dev compiler. This issue's message is `subject type … does not conform to protocol …` and reproduces with the 6.5-dev compiler and runtime; no `SuppressedAssociatedTypes` involvement.
- swiftlang/swift#74303, #69615: other members of the `__swift_instantiateConcreteTypeFromMangledName`-null family.

---

## House records (not part of the upstream body)

- Catalog: `swift-institute/Research/swift-compiler-bug-catalog.md` §A15.
- Probes + full bisect record: `~/Developer/.handoffs/probes-2026-06-10/noncopyable-sametype-conformance-crash/FINDINGS.md`.
- Production trigger: `Storage.Generational: Store.Protocol where Allocation == Memory.Allocator<Memory.Heap>.Pool` — the slotmap (LEG 7) DEBUG wall; runtime message there is `subject type x does not conform to protocol __StoreProtocol`.
- Evidence captures: `evidence/`.
