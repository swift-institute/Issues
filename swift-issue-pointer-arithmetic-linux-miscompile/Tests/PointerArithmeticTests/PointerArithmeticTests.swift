import Testing
@testable import PointerArithmeticLinuxMiscompile

@Suite
struct PointerArithmeticReduced {

    /// Fires the bug on Linux release-mode toolchains (Swift 6.3 stable,
    /// Swift 6.4-dev nightly). Passes on macOS, Windows, and Linux debug.
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
