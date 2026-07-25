# Investigation Arc: Cross-Module `@_rawLayout` + `~Copyable` Extension Rejection

**Investigation date**: 2026-05-23
**Toolchains tested**:
- Apple Swift 6.3.2 (Xcode 26.4.1, `swiftlang-6.3.2.1.108`) — **STILL BROKEN**
- Swift 6.4-dev nightly (`swift-latest.xctoolchain`) — **STILL BROKEN**

**Status**: Bug confirmed compile-time. Root-cause hypothesis identified empirically (unconditional protocol conformance leaks `Copyable` constraint to primary declaration). Workaround D verified on production source. Upstream filing pending principal authorization.

## 1. Initial discovery

`swift-storage-primitives` at commit `ee86ee0` (Cohort III Pilot 1 [MOD-031] restructure) builds 12 of 13 targets cleanly. `Storage Inline Primitives` fails with four "type 'Element' does not conform to protocol 'Copyable'" errors at `Sources/Storage Inline Primitives/Storage.Inline.swift` lines 97, 139, 142, 143 — all sites where `Storage<Element>.Inline`'s body references `Element` (via `@_rawLayout(likeArrayOf: Element, …)`, `bitIndex.retag(Element.self)`, `Index<Element>.Offset(…)`, `assumingMemoryBound(to: Element.self)`).

The brief's hypothesis was that the bug fires when:
1. Foreign-module `extension X where Element: ~Copyable` directly on the Element-generic root namespace
2. Nested type declares `@_rawLayout(likeArrayOf: Element, count: capacity)` inner storage struct
3. Custom `deinit` body uses `Element.self` / `Index<Element>.…` / `assumingMemoryBound(to: Element.self)`

Variable isolation refuted this trigger model and identified a different, simpler one.

## 2. Step 0 — Classification

**Bug class**: Rejects-valid ([ISSUE-010]). Correct code is rejected at compile time with a Copyable-conformance diagnostic. No SIL or runtime involvement.

**Investigation path**: type-checker level — `swiftc -typecheck` reproduces; SIL analysis is not needed (rejects-valid skips SIL per the SKILL.md table).

## 3. Step 0.5 — SE-Proposal context

**Relevant proposals**:

- **SE-0427 Noncopyable Generics** (in Swift 6.0). Establishes: "An extension of a concrete type must introduce a default `T: Copyable` requirement on every generic parameter of the extended type". This is THE relevant rule — the unconditional conformance extension adds an implicit `Element: Copyable` requirement. The proposal documents the rule applies to extensions but does NOT state that the implicit constraint should leak back to the type's primary declaration. The observed leak appears to be an implementation defect, not an intended consequence of SE-0427.
- **SE-0499 Support Non-Copyable Simple Protocols** (in Swift 6.2). Allows protocols themselves to be `~Copyable` (used by `Marker: ~Copyable` in our reproducer).
- **SE-0503**, **SE-0519** — checked, no relevant text on extension-constraint propagation across siblings.

The proposals do NOT predict the leak behavior. The observed compiler behavior contradicts the documented scope of the SE-0427 rule.

## 4. Step 1 — Dev toolchain check

Parent agent reported `TOOLCHAINS=swift swift build --target "Storage Inline Primitives"` STILL fails with the same errors. Re-verified by issuing `TOOLCHAINS=swift xcrun swiftc --version` (Swift 6.4-dev `LLVM a3655ee8d8c4d74, Swift d13cbbfd336f246`) and building the standalone reproducer — same errors fire on the dev toolchain. **NOT fix-on-dev.**

## 5. Step 2 — Reproducer construction

Initial brief reproducer (single-module Inline struct with `@_rawLayout` + deinit referencing `Element.self`) **did not** reproduce the error. The bare cross-module shape is INSUFFICIENT.

**Trigger discovery via cross-file bisection inside the production target.** Bisected which sibling file of `Storage.Inline.swift` triggers the error when typechecked together. Result:

```
=== Pair: Storage.Inline.swift + Storage.Inline Copyable.swift           → 0 errors
=== Pair: Storage.Inline.swift + Storage.Inline ~Copyable.swift          → 0 errors
=== Pair: Storage.Inline.swift + Storage.Inline+Deinitialize.swift       → 0 errors
=== Pair: Storage.Inline.swift + Storage.Inline+Initialize.swift         → 0 errors
=== Pair: Storage.Inline.swift + Storage.Inline+Memory.Contiguous.Protocol.swift → 6 errors  ← TRIGGER
=== Pair: Storage.Inline.swift + Storage.Inline+Move.swift               → 0 errors
=== Pair: Storage.Inline.swift + Storage.Inline+isEmpty.swift            → 0 errors
=== Pair: Storage.Inline.swift + exports.swift                           → 0 errors
```

