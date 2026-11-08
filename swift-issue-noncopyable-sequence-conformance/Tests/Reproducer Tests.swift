import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// Cross-module rejects-valid: a conditional conformance to a protocol with
// `associatedtype Element` leaks `Copyable` into the nested `~Copyable` type's
// `Heap<Element>` stored property. The loose sources at ../Sources/Core and
// ../Sources/Ring are NOT SwiftPM targets — Ring is rejected by design — so the
// probe emits both modules out of process.
//
// The rejection fires on the -emit-module path (what `swift build` runs) on
// 6.3.3-RELEASE and Apple Swift 6.4 (swiftlang-6.4.0.34.1); `-typecheck` alone
// is clean, which is why the 2026-07-30 re-verification read it as fixed.

@Suite
struct NoncopyableSequenceConformanceReproducer {

    /// `true` when Ring is rejected with the Copyable diagnostic, `false` when
    /// both modules emit cleanly, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let sources = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources")
            let fm = FileManager.default
            // The bug depends on file order: it fires only when
            // `Buffer.Ring+Sequence.swift` precedes `Buffer.Ring.swift`, the order
            // SwiftPM uses. A directory listing is unordered on Linux, so sort it.
            func swiftFiles(_ dir: String) -> [String] {
                let url = sources.appendingPathComponent(dir)
                return ((try? fm.contentsOfDirectory(atPath: url.path)) ?? [])
                    .filter { $0.hasSuffix(".swift") }
                    .sorted()
                    .map { url.appendingPathComponent($0).path }
            }
            let core = swiftFiles("Core")
            let ring = swiftFiles("Ring")
            guard !core.isEmpty, !ring.isEmpty else { return nil }

            let out = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(
                    "noncopyable-sequence-conformance-\(ProcessInfo.processInfo.processIdentifier)"
                )
            guard (try? fm.createDirectory(at: out, withIntermediateDirectories: true)) != nil
            else { return nil }
            defer { try? fm.removeItem(at: out) }

            func swiftc(_ arguments: [String]) -> (status: Int32, stderr: String)? {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments =
                    ["swiftc", "-swift-version", "6", "-parse-as-library"] + arguments
                let stderr = Pipe()
                process.standardError = stderr
                process.standardOutput = Pipe()
                resolveEnv(process)
                do { try process.run() } catch { return nil }
                let text =
                    String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                    ?? ""
                process.waitUntilExit()
                return (process.terminationStatus, text)
            }

            let coreModule = "swift_issue_noncopyable_sequence_conformance_Core"
            guard
                let built = swiftc(
                    [
                        "-emit-module", "-module-name", coreModule,
                        "-emit-module-path",
                        out.appendingPathComponent("\(coreModule).swiftmodule").path,
                    ] + core
                ), built.status == 0
            else { return nil }

            guard
                let result = swiftc(
                    [
                        "-emit-module", "-module-name", "Ring", "-I", out.path,
                        "-emit-module-path", out.appendingPathComponent("Ring.swiftmodule").path,
                    ] + ring
                )
            else { return nil }

            if result.stderr.contains("does not conform to protocol 'Copyable'") { return true }
            if result.status == 0 { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { Issue.record("no verdict: the reproduction could not be staged, built or run here (a reason recorded above, if any, says why)"); return }
        withKnownIssue(
            "associatedtype Element conformance leaks Copyable into a nested ~Copyable type (swiftlang/swift#87448)",
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
