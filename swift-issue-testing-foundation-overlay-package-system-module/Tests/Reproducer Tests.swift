import Testing

#if canImport(Darwin)
    import Foundation

    @Suite
    struct TestingFoundationOverlayPackageSystemModuleReproducer {
        /// True when the bug fires, false when the package builds. Any other outcome (the
        /// fixture failed for another reason) is recorded as an issue, never read as fixed.
        static func bugFires() throws -> Bool? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "swift",
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Sources/Reproducer/main.swift").path,
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            // Exit 1 alone is not a verdict: a script that fails to compile exits 1 too.
            switch process.terminationStatus {
            case 1 where output.contains("bug fired"): return true
            case 0: return false
            default:
                Issue.record("the reproducer ended without a verdict (exit \(process.terminationStatus)):\n\(output.suffix(3000))")
                return nil
            }
        }

        @Test
        func `A test target importing Foundation builds beside a package module named System`()
            throws
        {
            guard let fired = try Self.bugFires() else { Issue.record("no verdict: the reproduction could not be staged, built or run here (a reason recorded above, if any, says why)"); return }
            withKnownIssue(
                "Swift: the _Testing_Foundation overlay resolves a package module named System"
            ) {
                #expect(!fired)
            }
        }
    }
#endif
