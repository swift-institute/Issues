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

    /// Fires the bug on Linux release-mode toolchains (Swift 6.3 stable,
    /// Swift 6.4-dev nightly) when the enclosing target has
    /// `.enableExperimentalFeature("Lifetimes")` in its swiftSettings.
    /// Without that setting, this same test passes.
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
