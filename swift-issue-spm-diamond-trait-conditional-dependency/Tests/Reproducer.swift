import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation

@Suite
struct SPMDiamondTraitConditionalDependencyReproducer {
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
    func `A package reached with and without a trait resolves its trait-gated dependency`() throws {
        let fired = try Self.bugFires()
        withKnownIssue("SwiftPM: a diamond with and without a trait leaves the trait-gated dependency unresolved") {
            #expect(!fired)
        }
    }
}
#endif
