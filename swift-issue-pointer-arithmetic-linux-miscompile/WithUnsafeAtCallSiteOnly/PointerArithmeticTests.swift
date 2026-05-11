import Testing

// Q1b: `unsafe` keyword ONLY at the @Test call sites; absent from the
// operator bodies. If this target fails on Linux release while
// WithUnsafeInOperatorBodyOnly passes, the trigger is the call-site
// `unsafe`. If both fail, either position is sufficient.

struct Vec {
    let raw: Int
    init(_ raw: Int) { self.raw = raw }
}

func + (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    lhs.advanced(by: rhs.raw)
}

func - (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    lhs.advanced(by: -rhs.raw)
}

@Suite
struct PointerArithmeticReduced {
    @Test
    func reducedRepro_unsafeAtCallSiteOnly() {
        var values: [Int] = [0, 10, 20, 30, 40]
        unsafe values.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            let advanced = unsafe base + Vec(4)
            let backed = unsafe advanced - Vec(2)
            #expect(unsafe backed.pointee == 20)
        }
    }
}
