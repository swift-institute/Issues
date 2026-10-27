import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// swiftlang/swift#93525 — an assertions-enabled `swift-frontend` aborts in
// `RequirementMachine::verify` ("Term verification failed", GenericSignatureQueries.cpp:880)
// while lowering an initializer that pins a `~Copyable` generic parameter to a nested
// generic conditional conformer of a protocol with primary associated types.
// `Crash.swift.txt` aborts the compiler, so it is compiled OUT OF PROCESS ([ISSUE-029]).
//
// Only assertions builds run this verification. Release toolchains (Xcode, swift.org
// releases) compile the file, so their clean result says nothing about a fix. `when:` is
// therefore "this swiftc is an assertions build" (`swiftc --version` prints
// `Build config: +assertions`): green while the abort fires there, red once an
// assertions toolchain compiles the file. On a release toolchain the body runs
// unguarded and passes.

@Suite
struct SILGenTermVerificationPrimaryAssociatedTypeReproducer {

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

    /// `true` when the `swiftc` on PATH is an assertions build.
    static func assertionsToolchain() -> Bool {
        swiftc(["--version"])?.output.contains("+assertions") ?? false
    }

    /// `true` when swiftc aborted with the term-verification failure, `false` when it
    /// compiled the file, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let crashSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            let swiftCopy = temporary.appendingPathComponent("term-verification-test-\(pid).swift")
            let object = temporary.appendingPathComponent("term-verification-test-\(pid).o")
            try? FileManager.default.removeItem(at: swiftCopy)
            guard (try? FileManager.default.copyItem(at: crashSource, to: swiftCopy)) != nil else {
                return nil
            }
            defer {
                try? FileManager.default.removeItem(at: swiftCopy)
                try? FileManager.default.removeItem(at: object)
            }

            guard let result = swiftc(["-c", "-parse-as-library", swiftCopy.path, "-o", object.path])
            else { return nil }

            if result.output.contains("Term verification failed") { return true }
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
            "swiftlang/swift#93525 — RequirementMachine term verification fails in SILGen (assertions builds)",
            { #expect(fired == false) },
            when: { Self.assertionsToolchain() }
        )
    }
}
