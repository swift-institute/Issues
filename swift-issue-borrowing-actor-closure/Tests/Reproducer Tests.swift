import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

@Suite
struct BorrowingActorClosureReproducer {
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let here = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let crashSource = here.appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: crashSource.path) else {
                return nil
            }

            let identifier = ProcessInfo.processInfo.processIdentifier
            let stagedSource = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("borrowing-actor-closure-test-\(identifier).swift")
            let objectFile = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("borrowing-actor-closure-test-\(identifier).o")

            defer {
                try? FileManager.default.removeItem(at: stagedSource)
                try? FileManager.default.removeItem(at: objectFile)
            }

            guard
                (try? FileManager.default.copyItem(
                    at: crashSource,
                    to: stagedSource
                )) != nil
            else {
                return nil
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "swiftc", "-parse-as-library", "-swift-version", "6", "-c",
                stagedSource.path,
                "-o", objectFile.path,
            ]

            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = Pipe()

            do {
                resolveEnv(process)
                try process.run()
            } catch {
                return nil
            }

            let output =
                String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            process.waitUntilExit()

            // Release toolchains crash in MoveOnlyTypeEliminator; an assertions toolchain's
            // SIL verifier rejects the same leaked `@moveOnly` value first.
            if output.contains("MoveOnlyTypeEliminator")
                || output.contains("Unhandled SIL Instruction")
                || (output.contains("SIL verification failed") && output.contains("$@moveOnly"))
            {
                return true
            }

            if process.terminationStatus == 0 {
                return false
            }

            Issue.record("swiftc failed without the record's markers (exit \(process.terminationStatus)):\n\(output.suffix(3000))")
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else {
            return
        }

        withKnownIssue(
            "swift-institute/Issues#3 — MoveOnlyTypeEliminator crash for a borrowed actor parameter captured by a closure",
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
