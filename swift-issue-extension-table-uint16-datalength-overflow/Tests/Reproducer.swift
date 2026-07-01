import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// swiftlang/swift#NNNN — `ExtensionTableInfo::EmitKeyDataLength` serializes the
// per-base-name extension-table `dataLength` as a **uint16_t**, which overflows
// when a nominal type is extended enough times (Serialization.cpp:239).
//
// TWO MANIFESTATIONS OF ONE DEFECT
// --------------------------------
//   • ASSERTS toolchain (any DEVELOPMENT-SNAPSHOT / +assertions build):
//       `swiftc -emit-module` ABORTS (signal 6) —
//       Assertion failed: (dataLength == static_cast<uint16_t>(dataLength)),
//       function EmitKeyDataLength, file Serialization.cpp, line 239.
//   • RELEASE toolchain (NoAsserts, e.g. Xcode default):
//       `swiftc -emit-module` SUCCEEDS but writes a TRUNCATED extension table;
//       a downstream consumer then fails to resolve articles —
//       "type '`Burgerlijk Wetboek`.`2`' has no member 'Artikel 999'".
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// The asserts path aborts the COMPILER while emitting this module, so the trigger
// cannot be a compiled SwiftPM target. It lives as the `Crash.swift.txt` resource
// and is compiled OUT OF PROCESS here. The probe checks BOTH manifestations so it
// fires on release toolchains (truncation) as well as asserts toolchains (crash).
//
// FLIP SEMANTICS
// --------------
// `withKnownIssue` is GREEN while the bug fires and flips RED the moment an upstream
// fix lands (`-emit-module` succeeds AND the consumer resolves every article). The
// red flip on the weekly nightly cron is the fix-detection signal.

@Suite
struct ExtensionTableUInt16DataLengthOverflowReproducer {

    private static let moduleName = "Burgerlijk_Wetboek_Boek_2"

    /// Emits the reproducer as a module, then (on toolchains where emit does not
    /// abort) type-checks a consumer that references a high-numbered article.
    /// Returns `true` if the bug fires (crash OR truncation), `false` if fixed,
    /// `nil` if no compiler could be reached / an unrelated failure occurred.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let crashSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")
        guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

        let pid = ProcessInfo.processInfo.processIdentifier
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let staged = tmp.appendingPathComponent("exttable-repro-\(pid).swift")
        let moduleDir = tmp.appendingPathComponent("exttable-mod-\(pid)", isDirectory: true)
        try? FileManager.default.removeItem(at: staged)
        try? FileManager.default.removeItem(at: moduleDir)
        try? FileManager.default.createDirectory(at: moduleDir, withIntermediateDirectories: true)
        // swiftc keys off the file extension; stage the `.txt` resource as `.swift`.
        guard (try? FileManager.default.copyItem(at: crashSource, to: staged)) != nil else { return nil }
        defer {
            try? FileManager.default.removeItem(at: staged)
            try? FileManager.default.removeItem(at: moduleDir)
        }

        // Step 1 — emit the module.
        let modulePath = moduleDir.appendingPathComponent("\(moduleName).swiftmodule").path
        let (emitStatus, emitErr) = run([
            "swiftc", "-emit-module", "-module-name", moduleName,
            "-o", modulePath, staged.path,
        ])
        guard let emitStatus else { return nil }   // could not launch a compiler

        // Asserts path: the emit aborts in EmitKeyDataLength.
        if emitErr.contains("EmitKeyDataLength")
            || emitErr.contains("dataLength == static_cast<uint16_t>") {
            return true
        }
        // Emit failed for some OTHER reason — inconclusive.
        if emitStatus != 0 { return nil }

        // Step 2 — release path: emit succeeded; a truncated table drops articles.
        let consumer = tmp.appendingPathComponent("exttable-consumer-\(pid).swift")
        let consumerSource = """
        import \(moduleName)
        let _ = `Burgerlijk Wetboek`.`2`.`Artikel 999`.self
        """
        try? consumerSource.write(to: consumer, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: consumer) }
        let (consumerStatus, consumerErr) = run([
            "swiftc", "-typecheck", "-I", moduleDir.path, consumer.path,
        ])
        guard let consumerStatus else { return nil }
        if consumerErr.contains("has no member 'Artikel")
            || consumerErr.contains("is not a member type") {
            return true                     // silent truncation — the bug, on a release toolchain
        }
        if consumerStatus == 0 { return false }   // resolves cleanly — the fix has landed
        return nil                          // unrelated failure — inconclusive
        #else
        return nil                          // no subprocess facility
        #endif
    }

    #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    /// Runs a command via `/usr/bin/env`, returning (exitStatus, stderr) or (nil, "")
    /// if the process could not be launched.
    private static func run(_ args: [String]) -> (Int32?, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        do { try process.run() } catch { return (nil, "") }
        process.waitUntilExit()
        let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }
    #endif

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }   // no compiler / inconclusive → skip
        // `when: { true }`, NOT `when: { fired }`. The `guard` above already skips every
        // platform where presence can't be determined (Windows, unreachable compiler), so by
        // here the bug is expected until upstream fixes it. With `true`, known-issue matching
        // stays active when `fired` becomes `false` (fix landed) → the body passes → Swift
        // Testing records "Known issue was not recorded" → the leg flips RED. `when: { fired }`
        // would disable matching on a fix, leave the body passing, and stay GREEN forever —
        // defeating the weekly cron's fix-detection (empirically verified).
        withKnownIssue(
            "swiftlang/swift#NNNN — ExtensionTableInfo uint16 dataLength overflow (Serialization.cpp:239): crash on asserts, silent truncation on release",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
