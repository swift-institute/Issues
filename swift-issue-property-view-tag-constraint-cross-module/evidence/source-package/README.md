# Swift Bug: Property.View Extensions with Different Tag Constraints Report Invalid Redeclaration

## Swift Issue

Filed as [swiftlang/swift#86707](https://github.com/swiftlang/swift/issues/86707)

## Description

Swift incorrectly reports "invalid redeclaration" for `Property.View` extensions with **mutually exclusive** `Tag` constraints. The compiler ignores the `Tag ==` constraint when checking for declaration conflicts.

Two extensions like:
- `extension Property.View where Tag == Collection.Count, Base: Collection.Protocol`
- `extension Property.View where Tag == Collection.Remove, Base: Collection.Clearable`

Should never overlap because a `Property.View<Collection.Count, X>` can never satisfy `Tag == Collection.Remove`. Yet Swift reports one as a redeclaration of the other.

## Environment

- **Swift version**: Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
- **Target**: arm64-apple-macosx26.0
- **Required feature**: Lifetimes (experimental)

## Minimal Reproduction

See `Sources/CollectionLib/Collection.swift` - uncomment the buggy extensions to trigger the error.

```swift
// PropertyLib: View type with generic Tag
public struct Property<Tag, Base: ~Copyable>: ~Copyable { ... }
extension Property where Base: ~Copyable {
    @safe public struct View: ~Copyable, ~Escapable { ... }
}

// CollectionLib: Two extensions with DIFFERENT Tag constraints
extension Property.View where Tag == Collection.Count, Base: Collection.`Protocol` & ~Copyable {
    public var all: Int { 42 }  // note: 'all' previously declared here
}

extension Property.View where Tag == Collection.Remove, Base: Collection.Clearable & ~Copyable {
    public mutating func all() {}  // error: invalid redeclaration of 'all()'
}
```

## To Reproduce

```bash
git clone https://github.com/coenttb/swift-issue-property-view-tag-constraint-cross-module
cd swift-issue-property-view-tag-constraint-cross-module
# Uncomment the buggy code in Sources/CollectionLib/Collection.swift
swift build
```

## Error Output

```
error: invalid redeclaration of 'all()'
   |
   |     public var all: Int { 42 }  // note: 'all' previously declared here
   |                `- note: 'all' previously declared here
   :
   |     public mutating func all() {}  // error: invalid redeclaration of 'all()'
   |                          `- error: invalid redeclaration of 'all()'
```

## Conditions Required

All 5 conditions must be present to trigger the bug:

| Condition | Description |
|-----------|-------------|
| 1. Generic struct | Struct with phantom `Tag` parameter (e.g., `Property.View`) |
| 2. Protocol hierarchy | `Collection.Protocol` refines `Sequence.Protocol` |
| 3. Base refinement | One extension uses `Clearable` which refines `Protocol` |
| 4. Different Tag constraints | `Tag == Collection.Count` vs `Tag == Collection.Remove` |
| 5. Same member name | Both extensions declare member named `all` |

**Note**: Bug is NOT specific to `~Escapable` - also occurs with `~Copyable` only structs.

## Verified Test Results

| Test | Description | Result |
|------|-------------|--------|
| Same Base protocol | Both use `Collection.Protocol` | ✅ Compiles |
| Different Base protocols | `Protocol` vs `Clearable` (refines Protocol) | ❌ **Bug** |
| Different member names | `all` vs `total` | ✅ Compiles |
| Nested View types | Separate `View` per Tag namespace | ✅ **Workaround** |

## Workaround

See `Sources/CollectionLib/Workaround.swift` for the working pattern.

### Option 1: Rename members (loses API consistency)

```swift
extension Property.View where Tag == Collection.Count, ... {
    public var count: Int { ... }  // Renamed from 'all'
}

extension Property.View where Tag == Collection.Remove, ... {
    public mutating func removeAll() { ... }  // Renamed from 'all'
}
```

### Option 2: Nested View types (preserves naming) ✅ Recommended

Instead of one generic `Property.View` with Tag discrimination, use separate View types nested inside each Tag namespace:

```swift
extension Collection.Count {
    struct View<Base: Collection.Protocol & ~Copyable>: ~Copyable, ~Escapable {
        var all: Int { ... }  // ✅ No conflict - different type
    }
}

extension Collection.Remove {
    struct View<Base: Collection.Clearable & ~Copyable>: ~Copyable, ~Escapable {
        func all() { ... }  // ✅ No conflict - different type
    }
}
```

**Trade-off**: Requires defining a View struct per Tag instead of reusing one generic `Property.View`, but preserves the desired API naming (`.count.all`, `.remove.all()`).

## Impact

This blocks the design pattern of using phantom `Tag` types to namespace extensions on a generic `View` type. The pattern is used in:

- [swift-property-primitives](https://github.com/swift-institute/swift-primitives) - Fluent API via `Property.View` extensions
- Any library using phantom types for extension namespacing

The recommended workaround (nested View types) preserves API naming but requires more boilerplate.