The trigger file `Storage.Inline+Memory.Contiguous.Protocol.swift` line 69 declares **`extension Storage.Inline: Memory.Contiguous.`Protocol` { … }`** WITHOUT a `where Element: ~Copyable` clause — the standalone reproducer was missing this ingredient.

## 6. Variable isolation table

Following [ISSUE-013] Variable Isolation. All variants are cross-module unless noted. Each variant changes ONE variable from V0 (the minimum reproducing baseline) and rebuilds clean to test.

| # | Variant | Module split | `@_rawLayout` on inner | Custom `deinit` | Element refs in body | Conformance | `where` on conformance | Result |
|---|---------|:-------------|:----------------------|:----------------|:---------------------|:------------|:----------------------|:-------|
| V0 | baseline | cross | yes | yes | @rL + deinit | unconditional | no | **FAIL** (2 errors) |
| V1 | no conformance file | cross | yes | yes | @rL + deinit | absent | n/a | PASS |
| V2 | **Workaround D** | cross | yes | yes | @rL + deinit | conditional | **`~Copyable`** | **PASS** |
| V3 | no deinit body | cross | yes | no | @rL only | unconditional | no | FAIL |
| V4 | no `@_rawLayout` | cross | no | yes | deinit only | unconditional | no | FAIL |
| V5 | empty deinit | cross | yes | yes (empty body) | @rL only | unconditional | no | FAIL |
| V6 | two-level (extension Storage.Foo) | cross | yes | yes | @rL + deinit | unconditional | no | FAIL |
| V7 | conformance same-file as Inline | cross | yes | yes | @rL + deinit | unconditional | no | FAIL |
| V8 | inner `where Element: ~Copyable` repeated | cross | yes | yes | @rL + deinit | unconditional | no | FAIL |
| V9 | `package` inner struct | cross | yes | yes | @rL + deinit | unconditional | no | FAIL |
| V10 | **same module (single file)** | **same** | yes | yes | @rL + deinit | unconditional | no | **FAIL** |
| V11 | outer extension w/o `where` | cross | yes | yes | @rL + deinit | absent | n/a | PASS |
| V12 | minimal — only deinit `Element.self` ref | cross | no | yes (Element.self) | deinit only | unconditional | no | FAIL |
| V13 | only `@_rawLayout`, no deinit | cross | yes | no | @rL only | unconditional | no | FAIL |
| V14 | no Element refs at all | cross | no | no | none | unconditional | no | PASS |
| V15 | Element.self in regular method (not deinit) | cross | no | no | `func foo` | unconditional | no | FAIL |
| V16 | **same module, two files** | **same** | no | yes | deinit | unconditional | no | **FAIL** |
| V17 | **ABSOLUTE MIN** — same module, single file, no @_rawLayout, no deinit | **same** | no | no (method) | `func foo` | unconditional | no | **FAIL** |
| V18 | protocol implicitly Copyable | same | no | no | method | unconditional | no | FAIL* |
| V19 | bare extension (no protocol conformance) | same | yes | yes | @rL + deinit | absent (just methods) | n/a | **PASS** |
| V20 | protocol `~Copyable` WITHOUT `associatedtype Element` | same | no | no | method | unconditional | no | **PASS** |
| V21 | protocol with `associatedtype Element` (no typealias) | same | no | no | method | unconditional | no | FAIL |

*V18 error fires differently — error names `Storage<Element>.Inline does not conform to protocol Copyable` (because the protocol is implicitly Copyable and Inline is `~Copyable`). The exact same "leak" is at play, just diagnosed via a different inheritance path.

### Key invariants extracted

