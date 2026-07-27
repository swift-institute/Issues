/// @Suite/@Test Not Discovered in Generic Type Specialization Extensions
///
/// The @Test macro compiles without error inside `extension Container<Int>`,
/// but the test is silently invisible to `swift test list`.
///
/// Conditions required (ALL must be present):
/// 1. Generic struct
/// 2. Extension with concrete type arguments
/// 3. @Test macro on method in that extension

import Testing

struct Container<T> {}

// ❌ BUG: Compiles, but NOT discovered by `swift test list`
extension Container<Int> {
    @Suite struct Tests {
        @Test("test in generic specialization")
        func bug() { #expect(Bool(true)) }
    }
}

// ✅ WORKS: Non-generic struct IS discovered
struct Control {}
extension Control {
    @Suite struct Tests {
        @Test("test in non-generic struct")
        func control() { #expect(Bool(true)) }
    }
}
