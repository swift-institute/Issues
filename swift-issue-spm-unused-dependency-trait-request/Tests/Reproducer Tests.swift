import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation

    @Suite
    struct SPMUnusedDependencyTraitRequestReproducer {
        /// Runs the standalone reproducer; `true` when SwiftPM fails to resolve its graph.
        static func bugFires() throws -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "swift",
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("repro.swift").path,
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 1
        }

        @Test
        func `A trait requested on an unused dependency does not leave its guarded dependency unresolved`()
            throws
        {
            let fired = try Self.bugFires()
            withKnownIssue(
                "SwiftPM: a trait requested on a dependency no target uses requires the dependency it guards, which is never resolved"
            ) {
                #expect(!fired)
            }
        }
    }
#endif
