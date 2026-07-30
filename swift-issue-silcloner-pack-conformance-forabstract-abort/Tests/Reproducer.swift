import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// swiftlang/swift#90275 — SILCloner projects a pack element lane onto a pack
// archetype while remapping a substitution map inside an active pack
// expansion; `ProtocolConformanceRef::forAbstract` rejects the resulting
// PackElementType subject and swift-frontend aborts (signal 6) with
// `Abort: function forAbstract at ASTContext.cpp:5924`.
//
// Fixed upstream by swiftlang/swift#89916 ([SILCloner] Preserve expansion
// level when cloning pack conformances), merged to `release/6.4.x`
// (merge 5462b4ed24fafb0eabe28e32e6f06ae802f01f31). NOT on the 6.3 line.
// Institute tracking: swift-institute/Issues#58.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// The bug aborts the COMPILER while compiling the triggering source, so the
// trigger cannot be a compiled SwiftPM target — it would abort the whole
// Issues package build on every affected toolchain. It ships as the
// `Crash.swift.txt` resource and is compiled OUT OF PROCESS here.
//
// FLIP SEMANTICS
// --------------
// The bug fires on the 6.3 line (verified: 6.3.3-RELEASE) and is fixed on
// every tested 6.4+ toolchain (Apple Swift 6.4, 6.4.x-snapshot-2026-07-23,
// main-snapshot-2026-07-11 — the snapshots are assertions-enabled builds, so
// the abort would still be live were the defect present). `when:` is therefore
// VERSION-GATED to probed-compiler < 6.4, mirroring the
// inliner-escaping-mark-dependence entry's precedent in the inverse direction:
//
//   • 6.3-line leg, bug fires .... known issue matched .......... GREEN
//   • 6.3-line leg, fix lands .... known issue did not occur .... RED ← the signal
//   • 6.4+ leg (fix present) ..... body runs unguarded, passes .. GREEN
//   • 6.4+ leg, regression ....... body fails ................... RED
//
// The red flip on a 6.3-line toolchain is the detection signal that the
// #89916 fix (or a backport) has reached that line — the exact event
// swift-institute/Issues#58's blocked Swift 6.3 release gates wait on.

@Suite
struct SILClonerPackConformanceForAbstractAbortReproducer {

    /// Compiles `Crash.swift.txt` with `swiftc -emit-sil` in a child process
    /// and reports whether the forAbstract abort fired. Returns `nil` if no
    /// compiler could be reached or it failed for an unrelated reason
    /// (inconclusive).
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
            .appendingPathComponent("silcloner-pack-conformance-test-\(pid).swift")
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("silcloner-pack-conformance-test-\(pid).sil")
        try? FileManager.default.removeItem(at: swiftCopy)
        guard (try? FileManager.default.copyItem(at: here, to: swiftCopy)) != nil else { return nil }
        defer {
            try? FileManager.default.removeItem(at: swiftCopy)
            try? FileManager.default.removeItem(at: out)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swiftc", "-emit-sil", "-swift-version", "6",
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

        if errText.contains("forAbstract")
            && errText.contains("Abstract conformance with bad subject type") {
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
    /// #89916 fix has not reached. Gating on configuration, not on the probe's
    /// outcome, is what lets the red flip fire when a backport lands
    /// (`when: { fired }` would disable matching on a fix and stay green
    /// forever — see the functionsignatureopts entry's note).
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
        // First "N.M" pair after "version " — e.g. "Apple Swift version 6.3.3"
        // or "Swift version 6.4-dev".
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
            "swiftlang/swift#90275 — SILCloner pack-conformance substitution aborts in ProtocolConformanceRef::forAbstract",
            { #expect(fired == false) },
            when: { Self.probedCompilerIsPre64() }
        )
    }
}
