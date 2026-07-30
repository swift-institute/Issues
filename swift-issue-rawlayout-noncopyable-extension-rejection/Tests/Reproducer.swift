import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// REJECTS-VALID: a `@_rawLayout` storage type generic over a `~Copyable`
// element, extended in a module that imports the element-generic `Storage`
// namespace and `Marker` protocol (whose `associatedtype Element: ~Copyable`
// is load-bearing), is incorrectly rejected with "type 'Element' does not
// conform to protocol 'Copyable'". Still fires on Apple Swift 6.4 (verified
// 2026-07-30 via the two-invocation bare-swiftc probe). Module B fails
// compilation by design, so the reduced sources are NOT live SwiftPM
// targets; the probe drives them out of process, and `withKnownIssue` flips
// RED the moment module B typechecks cleanly.

@Suite
struct RawlayoutNoncopyableExtensionRejectionReproducer {

    /// Builds module A (always compiles — positive control), then typechecks
    /// module B against it with the RawLayout feature. Returns `true` if the
    /// Copyable rejection fired, `false` if module B typechecked cleanly,
    /// `nil` if inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources")
        let namespaceDir = sourcesRoot.appendingPathComponent("ReproducerStorageNamespace")
        let inlineDir = sourcesRoot.appendingPathComponent("ReproducerStorageInline")

        func swiftFiles(in directory: URL) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { $0.hasSuffix(".swift") }
                .sorted()
                .map { directory.appendingPathComponent($0).path }
        }
        let namespaceSources = swiftFiles(in: namespaceDir)
        let inlineSources = swiftFiles(in: inlineDir)
        guard !namespaceSources.isEmpty, !inlineSources.isEmpty else { return nil }

        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawlayout-rejection-test-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: work)
        guard (try? FileManager.default.createDirectory(
            at: work, withIntermediateDirectories: true
        )) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: work) }

        func run(_ arguments: [String]) -> (status: Int32, stderr: String)? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc"] + arguments
            process.currentDirectoryURL = work
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = Pipe()
            do { try process.run() } catch { return nil }
            let text = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            process.waitUntilExit()
            return (process.terminationStatus, text)
        }

        guard let moduleA = run(
            ["-wmo", "-parse-as-library", "-emit-module",
             "-emit-module-path", "StorageNamespaceLib.swiftmodule",
             "-module-name", "StorageNamespaceLib"] + namespaceSources
        ), moduleA.status == 0 else { return nil }

        guard let moduleB = run(
            ["-wmo", "-parse-as-library", "-typecheck",
             "-enable-experimental-feature", "RawLayout", "-I", "."] + inlineSources
        ) else { return nil }

        if moduleB.stderr.contains("does not conform to protocol 'Copyable'") { return true }
        if moduleB.status == 0 { return false }
        return nil
        #else
        return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }
        withKnownIssue(
            "@_rawLayout ~Copyable extension rejects-valid: 'Element' does not conform to protocol 'Copyable'",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
