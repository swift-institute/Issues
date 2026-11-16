import Testing

#if canImport(Glibc) || canImport(Darwin)
    import Foundation

    @Suite
    struct SPMManifestCacheEnvironmentRecompileReproducer {
        /// Runs the standalone reproducer; `true` when SwiftPM compiles the manifest again
        /// after only an unrelated environment variable changed.
        static func bugFires() throws -> Bool? {
            let script = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("repro.swift")
            let program = FileManager.default.temporaryDirectory
                .appendingPathComponent("issue-300-\(ProcessInfo.processInfo.processIdentifier)")
            // REASON: best-effort cleanup of a scratch file.
            // swiftlint:disable:next no_try_optional
            defer { try? FileManager.default.removeItem(at: program) }
            let build = try launch(URL(fileURLWithPath: "/usr/bin/env"), ["swiftc", script.path, "-o", program.path])
            guard build.status == 0 else {
                Issue.record("the reproducer didn't compile (exit \(build.status)):\n\(build.output.suffix(3000))")
                return nil
            }
            let result = try launch(program, [])
            switch result.status {
            case 1 where result.output.contains("compiled again although only X changed"): return true
            case 0 where result.output.contains("the manifest was reused"): return false
            default:
                Issue.record("the reproducer ended without a verdict (exit \(result.status)):\n\(result.output.suffix(3000))")
                return nil
            }
        }

        // REASON: Process.run() throws an untyped Foundation error.
        // swiftlint:disable:next typed_throws_required
        static func launch(_ executable: URL, _ arguments: [String]) throws -> (status: Int32, output: String) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }

        @Test
        func `A manifest is not compiled again when only an environment variable it never reads changes`()
            throws
        {
            guard let fired = try Self.bugFires() else { Issue.record("no verdict: the reproduction could not be staged, built or run here (a reason recorded above, if any, says why)"); return }
            withKnownIssue(
                "SwiftPM: the manifest cache key holds the whole environment, so any changed variable compiles the manifest again"
            ) {
                #expect(!fired)
            }
        }
    }
#endif

// Not applicable on Windows: the reproduction drives SwiftPM through /bin/sh and posix_spawn,
// and the cache key behaves the same there, so the Linux and macOS legs carry the evidence.
