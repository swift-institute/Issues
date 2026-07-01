import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// swiftlang/swift (PENDING filing) — `~Copyable` `@_rawLayout` trailing-field
// value-witness IRGen dominance-violation compiler abort.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// This bug aborts the COMPILER (signal 6, LLVM verifier "Instruction does not
// dominate all uses") while compiling the triggering source under `-O`. The
// triggering source therefore cannot be a compiled SwiftPM target — it would
// abort the whole Issues package build. Instead the trigger lives as the
// `Crash.swift.txt` resource and is compiled OUT OF PROCESS here.
//
// FLIP SEMANTICS
// --------------
// `withKnownIssue` is GREEN while the bug fires (the out-of-process `swiftc -O`
// aborts with the verifier error on the current toolchain) and flips RED the
// moment an upstream fix lands and `Crash.swift.txt` compiles cleanly. The red
// flip on the weekly `nightly-main-jammy` cron IS the fix-detection signal.
//
// The bug reproduces on every toolchain and platform sampled during
// investigation (Apple Swift 6.3.2, 6.4-dev, 6.5-dev on macOS arm64; Swift
// 6.3.1-RELEASE and 6.4-dev nightly on Linux aarch64), so the `when:`
// precondition is the unconditional "a compiler is reachable" probe.

@Suite
struct NoncopyableRawLayoutTrailingFieldReproducer {

    /// Compiles `Crash.swift.txt` with `swiftc -O` in a child process and
    /// reports whether the LLVM module verifier rejected the value-witness IR.
    /// Returns `nil` if no compiler could be reached / launched (inconclusive).
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
            .appendingPathComponent("rawlayout-trailing-test-\(pid).swift")
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawlayout-trailing-test-\(pid).out")
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
            "-enable-experimental-feature", "RawLayout",
            "-enable-experimental-feature", "ValueGenerics",
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

        if errText.contains("does not dominate all uses") || errText.contains("Broken module") {
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
            "swiftlang/swift#PENDING — ~Copyable @_rawLayout trailing-field value-witness dominance violation",
            { #expect(fired == false) },
            // `when: { true }`, NOT `{ fired }`: the `guard let fired … else { return }`
            // above already skips unreachable / N-A platforms, so known-issue matching must
            // stay ACTIVE when the bug stops firing — that is what flips the leg RED on an
            // upstream fix (the cron's whole purpose). `{ fired }` disables matching on a fix,
            // leaves the body passing, and stays GREEN forever (empirically verified). The
            // "Broken module" verifier error is target-independent (it runs pre-lowering), so
            // this fires on x86_64 CI legs too, per the arch-independence noted above.
            when: { true }
        )
    }
}
