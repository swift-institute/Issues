import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// Swift 6.3.2 in-cohort ICE ("failed to produce diagnostic for expression")
// at `var body: some P<I, Output, Error>` declarations in files importing a
// module exposing a parameterized typealias (`typealias X = Generic<Concrete>`)
// or a Base-constrained extension on a generic type. Fixed on 6.4-dev.
//
// The retained single-file shape (`Crash.swift.txt`) captures the identified
// trigger surface but has NEVER reproduced the ICE standalone — on every
// tested toolchain (6.3.2, 6.3.3, Apple 6.4, main snapshots) it compiles
// clean. The in-cohort case is the canonical reference (README). This test is
// therefore a CANARY, not a withKnownIssue reproducer: it asserts the
// standalone shape stays clean, and a red here means the standalone shape has
// STARTED reproducing — which would finally make the entry upstream-fileable
// with a self-contained reducer.

@Suite
struct ParameterizedTypealiasOpaqueReturnICECanary {

    /// Compiles `Crash.swift.txt` in a child process. Returns `true` if the
    /// ICE signature appeared, `false` if it compiled cleanly, `nil` if no
    /// compiler could be reached or it failed for an unrelated reason.
    static func iceFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

        guard FileManager.default.fileExists(atPath: here.path) else { return nil }

        let pid = ProcessInfo.processInfo.processIdentifier
        let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parameterized-typealias-ice-test-\(pid).swift")
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parameterized-typealias-ice-test-\(pid).out")
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

        if errText.contains("failed to produce diagnostic") { return true }
        if process.terminationStatus == 0 { return false }
        return nil
        #else
        return nil
        #endif
    }

    @Test
    func `standalone shape stays clean`() {
        guard let fired = Self.iceFires() else {
            // No reachable compiler, or an unrelated failure — nothing to assert.
            return
        }
        // Red here = the standalone shape started reproducing the in-cohort
        // ICE, i.e. a self-contained reducer now exists. Capture the
        // toolchain and update the README before touching this expectation.
        #expect(fired == false)
    }
}
