import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation

@Suite
struct SPMImpliedTraitConditionalDependencyReproducer {
    /// Runs the standalone reproducer; `true` when SwiftPM fails to resolve the fixture graph.
    static func bugFires() throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Reproducer/main.swift").path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 1
    }

    @Test
    func `An implied trait's conditional dependency trait request resolves`() throws {
        let fired = try Self.bugFires()
        withKnownIssue("SwiftPM: implied trait does not activate conditional dependency trait requests") {
            #expect(!fired)
        }
    }
}
#endif
