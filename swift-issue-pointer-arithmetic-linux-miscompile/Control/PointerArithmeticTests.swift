import Testing

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

    /// Fires the bug on Linux release-mode toolchains (Swift 6.3 stable,
    /// Swift 6.4-dev nightly) when the enclosing target has
    /// `.enableExperimentalFeature("Lifetimes")` in its swiftSettings.
    /// Without that setting, this same test passes.
    ///
    /// `unsafe` markers are present so this same file compiles under
    /// `.strictMemorySafety()` too (they are no-ops without it). This
    /// keeps the file byte-identical across the With* / Control targets
    /// that test individual swiftSettings for uniqueness.
    @Test
    func reducedRepro() {
        var values: [Int] = [0, 10, 20, 30, 40]
        unsafe values.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            let advanced = unsafe base + Vec(4)
            let backed = unsafe advanced - Vec(2)
            #expect(unsafe backed.pointee == 20)
        }
    }
}
