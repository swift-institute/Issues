# Swift Issue: Unconditional Protocol Conformance Leaks `Copyable` to Primary Declaration of ~Copyable-Generic Nested Type

**Upstream**: Not yet filed.
**Status**: STILL BROKEN on Swift 6.3.2 (default, `swiftlang-6.3.2.1.108`) AND Swift 6.4-dev nightly (`swift-latest.xctoolchain`). Reproducer at [`Sources/`](Sources/). **NOT fix-on-dev.**
**Production blocker**: `swift-storage-primitives@ee86ee0` Cohort III Pilot 1 [MOD-031] restructure — `Sources/Storage Inline Primitives/Storage.Inline.swift` lines 97/139/142/143.

## Trigger characterization

The error "type 'Element' does not conform to protocol 'Copyable'" fires inside
the primary declaration of a `~Copyable`-generic nested type when an UNCONDITIONAL
protocol-conformance extension on the same type appears elsewhere in the module
(same file, same target, or even cross-module).

Per SE-0427 Noncopyable Generics: "An extension of a concrete type must
introduce a default `T: Copyable` requirement on every generic parameter of the
extended type." The expected behavior is for that constraint to apply ONLY to
the extension's body. The observed behavior is that the constraint LEAKS BACK
to the primary type declaration and any sibling extensions, contradicting the
outer `extension Storage where Element: ~Copyable` clause.

**Single-line summary**: Adding `extension Storage.Inline: SomeProtocol { … }`
(without `where Element: ~Copyable`) causes a type error at every `Element`
reference inside `Storage.Inline`'s body, declared in a sibling extension.

## Conditions (all required)

1. **Root namespace** declared with `~Copyable` generic param: `enum Storage<Element: ~Copyable> {}`.
2. **Nested type** declared in an `extension Storage where Element: ~Copyable` clause: `public struct Inline<…>: ~Copyable { … }`.
3. **Reference to `Element` inside the nested type's body** — ANY of:
   - `@_rawLayout(likeArrayOf: Element, count: …)` on an inner struct
   - `_ = Element.self` in a method or deinit body
   - Other Element-typed expressions in member declarations
4. **Unconditional protocol-conformance extension** on the nested type, with NO `where Element: ~Copyable` clause:
   ```swift
   extension Storage.Inline: SomeProtocol { … }   // ← triggers the leak
   ```
   The protocol must have at least one `associatedtype Element: ~Copyable` requirement, OR be implicitly `Copyable` (V18 still fails but with a different
   error wording). A `~Copyable` protocol with NO `associatedtype Element` does NOT trigger (V20 PASSES).

**Trigger MINIMUM** (verified at `swiftc -typecheck` against Swift 6.3.2):

```swift
public enum Storage<Element: ~Copyable> {}
public protocol Marker: ~Copyable {
    associatedtype Element: ~Copyable
}

extension Storage where Element: ~Copyable {
    public struct Inline: ~Copyable {
        public init() {}
        public func foo() {
            _ = Element.self   // ← error: type 'Element' does not conform to protocol 'Copyable'
        }
    }
}

extension Storage.Inline: Marker {}   // ← THE TRIGGER (no `where`)
```

This 13-line shape reproduces the bug **in a single file, single module, no `@_rawLayout`, no `deinit`, no value-generic capacity, no cross-module split**. The `@_rawLayout` / `deinit` / cross-module structure in the production code are NOT load-bearing for the trigger — they merely happen to be present in the swift-storage-primitives consumer.

## Variable isolation table

See [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) for the full 17-variant matrix. Headline results:

| Variant | Mod | @_rawLayout | deinit | Where on conformance | Result |
|--------:|:----|:------------|:-------|:---------------------|:-------|
| V0 (baseline) | cross | yes | yes | no | **FAIL** (2 errors) |
| V1 (no conformance) | cross | yes | yes | n/a | PASS |
| V2 (Workaround D) | cross | yes | yes | **yes** (`~Copyable`) | **PASS** |
| V3 (no deinit) | cross | yes | no | no | FAIL |
| V4 (no @_rawLayout) | cross | no | yes | no | FAIL |
| V10 (co-located, single module) | same | yes | yes | no | FAIL |
| V16 (single module, two files) | same | no | yes | no | FAIL |
| V17 (single module, NO inner struct, NO @_rawLayout, NO deinit) | same | no | no (method) | no | FAIL |
| V19 (bare extension, no protocol) | cross | yes | yes | n/a | **PASS** |
| V20 (protocol without `associatedtype Element`) | same | no | no | no | **PASS** |
| V21 (Element associatedtype, no typealias) | same | no | no | no | FAIL |

## Workaround

**Workaround D** (verified empirically on production source — see [INVESTIGATION-ARC.md](INVESTIGATION-ARC.md) §Workaround discovery):

Add `where Element: ~Copyable` to the conformance extension:

```diff
- extension Storage.Inline: Memory.Contiguous.`Protocol` {
+ extension Storage.Inline: Memory.Contiguous.`Protocol` where Element: ~Copyable {
      // body unchanged
  }
```

This suppresses the default `Element: Copyable` constraint per SE-0427 and the leak is eliminated. Verified against the actual production file at `swift-storage-primitives/Sources/Storage Inline Primitives/Storage.Inline+Memory.Contiguous.Protocol.swift` line 69 — a one-line change builds the entire `Storage Inline Primitives` target clean (12 → 13 of 13 targets green).

