# Swift SILGen Crash: Property Wrapper + ~Copyable Cross-Module

## Swift Issue

This is a cross-module reproduction of [swiftlang/swift#81624](https://github.com/swiftlang/swift/issues/81624).

## Description

The compiler crashes (signal 11) during SIL generation when accessing a property that uses a property wrapper on a `~Copyable` type across module boundaries.

**Note**: `@inlinable`, `@frozen`, and `@usableFromInline` are NOT required to trigger this crash.

## Environment

- **Swift version**: Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
- **Target**: arm64-apple-macosx26.0
- **Crash location**: `getBaseAccessKind()` in SILGenLValue.cpp

## Minimal Reproduction (20 lines library + 5 lines client)

```swift
// In Lib module:
@propertyWrapper
public struct Wrapper<Value: ~Copyable>: ~Copyable {
    private var _value: Value
    public init(wrappedValue: consuming Value) { _value = wrappedValue }
    public var wrappedValue: Value {
        _read { yield _value }
        _modify { yield &_value }
    }
}

public struct Box<Value: ~Copyable>: ~Copyable {
    @Wrapper public var value: Value
    public init(_ value: consuming Value) { self.value = value }
}

// In client module (Tests):
import Lib
func crash() {
    let box = Box<Int>(42)
    _ = box.value  // CRASHES
}
```

## To Reproduce

```bash
git clone https://github.com/coenttb/swift-issue-silgen-property-wrapper-noncopyable
cd swift-issue-silgen-property-wrapper-noncopyable
swift test
```

## Crash Output

```
error: compile command failed due to signal 11
Stack dump:
4.  While silgen emitFunction SIL function "@$s5Tests5crashyyF".
    for 'crash()' (at .../Crash.swift:3:1)

4  swift-frontend  getBaseAccessKind(...) + 224
5  swift-frontend  getBaseAccessKind(...) + 224
6  swift-frontend  SILGenLValue::visitMemberRefExpr(...) + 1544
```

## Conditions Required

Both conditions must be present:

| Condition | Description |
|-----------|-------------|
| 1. Property wrapper + `~Copyable` | Property wrapper used on a `~Copyable` type |
| 2. Cross-module | Type defined in one module, accessed in another |

**NOT required**: `@inlinable`, `@frozen`, `@usableFromInline`, `Sendable`

## Workaround

Don't use property wrappers on `~Copyable` types. Use manual storage instead:

```swift
public struct Box<Value: ~Copyable>: ~Copyable {
    private var _value: Value
    public init(_ value: consuming Value) { _value = value }
    public var value: Value {
        _read { yield _value }
        _modify { yield &_value }
    }
}
```

## Impact

This blocks using property wrappers on `~Copyable` types in cross-module scenarios, preventing code reuse patterns that work for `Copyable` types.
