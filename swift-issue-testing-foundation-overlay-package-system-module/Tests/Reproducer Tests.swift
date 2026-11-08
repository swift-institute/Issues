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
            switch process.terminationStatus {
            case 1: return true
            case 0: return false
            default:
                Issue.record("the reproducer ended without a verdict (exit \(process.terminationStatus)):\n\(String(decoding: data, as: UTF8.self).suffix(3000))")
                return nil
            }
        }

        @Test
        func `A test target importing Foundation builds beside a package module named System`()
            throws
        {
            guard let fired = try Self.bugFires() else { return }
            withKnownIssue(
                "Swift: the _Testing_Foundation overlay resolves a package module named System"
            ) {
                #expect(!fired)
            }
        }
    }
#endif
