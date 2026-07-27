# Extension on deeply nested generic `~Copyable` type fails with type resolution error

## Description

An empty extension on a deeply nested generic `~Copyable` type fails to compile when declared in the **same file** as the type definition. Moving the extension to a separate file works around the issue.

The compiler produces a cascade of errors starting with incorrect namespace resolution (`Binary.Binary` instead of `Binary`).

## Reproduction

The bug occurs in a real codebase but could not be minimally reproduced in a standalone package. To reproduce:

```bash
git clone https://github.com/swift-standards/swift-standards
cd swift-standards

# Uncomment the extension
sed -i '' 's|//extension Binary.Cursor.Set.Reader {}|extension Binary.Cursor.Set.Reader {}|' Sources/Binary/Binary.Cursor.swift

# Build
swift build --target Binary
```

Alternatively, see: https://github.com/coenttb/swift-nested-copyable-extension-bug

## Expected behavior

The empty extension should compile:

```swift
extension Binary.Cursor.Set.Reader {}
```

## Actual behavior

Compilation fails with:

```
error: 'Mutable' is not a member type of enum 'Binary.Binary'
   public struct Cursor<Storage: Binary.Mutable>: ~Copyable {
                                         `- error: 'Mutable' is not a member type of enum 'Binary.Binary'
```

Note the erroneous `Binary.Binary` - the compiler doubles the namespace during type resolution.

This triggers a cascade of ~50 additional errors as the entire type hierarchy becomes unresolvable.

## Key observations

| Scenario | Result |
|----------|--------|
| Extension in same file | ❌ Fails |
| Extension in different file | ✅ Works |
| Empty extension body | ❌ Fails |
| Sibling extension (`Binary.Cursor.Move.Reader`) | ✅ Works |
| Methods defined inline in struct | ✅ Works |

## Type structure

```swift
public enum Binary {
    public protocol Contiguous: ~Copyable {
        associatedtype Space
        associatedtype Scalar: FixedWidthInteger & Sendable = Int
    }
    public protocol Mutable: Binary.Contiguous {}

    public typealias Position<Scalar, Space> = Coordinate.X<Space>.Value<Scalar>

    public struct Cursor<Storage: Binary.Mutable>: ~Copyable { ... }
}

extension Binary.Cursor {
    public struct Set: ~Copyable { ... }
}

extension Binary.Cursor.Set {
    public struct Reader: ~Copyable { ... }
}

// This fails:
extension Binary.Cursor.Set.Reader {}
```

## Environment

- **Swift version:** 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
- **Platform:** macOS 26.0 (arm64-apple-macosx26.0)
- **swift-driver version:** 1.127.14.1

## Workaround

Define methods inline in the struct definition instead of using separate extensions.
