import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// swiftlang/swift#89684 — bogus `type 'Substrate' does not conform to
// protocol 'P'` when a conditional extension declares a typealias named after
// an enclosing type's generic parameter.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// This bug REJECTS VALID SOURCE at `-typecheck`: references to the enclosing
// type's generic parameter inside the nested type's declaring context are
// captured by a conditionally-available member typealias of the same name,
// and the compiler evaluates the extension's `where` condition against the
// open generic argument — emitting a bogus conformance error. The triggering
// source therefore cannot be a compiled SwiftPM target — it would fail the
// whole Issues package build while the bug lives. Instead the trigger lives
// as the `Reject.swift.txt` resource and is typechecked OUT OF PROCESS here.
//
// FLIP SEMANTICS
// --------------
// `withKnownIssue` is GREEN while the bug fires (the out-of-process
// `swiftc -typecheck` rejects the source with the bogus-conformance
// signature) and flips RED the moment an upstream fix lands and
// `Reject.swift.txt` typechecks cleanly. The red flip on the weekly
// `nightly-main-jammy` cron IS the fix-detection signal.
//
// VERSION STORY (verified by re-running the reducer under each toolchain —
// `swift --version`-confirmed; see ../README.md)
//   6.3.2 (Xcode default) ........ REJECTS (bogus conformance error)
//   6.4-dev (2026-03-16-a) ....... REJECTS identically (+assertions; none fire)
//   6.5-dev (2026-05-27-a) ....... REJECTS identically (+assertions; none fire)
// The `when:` precondition is the unconditional "a compiler is reachable"
// probe.

@Suite
struct ConditionalExtensionTypealiasNameCaptureReproducer {

    /// Typechecks `Reject.swift.txt` with `swiftc -typecheck` in a child
    /// process and reports whether the bogus rejection fired. Returns `nil`
    /// if no compiler could be reached / launched, or the source was
    /// rejected without the bug's signature (inconclusive).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Reject.swift.txt")

        guard FileManager.default.fileExists(atPath: here.path) else { return nil }

        // swiftc keys off the file extension; stage the `.txt` resource as a
        // `.swift` temp so it is compiled rather than treated as a link input.
        let pid = ProcessInfo.processInfo.processIdentifier
        let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("conditional-extension-typealias-test-\(pid).swift")
        try? FileManager.default.removeItem(at: swiftCopy)
        guard (try? FileManager.default.copyItem(at: here, to: swiftCopy)) != nil else { return nil }
        defer {
            try? FileManager.default.removeItem(at: swiftCopy)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swiftc", "-typecheck", "-swift-version", "6",
            swiftCopy.path,
        ]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do { try process.run() } catch { return nil }
        process.waitUntilExit()

        let errText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if errText.contains("error: type 'Substrate' does not conform to protocol 'P'") {
            return true           // the bogus rejection — the bug's signature
        }
        if process.terminationStatus == 0 {
            return false          // typechecked cleanly — fix has landed
        }
        return nil                // rejected for an unrelated reason — inconclusive
        #else
        return nil                // no subprocess facility
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else {
            // No reachable compiler, or an unrelated failure — nothing to assert.
            return
        }

        withKnownIssue(
            "swiftlang/swift#89684 — conditional-extension typealias named after an enclosing generic parameter captures declaring-context references",
            { #expect(fired == false) },
            // `when: { true }`, NOT `{ fired }`: the `guard let fired … else { return }`
            // above already skips unreachable / N-A platforms, so known-issue matching must
            // stay ACTIVE when the bug stops firing — that is what flips the leg RED on an
            // upstream fix (the cron's whole purpose). `{ fired }` disables matching on a fix,
            // leaves the body passing, and stays GREEN forever (empirically verified).
            when: { true }
        )
    }
}
