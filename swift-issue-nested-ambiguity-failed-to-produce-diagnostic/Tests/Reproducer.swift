import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// The type checker emits "failed to produce diagnostic for expression" instead of
// an ambiguity error when an ambiguous call is the argument of an ambiguous
// overloaded call. `Crash.swift.txt` is ill-formed on purpose, so it is
// type-checked OUT OF PROCESS ([ISSUE-029]).
//
// Fires on every toolchain tested (6.3.3 through 6.5-dev), so `when: { true }`:
// the test stays green while the fallback error appears and flips red once a
// toolchain reports a proper diagnostic.

@Suite
struct NestedAmbiguityFailedToProduceDiagnosticReproducer {

    /// `true` when swiftc emitted the fallback error, `false` when it reported a
    /// proper ambiguity, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let crashSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

        guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

        let pid = ProcessInfo.processInfo.processIdentifier
        let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nested-ambiguity-diagnostic-test-\(pid).swift")
        try? FileManager.default.removeItem(at: swiftCopy)
        guard (try? FileManager.default.copyItem(at: crashSource, to: swiftCopy)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: swiftCopy) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc", "-typecheck", "-swift-version", "6", swiftCopy.path]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do { try process.run() } catch { return nil }
        let errText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        process.waitUntilExit()

        if errText.contains("failed to produce diagnostic") { return true }
        if errText.contains("ambiguous use of") { return false }
        return nil
        #else
        return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "Type checker: failed to produce diagnostic for an ambiguous call nested in an ambiguous overloaded call",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
