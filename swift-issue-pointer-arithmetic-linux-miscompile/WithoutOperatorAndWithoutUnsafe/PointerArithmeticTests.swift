import Testing

// Q2 negative control: no user-authored operator AND no `unsafe`
// markers. Should pass on all platforms — sanity check that bare
// stdlib pointer arithmetic is correct.

@Suite
struct PointerArithmeticReduced {
    @Test
    func reducedRepro_withoutOperatorAndWithoutUnsafe() {
        var values: [Int] = [0, 10, 20, 30, 40]
        values.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            let advanced = base.advanced(by: 4)
            let backed = advanced.advanced(by: -2)
            #expect(backed.pointee == 20)
        }
    }
}
