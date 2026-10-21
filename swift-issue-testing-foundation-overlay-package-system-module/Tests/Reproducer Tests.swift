import Testing

#if canImport(Darwin)
    import Foundation

    @Suite
    struct TestingFoundationOverlayPackageSystemModuleReproducer {
        static func bugFires() throws -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "swift",
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Sources/Reproducer/main.swift").path,
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 1
        }

        @Test
        func `A test target importing Foundation builds beside a package module named System`()
            throws
        {
            let fired = try Self.bugFires()
            withKnownIssue(
                "Swift: the _Testing_Foundation overlay resolves a package module named System"
            ) {
                #expect(!fired)
            }
        }
    }
#endif
