import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// swift-institute/Issues#21, upstream swiftlang/swift#86202 (open) — an existential
// of a protocol named through a typealias of its parent (`any A.P`, `typealias A = E`)
// trips `isActuallyCanonicalOrNull() && "Forming a CanType out of a non-canonical type!"`.
//
// `repro.swift` aborts the compiler, so it is compiled OUT OF PROCESS ([ISSUE-029]).
// The assertion is compiled out of release toolchains, which accept the file, so a
// toolchain without `+assertions` is inconclusive. On 6.4 assertions builds it fires in
// IRGen's debug-info mangling (needs `-g`); on main snapshots, in the SIL verifier
// (with or without `-g`). Wherever the probe is conclusive the bug fires, so `when:`
// is `true`.

@Suite
struct ProtocolTypealiasParentNoncanonicalReproducer {

    static func swiftc(_ arguments: [String]) -> (status: Int32, output: String)? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc"] + arguments
            let output = Pipe()
            process.standardError = output
            process.standardOutput = output
            do { try process.run() } catch { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        #else
            return nil
        #endif
    }

    /// `true` when the compiler asserted, `false` when it compiled the file, `nil` when
    /// inconclusive (no assertions in this toolchain, or any other outcome).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("repro.swift")

            guard FileManager.default.fileExists(atPath: source.path),
                let version = swiftc(["--version"]),
                version.output.contains("+assertions")
            else { return nil }

            guard let result = swiftc(["-g", "-c", source.path, "-o", "/dev/null"]) else { return nil }

            if result.output.contains("Forming a CanType out of a non-canonical type!") { return true }
            if result.status == 0 { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "swiftlang/swift#86202 (Issues#21; fixed on main by swiftlang/swift#93790) — `A.P` with `typealias A = E` forms a non-canonical CanType",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
