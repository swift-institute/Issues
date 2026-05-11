# ~Copyable Value-Generic Deinit Bug

<!--
---
version: 1.0.0
last_updated: 2026-03-15
status: SUPERSEDED
superseded_by: noncopyable-ecosystem-state.md
tier: 2
---
-->

> **SUPERSEDED** (2026-04-02) by [noncopyable-ecosystem-state.md](noncopyable-ecosystem-state.md).
> All findings consolidated into the topic-based document. This file retained as historical rationale.

## Summary

The Swift compiler (6.2.4) does not correctly synthesize member destruction for `~Copyable` structs that have cross-package, value-generic stored properties backed by `@_rawLayout` storage. This manifests as two distinct sub-bugs: (A) the deinit body is silently skipped unless a reference-typed stored property is present, and (B) even when the deinit body executes, automatic member destruction of the stored buffer does not happen. A two-part workaround — adding a dummy `AnyObject?` property and manually draining elements via a mutable pointer in the deinit body — has been applied to 21 types across 9 packages in swift-primitives. Tracked as a variant of swiftlang/swift #86652.

## Bug Description

### Bug A: Deinit Body Silently Skipped

When a `~Copyable` struct has a cross-package, value-generic stored property (e.g., `Buffer<Element>.Ring.Inline<capacity>`) and no reference-typed stored properties, the compiler silently skips the entire deinit body. Code placed in the `deinit {}` block never executes.

This appears to be a codegen issue where the compiler's destruction sequence for the type omits the user-written deinit body when all stored properties are value types from other packages with value-generic parameters.

### Bug B: Automatic Member Destruction Not Synthesized

Even when Bug A is worked around (by adding a reference-typed stored property to force the deinit body to execute), the compiler does not synthesize automatic member destruction for the cross-package value-generic stored property. In a correctly-functioning compiler, after the user deinit body runs, the compiler should automatically destroy each stored property — calling their respective deinits, which in turn destroy their members recursively. This does not happen for the affected stored properties.

The result is that the entire nested chain of `~Copyable` types below the stored property is leaked: element destructors are never called, and memory is not cleaned up.

## Conditions

The bug triggers when **all** of the following conditions are met:

1. **~Copyable container**: The outer type conforms to `~Copyable`
2. **Cross-package stored property**: The stored property's type is defined in a different SwiftPM package
3. **Value-generic parameter**: The stored property's type has a value-generic parameter (e.g., `<let capacity: Int>`) threaded through from the container
4. **@_rawLayout storage**: The underlying storage uses `@_rawLayout` (as in `Storage<Element>.Inline<capacity>`)
5. **Generic element**: The element type is generic with `Element: ~Copyable`

The bug does **not** trigger in simplified reproductions that lack `@_rawLayout` storage. All 11 variants in the standalone experiment pass because they use plain Swift struct storage rather than the raw layout storage used in production.

### Production Chain (3 Separate Packages)

```
Queue.Static<capacity>              (swift-queue-primitives)  — outer container
  → Buffer<Element>.Ring.Inline<capacity>  (swift-buffer-primitives)  — middle buffer
    → Storage<Element>.Inline<capacity>    (swift-storage-primitives) — @_rawLayout storage
```

## Workaround

The workaround has two parts, addressing Bug A and Bug B respectively.

### Part 1: Force Deinit Body Execution

Add a reference-typed stored property to force the compiler to generate the deinit body:

```swift
extension Queue where Element: ~Copyable {
    public struct Static<let capacity: Int>: ~Copyable {
        @usableFromInline
        package var _buffer: Buffer<Element>.Ring.Inline<capacity>

        // WORKAROUND: Forces compiler to execute deinit body.
        // WHY: Without a reference-typed stored property, the compiler silently
        //      skips the deinit body for ~Copyable structs with cross-package
        //      value-generic stored properties.
        // TRACKING: swiftlang/swift #86652 variant
        private var _deinitWorkaround: AnyObject? = nil
    }
}
```

The `AnyObject?` property is always `nil` and has no runtime cost beyond one pointer of storage. Its presence forces the compiler to emit the deinit body because it must release the optional reference.

### Part 2: Manual Element Cleanup via Mutable Pointer

Because automatic member destruction does not fire (Bug B), the deinit body must manually clean up elements through the mutating codepath:

```swift
deinit {
    // WORKAROUND: Manually clean up elements via the mutating path.
    // WHY: The compiler does not synthesize member destruction for _buffer
    //      (cross-package, value-generic ~Copyable stored property).
    //      Buffer.Ring.Inline's deinit never fires, so we call remove.all()
    //      through a mutable pointer — this uses the mutating codepath
    //      (header+storage deinitialize) which is not affected by the bug.
    // TRACKING: swiftlang/swift #86652 variant
    unsafe withUnsafePointer(to: _buffer) { ptr in
        unsafe UnsafeMutablePointer(mutating: ptr).pointee.remove.all()
    }
}
```

## Key Insight

The destruction codepath and the mutating codepath use different mechanisms to access the underlying storage:

