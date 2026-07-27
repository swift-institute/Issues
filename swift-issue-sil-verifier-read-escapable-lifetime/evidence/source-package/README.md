# Swift SIL Verifier Crash: `_read` yielding `~Escapable` value with `@_lifetime(borrow)`

> **Filed as**: [swiftlang/swift#87029](https://github.com/swiftlang/swift/issues/87029)

## Description

The compiler crashes (signal 6) during SIL verification when a `_read` coroutine yields a `~Copyable & ~Escapable` value whose initializer has a `@_lifetime(borrow)` lifetime dependency. The SIL verifier detects a double-consume: `mark_dependence [nonescaping]` and `destroy_value` both consume the yielded value.

This crash only occurs with the swift.org open-source toolchain (+assertions build). The Xcode-bundled toolchain (same version, no assertions) compiles successfully.

## Environment

- **Swift version (crashes)**: Apple Swift version 6.2.3 (swift-6.2.3-RELEASE), Build config: +assertions
- **Swift version (works)**: Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
- **Target**: arm64-apple-macosx26.0
- **Crash location**: SIL verifier, function `@$s24SILVerifierReadEscapable1PPAARi_zrlE7wrapperAA7WrapperVyxGvr`

## Minimal Reproduction (20 lines)

```swift
public struct Wrapper<Base: ~Copyable>: ~Copyable, ~Escapable {
    @usableFromInline
    var _base: UnsafeMutablePointer<Base>

    @inlinable
    @_lifetime(borrow base)
    public init(_ base: UnsafeMutablePointer<Base>) {
        unsafe _base = base
    }
}

public protocol P: ~Copyable {}

extension P where Self: ~Copyable {
    public var wrapper: Wrapper<Self> {
        mutating _read {
            yield unsafe Wrapper<Self>(&self)  // CRASHES
        }
    }
}
```

## To Reproduce

```bash
git clone https://github.com/coenttb/swift-issue-sil-verifier-read-escapable-lifetime
cd swift-issue-sil-verifier-read-escapable-lifetime
swift build  # Using swift.org 6.2.3-RELEASE toolchain (+assertions)
```

## Crash Output

```
Begin Error in Function: '$s24SILVerifierReadEscapable1PPAARi_zrlE7wrapperAA7WrapperVyxGvr'
Found over consume?!
Value:   %7 = apply ... Wrapper<Self>
User:   %8 = mark_dependence [nonescaping] %7 : $Wrapper<Self> on %5 : $UnsafeMutablePointer<Self>
Block: bb0
Consuming Users:
  destroy_value %7 : $Wrapper<Self>
  %8 = mark_dependence [nonescaping] %7 : $Wrapper<Self> on %5 : $UnsafeMutablePointer<Self>

End Error in Function: '$s24SILVerifierReadEscapable1PPAARi_zrlE7wrapperAA7WrapperVyxGvr'
Found ownership error?!
<unknown>:0: error: fatal error encountered during compilation; please submit a bug report
<unknown>:0: note: triggering standard assertion failure routine
```

## Conditions Required

All 5 conditions must be present to trigger the crash:

| # | Condition | Description |
|---|-----------|-------------|
| 1 | `~Copyable & ~Escapable` struct | The yielded type must be both non-copyable and non-escapable |
| 2 | `@_lifetime(borrow)` init | The struct's initializer must have a lifetime dependency |
| 3 | `_read` coroutine accessor | The property must use `_read` to yield the value |
| 4 | `where Self: ~Copyable` | The protocol extension must constrain Self as ~Copyable |
| 5 | +assertions toolchain | Only swift.org open-source builds with assertions enabled |

## Workaround

Use the Xcode-bundled Swift 6.2.3 toolchain instead of the swift.org open-source toolchain:

```bash
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift build
```

## Related Issues

- [#85275](https://github.com/swiftlang/swift/issues/85275) — ~Copyable/~Escapable crash with SIL ownership (related feature area, different trigger)
- [#80759](https://github.com/swiftlang/swift/issues/80759) — OSS 6.1 toolchain MoveOnlyChecker crash (same pattern: OSS-only assertion failure)

## Impact

This blocks all command-line builds for projects using `~Escapable` types with `_read` accessors when using the swift.org toolchain. Affects 61+ packages in the Swift Institute swift-primitives monorepo.
