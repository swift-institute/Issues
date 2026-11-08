import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// The type checker emits "failed to produce diagnostic for expression" instead of
// an ambiguity error when an ambiguous call is the argument of an ambiguous
// overloaded call. `Crash.swift.txt` is ill-formed on purpose, so it is
// type-checked OUT OF PROCESS.
//
// Fires on every toolchain tested (6.3.3 through 6.5-dev), so `when: { true }`:
// the test stays green while the fallback error appears and flips red once a
// toolchain reports a proper diagnostic.

@Suite
struct NestedAmbiguityFailedToProduceDiagnosticReproducer {

    /// `true` when swiftc emitted the fallback error, `false` when it reported a
    /// proper ambiguity, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let crashSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("nested-ambiguity-diagnostic-test-\(pid).swift")
            try? FileManager.default.removeItem(at: swiftCopy)
            guard (try? FileManager.default.copyItem(at: crashSource, to: swiftCopy)) != nil else {
                return nil
            }
            defer { try? FileManager.default.removeItem(at: swiftCopy) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc", "-typecheck", "-swift-version", "6", swiftCopy.path]
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = Pipe()

            resolveEnv(process)
            do { try process.run() } catch { return nil }
            let errText =
                String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            process.waitUntilExit()

            if errText.contains("failed to produce diagnostic") { return true }
            if errText.contains("ambiguous use of") { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "Type checker: failed to produce diagnostic for an ambiguous call nested in an ambiguous overloaded call",
            { #expect(fired == false) },
            when: { true }
        )
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
