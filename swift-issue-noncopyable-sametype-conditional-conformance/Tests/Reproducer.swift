import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// A generic type witnessing a protocol through `extension Gen: P where
// A == Pool` — a same-type conditional conformance whose subject carries a
// `~Copyable` generic argument — compiles cleanly and crashes at RUNTIME
// (SIGSEGV) when the conforming value's protocol-constrained container is
// used. Still fires on 6.3.3-RELEASE and Apple Swift 6.4 (verified
// 2026-07-30: the compiled reproducer dies on signal 11 on both).
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// The crash is a RUNTIME signal: an in-process reproduction would kill the
// test runner before any known issue could be recorded (the same reason the
// tagged-noncopyable-atomic entry documents). The probe compiles AND runs
// `Sources/reproducer.swift` out of process, so the signal lands in a child.

@Suite
struct NoncopyableSametypeConditionalConformanceReproducer {

    /// Compiles and runs `Sources/reproducer.swift` in child processes.
    /// Returns `true` if the compiled reproducer was killed by a signal,
    /// `false` if it ran to completion, `nil` if inconclusive (compile
    /// failure = broken instrument, not the bug).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/reproducer.swift")
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let pid = ProcessInfo.processInfo.processIdentifier
        let binary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sametype-conformance-test-\(pid)")
        defer { try? FileManager.default.removeItem(at: binary) }

        func run(_ executable: String, _ arguments: [String]) -> (signaled: Bool, status: Int32)? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardError = Pipe()
            process.standardOutput = Pipe()
            do { try process.run() } catch { return nil }
            process.waitUntilExit()
            return (process.terminationReason == .uncaughtSignal, process.terminationStatus)
        }

        guard let compile = run("/usr/bin/env", ["swiftc", source.path, "-o", binary.path]),
              !compile.signaled, compile.status == 0 else { return nil }
        guard let execution = run(binary.path, []) else { return nil }
        return execution.signaled
        #else
        return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }
        withKnownIssue(
            "~Copyable same-type conditional conformance: compiled reproducer crashes at runtime (SIGSEGV)",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
