# Swift SILGen Crash: Cross-Module Parameter Pack Expansion

## Description

The Swift compiler crashes with signal 11 during SIL generation when calling a function from **another module** that takes a parameter pack expansion `(repeat each T)` as an argument.

The same code works correctly when the function is defined in the **same module**.

## Environment

- **Swift version**: 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
- **Target**: arm64-apple-macosx26.0
- **Crash location**: `emitPackExpansionIntoPack` in SILGenApply.cpp

## Minimal Reproduction

**LibraryA** (defines the function):
```swift
public enum Tuple {
    public enum Append {}
}

extension Tuple.Append {
    @inlinable
    public static func apply<each T, U>(
        _ tuple: (repeat each T),
        _ element: U
    ) -> (repeat each T, U) {
        (repeat each tuple, element)
    }
}
```

**LibraryB** (calls the function — CRASHES):
```swift
public import LibraryA

@inlinable
public func combine<each O1, O2>(
    _ first: (repeat each O1),
    _ second: O2
) -> (repeat each O1, O2) {
    Tuple.Append.apply(first, second)  // ❌ CRASHES
}
```

## To Reproduce

```bash
git clone https://github.com/coenttb/swift-issue-silgen-pack-expansion-cross-module
cd swift-issue-silgen-pack-expansion-cross-module
swift build
```

## Crash Output

```
error: compile command failed due to signal 11 (use -v to see invocation)
Stack dump:
0.  Program arguments: swift-frontend -frontend -emit-module ...
1.  Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
2.  Compiling with the current language version
3.  While evaluating request ASTLoweringRequest(Lowering AST to SIL for module LibraryB)
4.  While silgen emitFunction SIL function "@$s8LibraryB7combine..."
    for 'combine(_:_:)' (at .../Caller.swift:21:1)

4  swift-frontend  emitPackExpansionIntoPack(...) + 492
5  swift-frontend  emitPackExpansionIntoPack(...) + 492
6  swift-frontend  emitDynamicPackLoop(...) + 1904
7  swift-frontend  ArgEmitter::emitPackArg(...) + 3532
...
```

## Key Stack Frames

| Frame | Function | File |
|-------|----------|------|
| 4-5 | `emitPackExpansionIntoPack` | SILGenApply.cpp |
| 6 | `emitDynamicPackLoop` | SILGenPack.cpp |
| 7 | `ArgEmitter::emitPackArg` | SILGenApply.cpp |

## Conditions Required

All three conditions must be present to trigger the crash:

| Condition | Description |
|-----------|-------------|
| 1. Cross-module call | Function defined in module A, called from module B |
| 2. Pack expansion argument | Passing `(repeat each T)` as function argument |
| 3. `@inlinable` | Function must be inlinable (for cross-module inlining) |

## Verified Test Results

| Test | Description | Result |
|------|-------------|--------|
| Same module | Function and caller in same module | ✅ Compiles |
| Cross-module | Function in LibraryA, caller in LibraryB | ❌ Crashes |
| Inline expression | `(repeat each tuple, element)` directly | ✅ Compiles |
| Function call | `Tuple.Append.apply(tuple, element)` | ❌ Crashes |

## Workaround

Inline the pack expansion expression instead of calling a cross-module function:

```swift
// Instead of:
Tuple.Append.apply(tuple, element)  // ❌ Crashes

// Use:
(repeat each tuple, element)  // ✅ Works
```

This workaround prevents code reuse across modules for pack expansion operations.

## Impact

This bug blocks:
- Creating reusable tuple/product utilities in shared libraries
- Result builder implementations that want to share pack manipulation code
- Any cross-module abstraction over parameter pack operations

## Related Issues

This may be related to:
- [#84568](https://github.com/swiftlang/swift/issues/84568) - Crash in visitPackExpansionExpr
- [#67645](https://github.com/swiftlang/swift/issues/67645) - Crash calling variadic generic function with pack expansion
- [#76391](https://github.com/swiftlang/swift/issues/76391) - Parameter pack crashes within generic type
