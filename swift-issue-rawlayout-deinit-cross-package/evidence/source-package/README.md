# Swift Bug: @_rawLayout deinit not called cross-module with generic-dependent layout

## Swift Issue

Related to [swiftlang/swift#86652](https://github.com/swiftlang/swift/issues/86652) — this reproduction isolates the bug to `@_rawLayout` directly (without `InlineArray`).

## Description

The `deinit` of a `~Copyable` struct containing an `@_rawLayout(likeArrayOf: T, count: N)` field is silently skipped when used **cross-module**. The same code works correctly in a single module.

**In cross-module Release mode (-O), the compiler crashes with an LLVM verification error.**

## Environment

Tested on:

| Toolchain | Version | Result |
|-----------|---------|--------|
| Xcode 26.2 | Swift 6.2.3 | Bug present |
| Xcode 26.3 | Swift 6.2.4 | Bug present |
| main snapshot | Swift 6.4-dev (2026-03-16) | Bug present |

## Minimal Reproduction

```swift
// In library module (ContainerLib)
public struct Box<T, let N: Int>: ~Copyable {
    @_rawLayout(likeArrayOf: T, count: N)
    struct Raw: ~Copyable { init() {} }

    var raw: Raw
    public init() { raw = Raw() }
    @inline(never) deinit { print("Box.deinit") }  // BUG: Never called cross-module
}
```

```swift
// In test/executable module (imports ContainerLib)
do { var b = Box<Int, 4>(); _ = consume b }
// Expected: "Box.deinit"
// Actual: (nothing)
```

## To Reproduce

```bash
git clone https://github.com/coenttb/swift-issue-rawlayout-deinit-cross-package
cd swift-issue-rawlayout-deinit-cross-package

# Cross-module tests
swift test              # Debug: deinit skipped
swift test -c release   # Release: COMPILER CRASH

# Single-module (works correctly)
swift run SingleModuleTest            # Debug: deinit works ✅
swift run -c release SingleModuleTest # Release: deinit works ✅
```

## Test Results Matrix

| Test | Single-Module Debug | Single-Module Release | Cross-Module Debug | Cross-Module Release |
|------|---------------------|----------------------|--------------------|--------------------|
| `Box<Int, 4>` | ✅ deinit | ✅ deinit | ❌ **skipped** | 💥 **crash** |
| `BoxFixed<Int, 4>` | ✅ deinit | ✅ deinit | ✅ deinit | — |
| `BoxWithToken<Int, 4>` | ✅ both | ✅ both | ✅ both | — |

**Key finding**: The bug is **cross-module specific**. Same code works in single module.

## Cross-Module Release Crash

```
error: compile command failed due to signal 6
Instruction does not dominate all uses!
  %16 = load i64, ptr %15, align 8, !dbg !520, !invariant.load !51
  %23 = mul i64 %16, %5, !dbg !520
<unknown>:0: error: fatal error encountered during compilation
<unknown>:0: note: Broken module found, compilation aborted!

Stack dump:
0.  Running pass "verify" on module "...ContainerLib.build/Container.swift.o"
```

## Token Test (Diagnostic)

Adding a reference-counted class property forces a destroy path and makes deinit work:

```swift
public struct BoxWithToken<T, let N: Int>: ~Copyable {
    @_rawLayout(likeArrayOf: T, count: N)
    struct Raw: ~Copyable { init() {} }

    var raw: Raw
    public let token: Token  // Adding this makes deinit work cross-module!
    ...
}
```

This confirms the compiler incorrectly classifies the type as "trivially destructible" when importing cross-module.

## Likely Cause

The compiler's destroyability/triviality information for `@_rawLayout` types with generic-dependent layouts is not being correctly serialized/deserialized across module boundaries. When importing:
1. Debug: destroy operation is not emitted, deinit skipped
2. Release: invalid IR is generated, LLVM verifier fails

## Control Cases

| Variant | Description | Cross-Module Result |
|---------|-------------|---------------------|
| `@_rawLayout(like: Int)` | Fixed layout, no generics | ✅ Works |
| `@_rawLayout(likeArrayOf: T, count: N)` | Generic-dependent layout | ❌ Bug |
| Same type + Token class | Forces nontrivial destroy | ✅ Works |

## Workarounds

| Workaround | Result |
|------------|--------|
| `consume b` | ❌ Does not fix |
| `withExtendedLifetime` | ❌ Does not fix |
| Add reference-counted property | ✅ Forces destroy path |
| Keep types in same module | ✅ Works (defeats modularity) |

## Notes

- The original filing (#86652) described this as "InlineArray + value generics". Subsequent experimentation narrowed the root cause to `@_rawLayout` with generic-dependent layout specifically. Value generics and `InlineArray` are non-contributing factors.
- Commit `ac072dad89a` ("CrossModuleOptimization: correctly serialize value-type deinits", 2026-02-18) serializes the `SILMoveOnlyDeinit` table for cross-module deinit de-virtualization, but does **not** fix this bug. The issue is in member destruction synthesis (triviality classification), not deinit availability.
- Still broken on `main` (Swift 6.4-dev, snapshot 2026-03-16).

## Impact

- Blocks production use of `@_rawLayout` for generic ~Copyable container types in libraries
- Any ~Copyable collection using @_rawLayout with generic element/capacity leaks resources when used as a dependency
- Cross-module release builds crash the compiler
- Workaround (`AnyObject? = nil` + manual cleanup in deinit) applied to 21 types across 9 packages in production code
