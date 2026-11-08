import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// The move checker reports "copy of noncopyable typed value. This is a compiler
// bug." when a `consuming func` on a `~Copyable, ~Escapable` builder forwards its
// `let`-bound `~Copyable` stored property into a sibling type's `consuming`
// initializer. `Bug.swift.txt` does not compile on affected toolchains, so it is
// compiled OUT OF PROCESS.
//
// Fires on release toolchains (6.3.2, 6.4.2 on macOS arm64), so `when: { true }`:
// the test stays green while the diagnostic appears and flips red once the source
// compiles.

@Suite
struct MoveCheckerLetFieldConsumingSelfCopyReproducer {

    /// `true` when swiftc emitted the diagnostic, `false` when the source
    /// compiled, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let bugSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Bug.swift.txt")

            guard FileManager.default.fileExists(atPath: bugSource.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let stage = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("move-checker-let-field-test-\(pid)")
            try? FileManager.default.removeItem(at: stage)
            guard (try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)) != nil,
                (try? FileManager.default.copyItem(
                    at: bugSource,
                    to: stage.appendingPathComponent("main.swift")
                )) != nil
            else {
                try? FileManager.default.removeItem(at: stage)
                return nil
            }
            defer { try? FileManager.default.removeItem(at: stage) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "swiftc", "-c",
                "-swift-version", "6",
                "-package-name", "Repro",
                "-enable-experimental-feature", "Lifetimes",
                "-enable-experimental-feature", "LifetimeDependence",
                "-enable-experimental-feature", "SuppressedAssociatedTypes",
                "main.swift",
                "-o", "main.o",
            ]
            process.currentDirectoryURL = stage
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = FileHandle.nullDevice

            resolveEnv(process)
            do { try process.run() } catch { return nil }
            let errText =
                String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            process.waitUntilExit()

            if (errText.contains("copy of noncopyable typed value")
                || errText.contains("copy of non-'Copyable' typed value")) { return true }
            if process.terminationStatus == 0 { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "Move checker: copy of noncopyable typed value when consuming self forwards a let field",
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
