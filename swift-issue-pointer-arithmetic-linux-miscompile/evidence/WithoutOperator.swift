import Testing

// Q2: No user-authored operator at all. Direct stdlib calls to
// `UnsafeMutablePointer.advanced(by:)`. Carries `unsafe` markers.
// If this target fails on Linux release, the bug fires WITHOUT user
// operator wrapping — the blast radius extends to any Swift 6.3
// codebase using `unsafe` markers on stdlib pointer arithmetic.
// If it passes, the user operator wrapping is part of the trigger
// and the report narrows accordingly.

@Suite
struct PointerArithmeticReduced {
    @Test
    func reducedRepro_withoutOperator() {
        var values: [Int] = [0, 10, 20, 30, 40]
        unsafe values.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            let advanced = unsafe base.advanced(by: 4)
            let backed = unsafe advanced.advanced(by: -2)
            #expect(unsafe backed.pointee == 20)
        }
    }
}
