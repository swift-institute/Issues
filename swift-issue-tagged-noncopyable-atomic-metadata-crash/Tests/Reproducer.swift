import Testing
import Synchronization
import Tagged_Primitives
import Ordinal_Primitives
import Cardinal_Primitives

private enum SimpleTag: Sendable {}

/// `withKnownIssue` flip semantics for SIGSEGV bugs.
///
/// On Swift 6.3.x (current shipping Xcode): the `.advance(within:)`
/// call SIGSEGVs at runtime metadata lookup of
/// `Atomic<Tagged_Primitives.Tagged<…>>`. The test process is killed
/// by the kernel (signal 11); SwiftTesting never gets a chance to
/// register the known issue, so the test leg reports "test process
/// exited with unexpected signal code 11". The CI per-issue matrix's
/// macOS-6.3.x leg captures this — that signal-11 IS the bug-fired
/// signal. `withKnownIssue` is documentation of intent for human
/// readers in that case.
///
/// On Swift 6.5-dev (snapshot 2026-03-16-a or newer, verified
/// 2026-05-23): the demangling-time conformance lookup succeeds and
/// the call returns cleanly. The `when:` predicate returns `false`,
/// `withKnownIssue` is bypassed, and the `#expect` runs as a normal
/// assertion — the test goes green via the regular path.
///
/// If the bug returns on Swift 6.5+ for some other reason, the
/// in-process call SIGSEGVs and the test leg reports signal 11
/// outside any `withKnownIssue` wrapper — that's the regression
/// detection signal.
@Suite
struct TaggedNoncopyableAtomicReproducer {

    @Test
    func reproducer() {
        // Body passed as positional (NOT trailing) — with `when:` after,
        // Swift's forward-scan rule binds a trailing closure to the wrong
        // parameter slot. Same pattern used by
        // swift-issue-pointer-arithmetic-linux-miscompile/Tests/Reproducer.swift.
        withKnownIssue(
            "swiftlang/swift — Tagged + Atomic + ~Copyable cross-module conditional-conformance runtime metadata SIGSEGV (pending filing; fixed on 6.5-dev)",
            {
                let cursor = Atomic<Tagged<SimpleTag, Ordinal>>(.zero)
                let count: Tagged<SimpleTag, Cardinal> = try! .init(2)
                let result = cursor.advance(within: count)
                #expect(result.underlying.rawValue == 0)
            },
            when: { isShippingBuggyToolchain() }
        )
    }
}

/// Compile-time gate: returns `true` on toolchains whose Swift compiler
/// version is older than 6.5. The bug fires on Apple Swift 6.3.x (the
/// current shipping Xcode); is fixed on the Swift 6.5-dev nightly
/// snapshot stream (verified 2026-03-16-a / 2026-05-07-a / 2026-05-12-a).
private func isShippingBuggyToolchain() -> Bool {
    #if compiler(<6.5)
    return true
    #else
    return false
    #endif
}
