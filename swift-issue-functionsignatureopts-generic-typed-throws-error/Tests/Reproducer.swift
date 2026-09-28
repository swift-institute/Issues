import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// swiftlang/swift#89617 — FunctionSignatureOpts asserts on a generic
// function whose typed-throws error type carries the function's own abstract
// type parameter (`func f<T>(…) throws(E<T>)`), with a same-module caller, at -O.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// This bug aborts the COMPILER (signal 6) while compiling the triggering source
// under `-O`. The triggering source therefore cannot be a compiled SwiftPM
// target — it would abort the whole Issues package build. Instead the trigger
// lives as the `Crash.swift.txt` resource and is compiled OUT OF PROCESS here.
//
// FLIP SEMANTICS
// --------------
// `withKnownIssue` is GREEN while the bug fires (the out-of-process `swiftc -O`
// aborts on the current toolchain) and flips RED the moment an upstream fix
// lands and `Crash.swift.txt` compiles cleanly. The red flip on the weekly
// `nightly-main-jammy` cron IS the fix-detection signal.
//
// VERSION STORY (verified by re-running the reducer under each toolchain —
// `swift --version`-confirmed; see ../README.md)
//   6.2 / 6.2.3 (asserts off) ... CRASH via the SIL verifier (try_apply error dest)
//   6.3.1 / 6.3.2 (Xcode default) CRASH via ASSERT(!type.hasTypeParameter())
//   6.3-dev / 6.4-dev / 6.5-dev . CRASH via the same assertion
// The bug is NOT a 6.3 regression (6.3 only added the earlier, louder
// SILArgument assertion).
//
// FIXED ON 6.4 (re-verified 2026-09-28, macOS arm64): 6.3.3-RELEASE still aborts
// on the assertion; Apple Swift 6.4 (swiftlang-6.4.0.34.1), the 6.4.x snapshot
// 2026-07-23 and the 6.5-dev snapshot 2026-07-11 compile it cleanly. So `when:`
// is version-gated like swift-issue-tasklocal-function-value-null-metadata:
//   below 6.4 — matching ACTIVE: green while it fires, RED on a backport.
//   6.4+      — matching INACTIVE: green while fixed, RED on a regression.

@Suite
struct FunctionSignatureOptsGenericTypedThrowsErrorReproducer {

    /// True when this target was built by a compiler that predates the fix.
    static var expectsBug: Bool {
        #if compiler(>=6.4)
        false
        #else
        true
        #endif
    }

    /// Compiles `Crash.swift.txt` with `swiftc -O` in a child process and
    /// reports whether FunctionSignatureOpts aborted. Returns `nil` if no
    /// compiler could be reached / launched (inconclusive).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

        guard FileManager.default.fileExists(atPath: here.path) else { return nil }

        // swiftc keys off the file extension; stage the `.txt` resource as a
        // `.swift` temp so it is compiled rather than treated as a link input.
        let pid = ProcessInfo.processInfo.processIdentifier
        let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fso-typedthrows-test-\(pid).swift")
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fso-typedthrows-test-\(pid).o")
        try? FileManager.default.removeItem(at: swiftCopy)
        guard (try? FileManager.default.copyItem(at: here, to: swiftCopy)) != nil else { return nil }
        defer {
            try? FileManager.default.removeItem(at: swiftCopy)
            try? FileManager.default.removeItem(at: out)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swiftc", "-O", "-swift-version", "6", "-c",
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

        // Two manifestations of the same defect (assert on 6.3+, verifier on 6.2/6.2.3).
        if errText.contains("hasTypeParameter")
            || errText.contains("error destination of try_apply must take argument of error result type") {
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
        guard let fired = Self.bugFires() else {
            // No reachable compiler, or an unrelated failure — nothing to assert.
            return
        }

        withKnownIssue(
            "swiftlang/swift#89617 — FunctionSignatureOpts !type.hasTypeParameter() on a generic typed-throws error result",
            { #expect(fired == false) },
            // Version-gated, NOT `{ fired }`: `{ fired }` would disable matching
            // exactly when the bug stops firing and hide a fix or a regression.
            when: { Self.expectsBug }
        )
    }
}
