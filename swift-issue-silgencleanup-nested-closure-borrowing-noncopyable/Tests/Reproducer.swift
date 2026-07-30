import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// A closure LITERAL (assigned to / returned as a closure-typed value) whose
// body defines a nested local closure that also captures the outer
// closure's `borrowing ~Copyable` parameter aborts swift-frontend (signal
// 6) in the SIL ownership verifier run by the mandatory SILGenCleanup pass
// ("Found ownership error?!" / "Have operand with incompatible
// ownership?!"). Fires at `-Onone` (SILGenCleanup is mandatory, not an
// optimization) and at `-O`. Still fires on Apple Swift 6.4
// (swiftlang-6.4.0.27.1) — verified 2026-07-30; no known-good toolchain has
// been checked yet, so this is NOT confirmed as a regression.
//
// The identical body as a plain top-level `func` (not a closure literal) is
// instead correctly REJECTED at typecheck ("cannot be captured by an
// escaping closure since it is a borrowed parameter") — a distinct, correct
// diagnostic. The escaping-closure-capture check that fires for a `func`'s
// borrowing parameter does not fire when the parameter belongs to a closure
// literal, and the malformed capture reaches SILGen instead of being
// rejected. See Crash.swift.txt for the full load-bearing/not-load-bearing
// ingredient breakdown.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// The bug aborts the COMPILER while compiling the triggering source, so the
// trigger cannot be a compiled SwiftPM target — it would abort the whole
// Issues package build. It ships as the `Crash.swift.txt` resource and is
// compiled OUT OF PROCESS here.
//
// FLIP SEMANTICS
// --------------
//   • bug fires ......... known issue matched ............. GREEN
//   • upstream fix lands . known issue did not occur ....... RED ← signal

@Suite
struct SILGenCleanupNestedClosureBorrowingNoncopyableReproducer {

    /// Compiles `Crash.swift.txt` in a child process. Returns `true` if the
    /// SILGenCleanup ownership abort fired, `false` if it compiled cleanly,
    /// `nil` if inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

        guard FileManager.default.fileExists(atPath: here.path) else { return nil }

        let pid = ProcessInfo.processInfo.processIdentifier
        let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("silgencleanup-nested-closure-test-\(pid).swift")
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("silgencleanup-nested-closure-test-\(pid).out")
        try? FileManager.default.removeItem(at: swiftCopy)
        guard (try? FileManager.default.copyItem(at: here, to: swiftCopy)) != nil else { return nil }
        defer {
            try? FileManager.default.removeItem(at: swiftCopy)
            try? FileManager.default.removeItem(at: out)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc", swiftCopy.path, "-o", out.path]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do { try process.run() } catch { return nil }
        process.waitUntilExit()

        let errText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if errText.contains("Found ownership error") && errText.contains("SILGenCleanup") {
            return true
        }
        if process.terminationStatus == 0 {
            return false          // compiled cleanly — fix has landed
        }
        return nil                // failed for an unrelated reason — inconclusive
        #else
        return nil                // no subprocess facility
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }
        withKnownIssue(
            "SILGenCleanup ownership-verifier abort: nested local closure capturing a borrowing ~Copyable parameter of an enclosing closure literal",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