- **Destruction path** (`storage.deinitialize()` via `Property.View`): Broken. The compiler fails to invoke this path for cross-package value-generic stored properties. The `deinit` of `Buffer.Ring.Inline` is never called, so its stored `Storage.Inline` is never deinitialized, and elements are leaked.

- **Mutating path** (`_removeAll()` via `remove.all()`): Works. This path uses `_modify` accessors on the storage, which correctly access the `@_rawLayout` backing memory. The mutating path deinitializes each element individually and resets the header, achieving the same cleanup that automatic destruction should perform.

The mutable pointer cast (`UnsafeMutablePointer(mutating: ptr)`) is necessary because `deinit` receives `self` as an immutable binding. The cast is sound because `self` is being consumed (destroyed), so no other references exist.

## Applied Locations

The workaround has been applied to 21 types across 9 packages in swift-primitives. All types follow the same pattern: a `~Copyable` container with a cross-package, value-generic inline buffer stored property.

### Queue Primitives (`swift-queue-primitives`)
- `Queue.Static<capacity>`
- `Queue.DoubleEnded.Static<capacity>`
- `Queue.Small` (enum-wrapped variant)
- `Queue.DoubleEnded.Small`

### Buffer Primitives (`swift-buffer-primitives`)
- Canary tests confirm the bug for all 4 inline buffer types: Ring, Linear, Arena, Slab

### Other Packages
- `Array.Static`, `Array.Small` (swift-array-primitives)
- `Stack.Static`, `Stack.Small` (swift-stack-primitives)
- `Heap.Static`, `Heap.Small` (swift-heap-primitives)
- `Heap.MinMax.Static`, `Heap.MinMax.Small` (swift-heap-primitives)
- `Set.Ordered.Static`, `Set.Ordered.Small` (swift-set-primitives)
- `Dictionary.Ordered.Static`, `Dictionary.Ordered.Small` (swift-dictionary-primitives)
- `Slab` (swift-slab-primitives)
- `List.Linked` (swift-list-primitives)
- `Tree.N.Inline`, `Tree.N.Small` (swift-tree-primitives)

## Experiment

**Path**: `Experiments/noncopyable-nested-deinit-chain/`

The experiment contains 11 variants testing increasingly complex nesting patterns:

| Variant | Description | Result |
|---------|-------------|--------|
| V1 | One level, direct (control) | PASS |
| V2 | Two levels, type generic only | PASS |
| V3 | Two levels, type + value generic | PASS |
| V4 | V3 + `_deinitWorkaround` | PASS |
| V5 | Outer wraps enum | PASS |
| V6 | Nested in generic extension | PASS |
| V7 | V6 + `_deinitWorkaround` | PASS |
| V8 | InlineArray in middle storage | PASS |
| V9 | V8 nested in generic extension | PASS |
| V10 | Deeply nested middle (production nesting) | PASS |
| V11 | V10 + `_deinitWorkaround` | PASS |

**Critical finding**: All 11 variants pass because the simplified reproduction uses plain Swift struct storage rather than `@_rawLayout` storage. The bug only manifests with `@_rawLayout`-backed `Storage<Element>.Inline<capacity>` as used in production. This was confirmed by canary tests in swift-buffer-primitives that exercise the real storage chain — those tests show `tracker.deinitOrder` returning `[]` for all 4 inline buffer types without the workaround.

## Upstream

**Tracking**: swiftlang/swift [#86652](https://github.com/swiftlang/swift/issues/86652) — originally filed for InlineArray + value generic deinit issues.

This is a variant of #86652 where the same root cause (incorrect destruction codegen for value-generic `~Copyable` types) manifests in cross-package nested `~Copyable` containers with `@_rawLayout` storage. The original issue focuses on `InlineArray`; our variant involves custom `Storage.Inline` types that use `@_rawLayout(like: InlineArray<capacity, Element>)`.

### When to Remove the Workaround

The workaround can be removed when the Swift compiler correctly:
1. Executes deinit bodies for `~Copyable` structs with cross-package value-generic stored properties (Bug A)
2. Synthesizes automatic member destruction for such stored properties (Bug B)

Removal should be validated by the canary tests in swift-buffer-primitives, which test deinit ordering without the workaround present.

## References

- **Experiment**: `Experiments/noncopyable-nested-deinit-chain/`
- **Queue.Static workaround**: `https://github.com/swift-primitives/swift-queue-primitives/blob/main/Sources/Queue Primitives Core/Queue.Static.swift`
- **Queue.DoubleEnded.Static workaround**: `https://github.com/swift-primitives/swift-queue-primitives/blob/main/Sources/Queue Primitives Core/Queue.DoubleEnded.Static.swift`
- **Buffer canary tests**: `https://github.com/swift-primitives/swift-buffer-primitives/blob/main/Tests/Buffer Ring Inline Primitives Tests/Buffer.Ring.Inline Canary Tests.swift`
- **Storage inline deinit research**: `https://github.com/swift-primitives/swift-storage-primitives/blob/main/Research/inline-deinit-ownership.md`
- **Swift issue**: https://github.com/swiftlang/swift/issues/86652