**Workarounds NOT viable**:

- **A (co-location)** — V10/V16 prove same-module DOES still trigger. Moving the conformance to the namespace target would not fix the bug AND would violate [MOD-017].
- **B (top-level `@_rawLayout` helper)** — the bug fires even without `@_rawLayout` (V4, V14, V17). The trigger is the unconditional conformance, not `@_rawLayout`.
- **C (eliminate `Element.self` refs in deinit)** — V13 / V15 prove any Element reference triggers (including in `@_rawLayout` site, in regular methods, in any member). Storage.Inline structurally requires Element references.

## Applied locations

**Production blocker**:

- `swift-primitives/swift-storage-primitives@ee86ee0` (Cohort III Pilot 1 [MOD-031] restructure)
  - `Sources/Storage Inline Primitives/Storage.Inline+Memory.Contiguous.Protocol.swift` line 69 — the conformance is unconditional.
  - `Sources/Storage Inline Primitives/Storage.Inline.swift` lines 97 (`@_rawLayout`), 139 (`bitIndex.retag(Element.self)`), 142 (`Index<Element>.Offset`), 143 (`assumingMemoryBound(to: Element.self)`) — error fires here.

The production fix (Workaround D) is a one-line change. **The principal decides on application** — this investigation does NOT modify swift-storage-primitives per the Pilot-1-paused discipline.

## Cross-references

- Related but **distinct** bug — [`swift-issue-rawlayout-noncopyable-deinit`](../swift-issue-rawlayout-noncopyable-deinit/README.md). That bug is a RUNTIME deinit-not-firing defect on cross-package value-generic `@_rawLayout` chains (`swiftlang/swift#86652` variant). THIS bug is a COMPILE-TIME type-checking defect with no `@_rawLayout` dependency.
- SE-0427 Noncopyable Generics — establishes the default `T: Copyable` rule for concrete extensions. The leak-back behavior contradicts the proposal's scope ("on the extension").
- `swift-institute/Research/swift-compiler-bug-catalog.md` — append entry.
- Memory: an internal feedback note — the implicit constraint rule is known; the LEAK behavior is the bug.

## Reproducer

Module A and Module B sources are at [`Sources/ReproducerStorageNamespace/`](Sources/ReproducerStorageNamespace/) and [`Sources/ReproducerStorageInline/`](Sources/ReproducerStorageInline/).

```bash
cd Sources && cp ReproducerStorageNamespace/storage_namespace.swift .
cp ReproducerStorageInline/storage_inline.swift .
cp ReproducerStorageInline/storage_inline_marker.swift .

swiftc -module-name StorageNamespaceLib \
       -emit-module -emit-library -enable-library-evolution \
       -enable-experimental-feature SuppressedAssociatedTypes \
       storage_namespace.swift
# → exit 0

swiftc -module-name StorageInlineLib -I . -L . -lStorageNamespaceLib \
       -emit-module -emit-library -enable-library-evolution \
       -enable-upcoming-feature InternalImportsByDefault \
       -enable-upcoming-feature MemberImportVisibility \
       -enable-experimental-feature LifetimeDependence \
       -enable-experimental-feature SuppressedAssociatedTypes \
       -enable-experimental-feature RawLayout \
       storage_inline.swift storage_inline_marker.swift
# → error: type 'Element' does not conform to protocol 'Copyable' (×2)

# Apply Workaround D:
sed -i.bak 's|extension Storage.Inline: Marker {|extension Storage.Inline: Marker where Element: ~Copyable {|' storage_inline_marker.swift

# Re-run the Inline build:
swiftc -module-name StorageInlineLib … storage_inline.swift storage_inline_marker.swift
# → exit 0
```

## SwiftPM `Package.swift` integration — DEFERRED

The standing per-issue convention (sibling `swift-issue-pointer-arithmetic-linux-miscompile/`) declares one `Tests/Reproducer.swift` + one `Sources/Reproducer/main.swift` per issue, both runtime artifacts. This is a **rejects-valid** bug — the reproducer is a build-failure check. The flip-on-fix signal needs different infrastructure (e.g. a CI step that EXPECTS the build to fail until upstream fixes), which the principal decides on. The two sub-module sources at `Sources/ReproducerStorageNamespace/` and `Sources/ReproducerStorageInline/` are not currently wired into the Issues `Package.swift`; integration is deferred.

## Status notes

- **NOT fix-on-dev** — verified by parent agent + this investigation (`TOOLCHAINS=swift swiftc storage_inline.swift storage_inline_marker.swift` reproduces).
- **SE-Proposal context** — SE-0427 (in 6.0), SE-0499 (in 6.2), SE-0503, SE-0519 are the relevant `~Copyable` corpus. SE-0427 documents the default-`Copyable` rule for extensions; none of the four explicitly states whether that constraint should be visible only within the extension body or visible across all extensions/sibling-declarations of the type. The empirical observation (V0 leak, V2 workaround) suggests the implementation visibly leaks beyond the proposal's documented scope.
- **Suggested labels** for upstream filing: `bug`, `noncopyable`, `extensions`, `type-checker`, `rejects-valid`.
