import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// CopyPropagation shortens the begin_borrow/end_borrow scope of a borrowed
// `~Copyable` parameter so that it ends before the apply that consumes its
// projected `~Copyable` field; the SIL ownership verifier then aborts
// swift-frontend (signal 6) with "Found outside of lifetime use?!". Fires at
// `-O` only; `-Onone` is clean. Verified fixed on the 6.4 line (Apple Swift
// 6.4, 6.4.x-snapshot-2026-07-23, main-snapshot-2026-07-11 all compile the
// trigger cleanly at -O); still fires on 6.3.3-RELEASE.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// The bug aborts the COMPILER while compiling the triggering source, so the
// trigger cannot be a compiled SwiftPM target — it would abort the whole
// Issues package build on every affected toolchain at release configuration.
// It ships as the `Crash.swift.txt` resource and is compiled OUT OF PROCESS
// here with `swiftc -O`.
//
// FLIP SEMANTICS (version-gated, like the silcloner entry)
// --------------------------------------------------------
//   • 6.3-line leg, bug fires .... known issue matched .......... GREEN
//   • 6.3-line leg, fix lands .... known issue did not occur .... RED ← the signal
//   • 6.4+ leg (fix present) ..... body runs unguarded, passes .. GREEN
//   • 6.4+ leg, regression ....... body fails ................... RED

@Suite
struct FileSystemStreamingWriteOwnershipReproducer {

    /// Compiles `Crash.swift.txt` with `swiftc -O` in a child process and
    /// reports whether the CopyPropagation ownership abort fired. Returns
    /// `nil` if no compiler could be reached or it failed for an unrelated
    /// reason (inconclusive).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

        guard FileManager.default.fileExists(atPath: here.path) else { return nil }

        let pid = ProcessInfo.processInfo.processIdentifier
        let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fs-streaming-write-ownership-test-\(pid).swift")
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fs-streaming-write-ownership-test-\(pid).out")
        try? FileManager.default.removeItem(at: swiftCopy)
        guard (try? FileManager.default.copyItem(at: here, to: swiftCopy)) != nil else { return nil }
        defer {
            try? FileManager.default.removeItem(at: swiftCopy)
            try? FileManager.default.removeItem(at: out)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swiftc", "-O",
            swiftCopy.path,
            "-o", out.path,
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

        if errText.contains("Found outside of lifetime use")
            && errText.contains("CopyPropagation") {
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

    /// Version gate for `when:` — true when the PROBED `swiftc` (the one
    /// `bugFires()` launches via `env`) is on a pre-6.4 line, i.e. a line the
    /// fix has not reached. Gating on configuration, not on the probe's
    /// outcome, is what lets the red flip fire when a backport lands.
    static func probedCompilerIsPre64() -> Bool {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc", "--version"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        let text = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard let range = text.range(of: "version ") else { return false }
        let tail = text[range.upperBound...]
        let components = tail
            .prefix(while: { $0.isNumber || $0 == "." })
            .split(separator: ".")
            .compactMap { Int($0) }
        guard components.count >= 2 else { return false }
        return (components[0], components[1]) < (6, 4)
        #else
        return false
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else {
            // No reachable compiler, or an unrelated failure — nothing to assert.
            return
        }

        // Body passed as positional (NOT trailing) — with `when:` after,
        // Swift's forward-scan rule binds a trailing closure to `matching:`
        // instead of `body`, producing a contextual-type mismatch.
        withKnownIssue(
            "CopyPropagation shortens a borrowed ~Copyable parameter's scope before the apply consuming its projected field (fixed on the 6.4 line)",
            { #expect(fired == false) },
            when: { Self.probedCompilerIsPre64() }
        )
    }
}
