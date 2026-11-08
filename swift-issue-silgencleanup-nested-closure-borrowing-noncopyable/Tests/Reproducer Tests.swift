import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
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
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let here = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: here.path) else {
                Issue.record("Sources/Reproducer/Crash.swift.txt is missing")
                return nil
            }

            let pid = ProcessInfo.processInfo.processIdentifier
            let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("silgencleanup-nested-closure-test-\(pid).swift")
            let out = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("silgencleanup-nested-closure-test-\(pid).out")
            try? FileManager.default.removeItem(at: swiftCopy)
            guard (try? FileManager.default.copyItem(at: here, to: swiftCopy)) != nil else {
                Issue.record("could not stage the reproduction")
                return nil
            }
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

            resolveEnv(process)
            do { try process.run() } catch {
                Issue.record("could not launch swiftc: \(error)")
                return nil
            }
            process.waitUntilExit()

            let errText =
                String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

            // Release toolchains abort in SILGenCleanup; an assertions build of 6.4.x asserts
            // on the same capture earlier, in SILGenFunction::emitCaptures.
            if (errText.contains("Found ownership error") && errText.contains("SILGenCleanup"))
                || errText.contains("no address for captured var!")
            {
                return true
            }
            if process.terminationStatus == 0 || errText.contains("cannot be captured by an escaping closure since it is a borrowed parameter") {
                return false  // compiled, or diagnosed the capture (main): no crash
            }
            Issue.record("swiftc failed without the record's markers (exit \(process.terminationStatus)):\n\(errText.suffix(3000))")
            return nil
        #else
            return nil  // no subprocess facility
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }
        withKnownIssue(
            "SILGenCleanup ownership-verifier abort: nested local closure capturing a borrowing ~Copyable parameter of an enclosing closure literal",
            { #expect(fired == false) },
            when: { Self.beforeFix }
        )
    }

    /// Fixed on main before 6.5; every 6.4 toolchain still has it. From 6.5 on, the bug
    /// firing again is a regression and fails the test.
    static var beforeFix: Bool {
        #if compiler(>=6.5)
            return false
        #else
            return true
        #endif
    }
}

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    /// `/usr/bin/env` does not exist on Windows. There, a process set up to run a tool
    /// through it runs the tool found on Path instead; elsewhere nothing changes.
    func resolveEnv(_ process: Process) {
        #if os(Windows)
            guard process.executableURL?.path.hasSuffix("/usr/bin/env") == true,
                let arguments = process.arguments, let name = arguments.first
            else { return }
            let path = ProcessInfo.processInfo.environment["Path"] ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
            for directory in path.split(separator: ";") {
                let candidate = URL(fileURLWithPath: String(directory))
                    .appendingPathComponent(name.hasSuffix(".exe") ? name : "\(name).exe")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    process.executableURL = candidate
                    process.arguments = Array(arguments.dropFirst())
                    return
                }
            }
        #endif
    }

#endif
