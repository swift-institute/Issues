import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// swift-institute/Issues#21, upstream swiftlang/swift#86202 (open) — an existential
// of a protocol named through a typealias of its parent (`any A.P`, `typealias A = E`)
// trips `isActuallyCanonicalOrNull() && "Forming a CanType out of a non-canonical type!"`.
//
// `repro.swift` aborts the compiler, so it is compiled OUT OF PROCESS.
// The assertion is compiled out of release toolchains, which accept the file, so a
// toolchain without `+assertions` is inconclusive. On 6.4 assertions builds it fires in
// IRGen's debug-info mangling (needs `-g`); on main snapshots, in the SIL verifier
// (with or without `-g`). Wherever the probe is conclusive the bug fires, so `when:`
// is `true`.

@Suite
struct ProtocolTypealiasParentNoncanonicalReproducer {

    static func swiftc(_ arguments: [String]) -> (status: Int32, output: String)? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc"] + arguments
            let output = Pipe()
            process.standardError = output
            process.standardOutput = output
            resolveEnv(process)
            do { try process.run() } catch { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        #else
            return nil
        #endif
    }

    /// `true` when the compiler asserted, `false` when it compiled the file, `nil` when
    /// inconclusive (any other outcome).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("repro.swift")

            guard FileManager.default.fileExists(atPath: source.path) else { return nil }

            guard let result = swiftc(["-g", "-c", source.path, "-o", FileManager.default.temporaryDirectory.appendingPathComponent("issue-21-\(ProcessInfo.processInfo.processIdentifier).o").path]) else { return nil }

            if result.output.contains("Forming a CanType out of a non-canonical type!") { return true }
            if result.status == 0 { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { Issue.record("no verdict: the reproduction could not be staged, built or run here (a reason recorded above, if any, says why)"); return }

        withKnownIssue(
            "swiftlang/swift#86202 (Issues#21; still fires with -g on main after swiftlang/swift#93790) — `A.P` with `typealias A = E` forms a non-canonical CanType",
            { #expect(fired == false) },
            when: { Self.hasAssertions }
        )
    }

    /// The abort is an assertion: only a toolchain built with assertions shows it.
    static var hasAssertions: Bool {
        swiftc(["--version"])?.output.contains("+assertions") ?? false
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
