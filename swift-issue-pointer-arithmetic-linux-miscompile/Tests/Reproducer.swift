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

// Release-mode + Linux probe.
//
// Detection uses `assert`'s autoclosure: in `-O` (release) the autoclosure
// body is never executed, so the side-effect closure cannot flip `debug`;
// in `-Onone` (debug) the autoclosure runs and `debug` becomes true.
//
// The probe is the gate for `withKnownIssue` below — on Linux release the
// bug fires and `withKnownIssue` catches it (green); on every other
// platform/configuration the bug doesn't fire, the precondition returns
// false, and the wrapped block runs unguarded (also green).
private func isLinuxRelease() -> Bool {
    #if os(Linux)
    var debug = false
    assert({ debug = true; return true }())
    return !debug
    #else
    return false
    #endif
}

@Suite
struct PointerArithmeticReproducer {

    /// swiftlang/swift#77558 — Linux release-mode pointer arithmetic
    /// miscompile. A `.pointee` load after a user-authored `+`/`-`
    /// operator wrapping `.advanced(by:)` returns the value at the
    /// wrong address. Fires on Swift 6.3 stable + 6.4-dev nightly
    /// Linux release; does not fire on macOS / Windows / Linux debug.
    ///
    /// `withKnownIssue` flip semantics: green while the bug fires on
    /// Linux release (current state); red the moment upstream lands a
    /// fix and the bug stops firing. The red flip IS the fix-detection
    /// signal — see `.github/workflows/nightly.yml`.
    @Test
    func reproducer() {
        // Body passed as positional (NOT trailing) — with `when:` after,
        // Swift's forward-scan rule binds a trailing closure to `matching:`
        // instead of `body`, producing a contextual-type mismatch.
        withKnownIssue(
            "swiftlang/swift#77558 — Linux release-mode pointer arithmetic miscompile",
            {
                var values: [Int] = [0, 10, 20, 30, 40]
                unsafe values.withUnsafeMutableBufferPointer { buf in
                    let base = buf.baseAddress!
                    let advanced = unsafe base + Vec(4)
                    let backed = unsafe advanced - Vec(2)
                    #expect(unsafe backed.pointee == 20)
                }
            },
            when: { isLinuxRelease() }
        )
    }
}
