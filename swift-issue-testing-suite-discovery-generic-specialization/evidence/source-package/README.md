# Swift Testing: @Suite/@Test silently not discovered in generic specialization extensions

## Swift Issue

Filed as [swiftlang/swift-testing#1508](https://github.com/swiftlang/swift-testing/issues/1508)

## Description

`@Test` compiles without error inside `extension Container<Int>`, but the test is silently invisible to `swift test list` and never executes. No warning or diagnostic is emitted.

## Environment

- **Swift version**: Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
- **Target**: arm64-apple-macosx26.0

## Minimal Reproduction (6 lines)

```swift
import Testing

struct Container<T> {}

extension Container<Int> {
    @Suite struct Tests {
        @Test("never discovered")
        func bug() { #expect(Bool(true)) }
    }
}
```

## To Reproduce

```bash
git clone https://github.com/coenttb/swift-issue-testing-suite-discovery-generic-specialization
cd swift-issue-testing-suite-discovery-generic-specialization
swift test list
```

**Expected**: `Container<Swift.Int>/Tests/bug()` appears in output
**Actual**: Only `Control/Tests/control()` appears

## Conditions Required

All 3 conditions must be present:

| # | Condition | Description |
|---|-----------|-------------|
| 1 | Generic struct | e.g., `struct Container<T> {}` |
| 2 | Concrete specialization extension | e.g., `extension Container<Int>` |
| 3 | @Test macro | Applied to method inside that extension |

## Verified Test Results

| Configuration | Result |
|---------------|--------|
| `extension Container<Int> { @Suite ... }` | ❌ Compiles, NOT discovered |
| `extension Control { @Suite ... }` (non-generic) | ✅ Discovered, passes |

## Impact

This prevents organizing test suites as extensions of the types they test when those types are generic.

Workaround: use a non-generic struct or enum as the test suite container.
