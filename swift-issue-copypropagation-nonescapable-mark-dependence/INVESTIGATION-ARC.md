# Compiler PR Handoff: Fix mark_dependence Simplification for ~Escapable Coroutine Yields

<!--
---
version: 2.0.0
last_updated: 2026-03-22
status: FIX_IMPLEMENTED
---
-->

## Context

This document provides a comprehensive handoff for contributing a fix to the Swift compiler for [swiftlang/swift#88022](https://github.com/swiftlang/swift/issues/88022) — CopyPropagation crash with `~Escapable` + `@_lifetime(borrow)` across control flow in release builds.

## Root Cause (Fully Traced via SIL Dumps)

The original hypothesis (mark_dependence settling to [escaping]) was **wrong**. SIL dumps prove all mark_dependence resolve correctly to [nonescaping]. The actual bug is a multi-pass interaction:

### Bug Chain

1. **`PredictableDeadAllocationElimination`** (Core, mandatory pass #32):
   - The `_read` accessor's SIL has `mark_dependence [nonescaping] %init on %alloc_stack`
   - This pass eliminates the `alloc_stack`, changing the mark_dependence base to a trivial value (`struct $UnsafeMutablePointer`)
   - During deletion of the old mark_dependence, the `InstructionDeleter` inserts a compensating `destroy_value` for the init result
   - Result: the init result now has BOTH a `mark_dependence` (ForwardingConsume) AND a `destroy_value` — double consume

2. **`SILCombine`** (Core, optimization pass #14):
   - `SimplifyMarkDependence.isRedundant` sees the mark_dependence base is a trivial object → removes it
   - RAUW replaces all uses of the mark_dependence result with the init result
   - The `destroy_value` (from step 1) + yield + bb1/bb2 destroys now ALL target the same value
   - Result: triple consume of the init result

3. **`DeinitDevirtualizer`** (Core, optimization pass #20):
   - Converts `destroy_value` → `end_lifetime` for ~Copyable types
   - The triple consume becomes triple `end_lifetime`

4. **Serialization**: The malformed SIL is serialized with the Core module

5. **`EarlyPerfInliner`** (Middle module): Inlines the accessor into the consumer, propagating the double `end_lifetime`

6. **`CopyPropagation`** (Middle module): Verifies ownership → crash: "Found over consume?!"

### Evidence

SIL dump of the `_read` accessor before and after SILCombine (Core module):

**Before SILCombine** (correct ownership, two separate values):
```sil
%6 = apply init(...)                              // @owned View
%7 = mark_dependence [nonescaping] %6 on %4       // forwards from %6
destroy_value %6                                  // destroys forwarded-from (from PredictableDeadAllocationElim)
yield %7, resume bb1, unwind bb2                  // yields mark_dependence result
bb1: destroy_value %7                             // cleanup
bb2: destroy_value %7                             // cleanup
```

**After SILCombine** (broken — mark_dependence removed, triple consume):
```sil
%6 = apply init(...)
destroy_value %6                                  // STILL HERE
yield %6                                          // %7 → %6 (RAUW)
bb1: destroy_value %6                             // %7 → %6 (RAUW)
bb2: destroy_value %6                             // %7 → %6 (RAUW)
```

## The Fix

### File Changed

`SwiftCompilerSources/Sources/Optimizer/InstructionSimplification/SimplifyMarkDependence.swift`

### Change

In `isRedundant`, add a guard for non-escapable value types in the trivial-base case. This is directly analogous to the existing guard at line 59-61 for address types:

```swift
if base.type.isObject && base.type.isTrivial(in: base.parentFunction)
     && !(base.definingInstruction is BeginApplyInst) {
  // ... existing comments ...
  //
  // For non-escapable types, the mark_dependence carries lifetime dependency
  // information and participates in ownership forwarding. Removing it when
  // the value operand is non-escapable can create ownership violations
  // (double consume) because earlier passes like PredictableDeadAllocationElimination
  // may have inserted a destroy_value of the forwarded-from value when
  // promoting the mark_dependence base from an alloc_stack to the stored value.
  if !valueOrAddress.type.isEscapable(in: parentFunction) {
    return false
  }
  return true
}
```

### Test Added

`test/SILOptimizer/sil_combine_mark_dependence_nonescapable.sil` — verifies SILCombine preserves the mark_dependence for ~Escapable types with trivial bases.

### Deeper Root Cause (for future work)

The upstream issue is in `PredictableDeadAllocationElimination` (`lib/SILOptimizer/Mandatory/PredictableMemOpt.cpp`). When promoting a mark_dependence base from `alloc_stack` to the stored value, the `InstructionDeleter.forceDelete` of the old mark_dependence inserts a compensating `destroy_value` for the value operand. This is incorrect because the value operand is already consumed by the NEW mark_dependence (created in `promoteMarkDepBase`). This deserves a separate investigation.

## Standalone Reproducer

Repository: https://github.com/coenttb/swift-issue-copypropagation-nonescapable-mark-dependence

```bash
cd swift-issue-copypropagation-nonescapable-mark-dependence
swift build            # ✅ Debug builds
swift build -c release # ❌ Crashes with "Found over consume?!"
```

## SIL Dump Commands

```bash
# Correct syntax for SIL dump flags (via -Xllvm, double dashes):
swift build -c release \
  -Xswiftc -Xllvm -Xswiftc '--sil-print-all' \
  -Xswiftc -Xllvm -Xswiftc '--sil-print-function=$s4Core9ContainerVAARi_zrlE6accessAA4ViewVAARi__rlE5TypedVyAA6AccessOACyxG_xGvr'

# Print around a specific pass:
swift build -c release \
  -Xswiftc -Xllvm -Xswiftc '--sil-print-around=sil-combine' \
  -Xswiftc -Xllvm -Xswiftc '--sil-print-function=...'
```

## Key Files in Compiler Source

| File | Purpose | Key Lines |
|------|---------|-----------|
| `SwiftCompilerSources/.../SimplifyMarkDependence.swift` | **THE FIX** — mark_dependence simplification | 44-55 (isRedundant, trivial base) |
| `lib/SILOptimizer/Mandatory/PredictableMemOpt.cpp` | Deeper root cause — dead alloc elimination | 2331-2346 (promoteMarkDepBase) |
| `lib/SILOptimizer/Utils/SILInliner.cpp` | Coroutine inlining (propagates the bug) | 96-330 (BeginApplySite) |
| `lib/SILOptimizer/Transforms/CopyPropagation.cpp` | Pass that catches the error | 686-688 (verifyOwnership) |
| `lib/SIL/IR/OperandOwnership.cpp` | Operand classification | 699-720 (visitMarkDependenceInst) |

## Building and Testing

```bash
cd swift

# Build the compiler:
utils/build-script --skip-build-benchmarks --skip-ios --skip-watchos --skip-tvos --release-debuginfo

# Test the fix:
llvm-lit test/SILOptimizer/sil_combine_mark_dependence_nonescapable.sil
llvm-lit test/SILOptimizer/lifetime_dependence/

# Test with reproducer:
/path/to/built/swift build -c release  # in the reproducer directory
```

## What Success Looks Like

- The new SIL test passes (`sil_combine_mark_dependence_nonescapable.sil`)
- The reproducer builds in release mode without crashing
- No `@_optimize(none)` needed on consumer functions
- Existing lifetime_dependence and copy_propagation tests pass
- `~Escapable` types can be safely used with `@_lifetime(borrow)` in coroutine-yielded patterns

## Related Resources

- Issue: https://github.com/swiftlang/swift/issues/88022
- Related issue (Bug 1): https://github.com/swiftlang/swift/issues/86652
- Research: `https://github.com/swift-primitives/swift-property-primitives/blob/main/Research/property-view-escapable-removal.md`
- Reflection: `Research/Reflections/2026-03-22-copypropagation-nonescapable-root-cause-and-fix.md`
