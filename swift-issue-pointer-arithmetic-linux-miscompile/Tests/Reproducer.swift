import Testing

private struct Vec {
    let raw: Int
    init(_ raw: Int) { self.raw = raw }
}

private func + (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    unsafe lhs.advanced(by: rhs.raw)
}

private func - (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    unsafe lhs.advanced(by: -rhs.raw)
}

// Release-mode probe.
//
// In `-O` the autoclosure passed to `assert` never runs, so `debug`
// stays false; in `-Onone` it runs and `debug` becomes true. Windows is
// left out until its CI leg shows whether the bug fires there.
private func isRelease() -> Bool {
    #if os(Windows)
    return false
    #else
    var debug = false
    assert({ debug = true; return true }())
    return !debug
    #endif
}

@Suite
struct PointerArithmeticReproducer {

    /// swiftlang/swift#77558 — release-mode pointer arithmetic
    /// miscompile. A `.pointee` load after a user-authored `+`/`-`
    /// operator wrapping `.advanced(by:)` returns the value at the
    /// wrong address. Not fixed on Swift 6.4 (swiftlang-6.4.0.34.1):
    /// fires under `swift test -c release` on macOS 27 arm64 and on
    /// `swift:6.4` Linux aarch64 and x86_64; debug is correct.
    ///
    /// The load runs in plain code, outside any `withKnownIssue` or
    /// `#expect` closure, so the test harness cannot perturb the
    /// codegen under test. Only the comparison is wrapped. Green while
    /// the bug fires; "Known issue was not recorded" (red) once a
    /// toolchain fixes it — that flip is the fix-detection signal.
    @Test
    func reproducer() {
        var values: [Int] = [0, 10, 20, 30, 40]
        let loaded = values.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            let advanced = unsafe base + Vec(4)
            let backed = unsafe advanced - Vec(2)
            return unsafe backed.pointee
        }
        // Body passed as positional (NOT trailing) — with `when:` after,
        // Swift's forward-scan rule binds a trailing closure to `matching:`
        // instead of `body`, producing a contextual-type mismatch.
        withKnownIssue(
            "swiftlang/swift#77558 — release-mode pointer arithmetic miscompile",
            { #expect(loaded == 20) },
            when: { isRelease() }
        )
    }
}
