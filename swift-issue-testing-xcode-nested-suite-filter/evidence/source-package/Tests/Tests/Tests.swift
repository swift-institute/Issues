/// Xcode Gutter Diamond Fails at Suite Nesting Depth 4+
///
/// The Xcode gutter diamond reports "0 tests" for `@Test` functions nested
/// 4+ levels deep. `swift test` and Cmd+U both discover and run the test.
///
/// Condition required:
/// 1. Test function nested 4+ levels (3+ enclosing `@Suite` types)
///
/// Note: Backticks, raw identifiers, cross-module extensions, and `@testable`
/// are NOT required. Plain inline nesting reproduces this.

import Testing

// MARK: - Minimal Reproduction: depth 4 — BUG: 0 tests via Xcode gutter diamond

@Suite struct A {
    @Suite struct B {
        @Suite struct C {
            @Test func bug() { #expect(Bool(true)) }
        }
    }
}

// MARK: - Verified Working Case: depth 3 — works via Xcode gutter diamond

@Suite struct X {
    @Suite struct Y {
        @Test func works() { #expect(Bool(true)) }
    }
}