1. The trigger is **NOT** `@_rawLayout`. Without `@_rawLayout`, the bug still fires (V4, V12, V14, V15, V16, V17). The brief's hypothesis was wrong on this dimension.
2. The trigger is **NOT** custom `deinit`. Without a deinit, the bug still fires (V3, V13, V15, V17). The deinit was incidental, not load-bearing.
3. The trigger is **NOT** cross-module. Same module (V10, V16, V17) and single file (V10, V17) still trigger.
4. The trigger is **NOT** the `extension Storage.Foo where …` two-level shape. V6 with two-level extension still fires.
5. The trigger **IS** the unconditional conformance extension `extension Storage.Inline: SomeProtocol { … }` (no `where Element: ~Copyable`). Without it, the bug doesn't fire (V1, V11, V14, V19, V20).
6. The trigger **REQUIRES** the protocol to have at least one `associatedtype Element: ~Copyable` requirement OR be implicitly Copyable. A `~Copyable` protocol without that associated type does NOT trigger (V20).
7. The trigger **REQUIRES** at least one reference to `Element` inside the nested type's body — `@_rawLayout(likeArrayOf: Element, …)`, `Element.self`, `Index<Element>.…`, etc. (V14 with no Element refs passes).

### Refined trigger model (post-isolation)

**All-of:**

1. `enum Storage<Element: ~Copyable>` (or similar `~Copyable`-generic root)
2. `extension Storage where Element: ~Copyable { struct Inline<…>: ~Copyable { … } }` (nested-type declaration in a `~Copyable`-scoped extension)
3. At least one reference to `Element` inside Inline's body
4. **`extension Storage.Inline: SomeProtocol { … }`** WITHOUT `where Element: ~Copyable`, where `SomeProtocol` has an `associatedtype Element: ~Copyable` OR is implicitly Copyable

The bug fires regardless of file separation, regardless of module separation, regardless of access level (`public`/`package`), regardless of `@_rawLayout` presence, regardless of `deinit` presence.

## 7. Diagnostic investigation

Diagnostic ID via `-debug-diagnostic-names`:

```bash
swiftc -typecheck -Xfrontend -debug-diagnostic-names \
    storage_namespace.swift storage_inline.swift storage_inline_marker.swift
```

Yields:

```
error: type 'Element' does not conform to protocol 'Copyable' [#type_does_not_conform]
```

The `[#type_does_not_conform]` is the standard conformance-check diagnostic — confirms this is a type-checker rejection at requirement-check time. Searching the Swift compiler source for `type_does_not_conform` would land in `lib/Sema/CSDiagnostics.cpp` / `lib/Sema/TypeCheckGeneric.cpp` — not pursued in this investigation since the workaround is clean.

## 8. Step 4 — Duplicate search

