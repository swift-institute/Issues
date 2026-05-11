import Testing

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

    /// Control without `unsafe` keyword markers. Differs from the With* /
    /// Control sibling targets only by the absence of the `unsafe`
    /// expression marker. If this target passes on Linux release while
    /// the others fail, the `unsafe` keyword itself is the load-bearing
    /// trigger — not any of the swiftSettings.
    @Test
    func reducedRepro() {
        var values: [Int] = [0, 10, 20, 30, 40]
        values.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            let advanced = base + Vec(4)
            let backed = advanced - Vec(2)
            #expect(backed.pointee == 20)
        }
    }
}
