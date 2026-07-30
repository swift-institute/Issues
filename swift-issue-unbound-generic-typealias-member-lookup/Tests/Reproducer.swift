import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// REJECTS-VALID: member-type lookup does not look through an unbound
// generic typealias, though it does through (row 1) the unbound generic
// NOMINAL type the alias refers to, (row 2) the BOUND form of the same
// alias, and (row 5, added per swift-institute/.github#122 W8) a
// NON-generic alias to an unbound generic NOMINAL. Only the unbound
// GENERIC alias base (row 4) is rejected — sharpening the claim from
// "alias bases break" to "GENERIC alias bases break". Reproduces
// identically on every toolchain checked (6.3.3, Apple 6.4
// swiftlang-6.4.0.27.1, 6.4.x nightly, main nightly) — NOT a regression,
// no known-good toolchain. Upstream filing remains principal-gated
// (swift-institute/Issues#58).
//
// WHY A `swiftc -typecheck` PROBE, NOT exit(0)/exit(1) CODEGEN
// --------------------------------------------------------------
// The bug is a type-check rejection, not a codegen fault, and
// `reproducer.swift` fails to compile BY DESIGN (row 4) — a live SwiftPM
// target would break the whole Issues package build. The trigger ships as
// a loose file, `Tests/../Sources/reproducer.swift`, compiled OUT OF
// PROCESS with `swiftc -typecheck -swift-version 6`.
//
// FLIP SEMANTICS
// --------------
//   • bug fires ......... known issue matched ............. GREEN
//   • upstream fix lands . known issue did not occur ....... RED ← signal

@Suite
struct UnboundGenericTypealiasMemberLookupReproducer {

    /// Typechecks `Sources/reproducer.swift` in a child process. Returns
    /// `true` if the row-4 rejection fired, `false` if it typechecked
    /// cleanly, `nil` if inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/reproducer.swift")
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc", "-typecheck", "-swift-version", "6", source.path]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let errText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if errText.contains("is not a member type of type") && errText.contains("Alias") {
            return true
        }
        if process.terminationStatus == 0 { return false }
        return nil
        #else
        return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }
        withKnownIssue(
            "Member-type lookup does not look through an unbound GENERIC typealias ('Alias.Member' rejected; 'Carrier.Member', 'Alias<Int>.Member', and 'Bare.Member' all accepted)",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
