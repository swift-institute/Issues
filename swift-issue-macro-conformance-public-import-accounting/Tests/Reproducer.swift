import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation

@Suite
struct MacroConformancePublicImportAccountingReproducer {
    /// Runs the standalone reproducer; `true` when `public import` is reported unused.
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
    func `A public conformance added by a macro counts toward public import use`() throws {
        let fired = try Self.bugFires()
        withKnownIssue("Swift: macro-generated public declarations do not count toward public import accounting") {
            #expect(!fired)
        }
    }
}
#endif
