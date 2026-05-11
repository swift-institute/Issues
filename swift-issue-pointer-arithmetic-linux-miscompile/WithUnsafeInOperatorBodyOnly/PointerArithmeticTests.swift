import Testing

// Q1a: `unsafe` keyword ONLY inside the operator bodies; absent from
// the @Test call sites. If this target fails on Linux release while
// WithUnsafeAtCallSiteOnly passes, the trigger is the operator-body
// `unsafe`. If both fail, either position is sufficient.

struct Vec {
    let raw: Int
    init(_ raw: Int) { self.raw = raw }
}

func + (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    unsafe lhs.advanced(by: rhs.raw)
}

func - (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    unsafe lhs.advanced(by: -rhs.raw)
}

@Suite
struct PointerArithmeticReduced {
    @Test
    func reducedRepro_unsafeInOperatorBodyOnly() {
        var values: [Int] = [0, 10, 20, 30, 40]
        values.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            let advanced = base + Vec(4)
            let backed = advanced - Vec(2)
            #expect(backed.pointee == 20)
        }
    }
}