Searched [`github.com/swiftlang/swift/issues`](https://github.com/swiftlang/swift/issues) for the following keyword combinations:

- `"extension" "where Element: ~Copyable" "does not conform to protocol 'Copyable'"`
- `noncopyable extension unconditional conformance "does not conform to protocol 'Copyable'"`
- `~Copyable extension implicit Copyable leak`
- `SE-0427 extension default Copyable constraint propagate`

**No exact match found.** Surfaced relevant proposals (SE-0427, SE-0499) and unrelated issues (#85212 swift_getTypeName, #87071 C++ interop). The closest in spirit is the documented SE-0427 rule that adding `extension X { }` implicitly constrains generic params to Copyable — but no upstream issue tracks the LEAK behavior described here.

[`ISSUE-001`] keyword-search blind-spot note: the upstream report — if it exists — may not use the words "leak" or "propagate" or "primary declaration". A future search should consider keywords like:

- `"failed to suppress" "Copyable" "extension"`
- `"associatedtype Element" "~Copyable" "extension conformance"`
- Swift Forums `~Copyable extension constraint scoping`

## 9. Workaround discovery

Tested four candidate workarounds (per the brief):

### Workaround A — co-location

**Hypothesis**: move `Storage.Inline` into the same module as `Storage`.

**Result**: NOT VIABLE. V10 (same-module, single-file, all declarations co-located) STILL FAILS with the same errors. Module separation is not the trigger.

Bonus disqualifier: moving the type into `Storage Primitive` would also violate [MOD-017] (the Namespace target has zero external deps).

### Workaround B — top-level `@_rawLayout` helper

**Hypothesis**: refactor `_Raw` to a top-level `package struct StorageInlineRaw<Element: ~Copyable, let capacity: Int>: ~Copyable`.

**Result**: NOT VIABLE. V4 confirms that the bug fires even WITHOUT `@_rawLayout`. The `@_rawLayout` site is not the trigger; the Element references generally are. A top-level `@_rawLayout` helper would not fix anything because the production code's `Element.self` references in the deinit body would still fail.

### Workaround C — eliminate the deinit body's `Element.self` references

**Hypothesis**: move the deinit's per-element cleanup to a same-module helper.

**Result**: NOT VIABLE. V15 confirms the bug fires for `Element.self` references in ANY method, not just `deinit`. `Storage.Inline` structurally requires Element references throughout — `@_rawLayout(likeArrayOf: Element, …)`, `pointer(at:)`, `_mutablePointer(at:)`, etc. Cannot eliminate them all without redesigning the type.

### Workaround D — add `where Element: ~Copyable` to the conformance extension

**Hypothesis**: re-state the `~Copyable` constraint on the conformance extension to suppress the SE-0427 default `Element: Copyable` requirement.

**Result**: **VIABLE — VERIFIED**. V2 against the standalone reproducer PASSES. Applied to the production file (one-line `sed` against `Storage.Inline+Memory.Contiguous.Protocol.swift` line 69), the full `Storage Inline Primitives` target typechecks cleanly:

```bash
$ swiftc -typecheck Sources/Storage\ Inline\ Primitives/*.swift \
    [production flags + RawLayout + Lifetimes + StrictMemorySafety] \
    [+ Workaround D applied to one line]
exit=0
```

This is the recommended workaround. The production diff is a single character insertion at line 69:

```diff
- extension Storage.Inline: Memory.Contiguous.`Protocol` {
+ extension Storage.Inline: Memory.Contiguous.`Protocol` where Element: ~Copyable {
```

The body of the conformance (the `withUnsafeBufferPointer` method) does not change. The conformance is intentionally available for all `Element` types — adding `where Element: ~Copyable` is INCLUSIVE (suppresses the default Copyable requirement; allows the conformance for both Copyable and ~Copyable Element types).

## 10. Open questions

- **Type-checker root cause**: Where in `lib/Sema/TypeCheckGeneric.cpp` (or wherever SE-0427's default-`Copyable` rule is implemented) does the extension-level constraint propagate beyond the extension scope? Investigation deferred — the empirical workaround is sufficient.
- **Other unconditional `~Copyable`-incompatible extensions in the ecosystem**: how many sibling packages have unconditional `extension X: SomeProtocol` declarations on `~Copyable` types? `Storage.Pool.Inline` and `Storage.Arena.Inline` build green — neither has the `Memory.Contiguous.Protocol` conformance, which is why they pass. A grep for `extension.*[A-Z].*<.*~Copyable.*>.*:.*Protocol` across the ecosystem may surface other latent-failure sites that today happen not to trigger due to having no Element refs in the body.
- **6.5-dev / future toolchains**: not tested (the dev toolchain `swift-latest.xctoolchain` is 6.4-dev). If the bug is fixed in a 6.5-dev snapshot, the workaround becomes removable. Workaround D, however, is inclusive — the `where Element: ~Copyable` clause is semantically valid Swift and not a `@_workaround` annotation; leaving it in place after the underlying defect is fixed has no adverse effect.

## 11. Recommended next step

Apply **Workaround D** at `swift-storage-primitives/Sources/Storage Inline Primitives/Storage.Inline+Memory.Contiguous.Protocol.swift` line 69. The production fix is a 1-character change inside the extension declaration. This unblocks Pilot 1.

The fix is principal-decided. This investigation does NOT modify swift-storage-primitives per the Pilot-1-paused discipline declared in the brief.

## 12. Cross-references

- Skill: [ISSUE-001], [ISSUE-002], [ISSUE-010], [ISSUE-013], [ISSUE-018], [ISSUE-020], [ISSUE-028]
- Related Issues entry: [`../swift-issue-rawlayout-noncopyable-deinit/`](../swift-issue-rawlayout-noncopyable-deinit/) — different bug (runtime, [#86652](https://github.com/swiftlang/swift/issues/86652) variant); this one is compile-time.
- Production trigger sites:
  - `swift-storage-primitives@ee86ee0` `Sources/Storage Inline Primitives/Storage.Inline+Memory.Contiguous.Protocol.swift` line 69 — unconditional conformance.
  - `swift-storage-primitives@ee86ee0` `Sources/Storage Inline Primitives/Storage.Inline.swift` lines 97/139/142/143 — error fires here.
- SE-0427 Noncopyable Generics — establishes the default `Copyable` rule that this bug exposes.
- Memory: an internal feedback note — the implicit-Copyable-on-bare-extension rule is known and documented in workspace memory; the cross-sibling LEAK is what this investigation surfaces as a bug.
