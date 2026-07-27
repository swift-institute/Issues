# Bug: Xcode gutter diamond fails for deeply nested Swift Testing suites

## Description

Clicking the Xcode gutter diamond to run an individual `@Test` function reports "0 tests" when the test is nested 4+ levels deep (3+ enclosing `@Suite` types). Running all tests via Cmd+U or `swift test` discovers and runs the test correctly.

## Environment

- **Swift version**: Apple Swift version 6.2.4 (swiftlang-6.2.4.1.4 clang-1700.6.4.2)
- **Target**: arm64-apple-macosx26.0
- **Xcode**: 26.0 beta

## Minimal Reproduction (7 lines)

```swift
import Testing

@Suite struct A {
    @Suite struct B {
        @Suite struct C {
            @Test func bug() { #expect(Bool(true)) }
        }
    }
}
```

## To Reproduce

```bash
git clone https://github.com/coenttb/swift-issue-testing-xcode-nested-suite-filter
cd swift-issue-testing-xcode-nested-suite-filter
swift test  # Both tests pass
```

Then open in Xcode:
1. Click the gutter diamond next to `bug()` — reports "0 tests"
2. Click the gutter diamond next to `works()` — runs correctly
3. Press Cmd+U — both tests run and pass

## Conditions Required

| # | Condition | Description |
|---|-----------|-------------|
| 1 | Nesting depth 4+ | `@Test` function inside 3+ enclosing `@Suite` types |

**Not required**: backticks, raw identifiers, cross-module extensions, `@testable import`, library targets.

## Verified Test Results

| Test | Depth | `swift test` | Cmd+U | Gutter Diamond |
|------|-------|--------------|-------|----------------|
| `X.Y.works()` | 3 | ✅ | ✅ | ✅ |
| `A.B.C.bug()` | 4 | ✅ | ✅ | ❌ 0 tests |

**Key finding**: The boundary is exactly depth 3 → 4. Removing any one nesting level makes the gutter diamond work.

## Workaround

Flatten the suite hierarchy to 3 or fewer levels.

## Related Issues

- [#524](https://github.com/swiftlang/swift-testing/issues/524) — Private suite type fails to run in Xcode (same symptom pattern; tracked as rdar://131227159)
- [sourcekit-lsp#1218](https://github.com/swiftlang/sourcekit-lsp/issues/1218) — Tests in extensions not nested correctly in `textDocument/tests` (tracked as rdar://127491907)

## Filed Issues

- Apple Feedback: FB22115546
- GitHub: [swiftlang/swift-testing#1604](https://github.com/swiftlang/swift-testing/issues/1604)

## Impact

This blocks test organization patterns that mirror code structure with deeply nested type hierarchies.
