import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// A body member and a redundant-with-default `where Element: Copyable`
// extension member of an extension-nested type mangle to the SAME symbol,
// and `swiftc -emit-object` fails with "multiple definitions of symbol".
// Still fires on 6.3.3-RELEASE and Apple Swift 6.4 (verified 2026-07-30).
//
// The reduced sources are the loose files at ../Sources/*.swift (reproducer,
// overload-resolution control, ~Escapable analogue, production shape, two
// verified workarounds). They are NOT SwiftPM targets — the reproducer fails
// compilation by design — so the probe compiles it out of process, and
// `withKnownIssue` stays green while the collision fires, flipping RED the
// moment an upstream fix lets it compile.

@Suite
struct NoncopyableExtensionMemberManglingCollisionReproducer {

    /// Compiles `Sources/reproducer.swift` with `swiftc -emit-object` in a
    /// child process. Returns `true` if the mangling collision fired,
    /// `false` if it compiled cleanly, `nil` if inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/reproducer.swift")
            guard FileManager.default.fileExists(atPath: source.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let objectFile = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mangling-collision-test-\(pid).o")
            defer { try? FileManager.default.removeItem(at: objectFile) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc", "-emit-object", source.path, "-o", objectFile.path]
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = Pipe()
            resolveEnv(process)
            do { try process.run() } catch { return nil }
            let errText =
                String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            process.waitUntilExit()

            if errText.contains("multiple definitions of symbol") { return true }
            if process.terminationStatus == 0 { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { Issue.record("no verdict: the reproduction could not be staged, built or run here (a reason recorded above, if any, says why)"); return }
        withKnownIssue(
            "~Copyable extension-member mangling collision: body member and redundant-with-default extension member mangle identically",
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
