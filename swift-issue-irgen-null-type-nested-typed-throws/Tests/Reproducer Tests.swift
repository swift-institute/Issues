import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// IRGen asserts 'Cannot dereference a null Type!' at -O on a nested typed-throws generic (6.4 branch, assertions builds; fixed on main).
// The record is the issue named in ../ISSUE; the reproduction is
// Sources/Reproducer/Repro.swift.txt, run out of process. A failure that carries none
// of the record's markers is recorded, never skipped: the bug changed.

@Suite
struct Reproducer {

    /// Fixed on main before 6.5; every 6.4 toolchain still has it. From 6.5 on, the bug
    /// firing again is a regression and fails the test.
    static var beforeFix: Bool {
        #if compiler(>=6.5)
            return false
        #else
            return true
        #endif
    }

    /// The failure is an assertion, so only a toolchain built with assertions shows it:
    /// snapshots, Linux nightly, and Windows releases. Elsewhere the source compiles.
    static var hasAssertions: Bool {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            guard let swiftc = tool("swiftc") else { return false }
            return run(swiftc, ["-frontend", "-version"], in: FileManager.default.temporaryDirectory, seconds: 60)
                .output.contains("+assertions")
        #else
            return false
        #endif
    }

    static let markers: [String] = ["Cannot dereference a null Type!"]

    #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
        static func bugFires() -> Bool? {
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Reproducer/Repro.swift.txt")
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("issue-111-\(ProcessInfo.processInfo.processIdentifier)")
            // REASON: best-effort cleanup of a scratch directory.
            // swiftlint:disable:next no_try_optional
            defer { try? FileManager.default.removeItem(at: work) }
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: work.appendingPathComponent("repro.swift"))
            } catch {
                Issue.record("could not stage the reproduction: \(error)")
                return nil
            }
            guard let launcher = tool("swiftc") else {
                Issue.record("no swiftc to run")
                return nil
            }
            let result = run(launcher, ["-c", "-O", "-swift-version", "6", "repro.swift", "-o", "repro.o"], in: work, seconds: 600)
            if result.timedOut {
                Issue.record("swiftc ran past its time limit")
                return nil
            }
            if markers.contains(where: result.output.contains) { return true }
            if result.status == 0 { return false }
            Issue.record("swiftc failed without the record's markers (exit \(result.status)):\n\(result.output.suffix(3000))")
            return nil
        }

        /// The launcher for a tool: the executable on PATH, or on macOS `xcrun <name>`.
        static func tool(_ name: String) -> (URL, [String])? {
            #if os(Windows)
                let separator: Character = ";"
                let candidates = ["\(name).exe", name]
            #else
                let separator: Character = ":"
                let candidates = [name]
            #endif
            let environment = ProcessInfo.processInfo.environment
            for directory in (environment["PATH"] ?? environment["Path"] ?? "").split(separator: separator) {
                for candidate in candidates {
                    let url = URL(fileURLWithPath: String(directory)).appendingPathComponent(candidate)
                    if FileManager.default.fileExists(atPath: url.path) && FileManager.default.isExecutableFile(atPath: url.path) {
                        return (url, [])
                    }
                }
            }
            #if os(macOS)
                return (URL(fileURLWithPath: "/usr/bin/xcrun"), [name])
            #else
                return nil
            #endif
        }

        static func run(_ launcher: (URL, [String]), _ arguments: [String], in directory: URL, seconds: Double)
            -> (status: Int32, output: String, timedOut: Bool)
        {
            let log = directory.appendingPathComponent("output-\(UUID().uuidString).txt")
            guard FileManager.default.createFile(atPath: log.path, contents: nil),
                let handle = try? FileHandle(forWritingTo: log)
            else { return (-1, "could not create \(log.path)", false) }
            let process = Process()
            process.executableURL = launcher.0
            process.arguments = launcher.1 + arguments
            process.currentDirectoryURL = directory
            process.environment = withToolchainRuntime(ProcessInfo.processInfo.environment)
            process.standardOutput = handle
            process.standardError = handle
            do { try process.run() } catch { return (-1, "could not launch \(launcher.0.path): \(error)", false) }
            let deadline = Date().addingTimeInterval(seconds)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            let timedOut = process.isRunning
            if timedOut { process.terminate() }
            process.waitUntilExit()
            // REASON: the log is read best-effort after the child has exited.
            // swiftlint:disable:next no_try_optional
            try? handle.close()
            let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            return (process.terminationStatus, output, timedOut)
        }
    #else
        static func bugFires() -> Bool? {
            Issue.record("this platform can't launch a tool from a test")
            return nil
        }
    #endif

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }
        withKnownIssue(
            "swift-institute/Issues#111",
            { #expect(fired == false) },
            when: { Self.hasAssertions && Self.beforeFix }
        )
    }
}

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    /// On macOS, a program built by a toolchain other than Xcode's still loads the system's
    /// Swift runtime, so a snapshot run would test the system's runtime, not the snapshot's.
    /// When the `swiftc` on PATH belongs to such a toolchain, point the loader at its runtime.
    /// Elsewhere, and for Xcode's toolchain, the environment is returned unchanged.
    func withToolchainRuntime(_ environment: [String: String]) -> [String: String] {
        #if os(macOS)
            for directory in (environment["PATH"] ?? "").split(separator: ":") {
                let swiftc = URL(fileURLWithPath: String(directory)).appendingPathComponent("swiftc")
                guard FileManager.default.isExecutableFile(atPath: swiftc.path) else { continue }
                let resolved = swiftc.resolvingSymlinksInPath()
                guard !resolved.path.contains(".app/Contents/Developer") else { return environment }
                let runtime = resolved.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("lib/swift/macosx")
                guard FileManager.default.fileExists(atPath: runtime.appendingPathComponent("libswiftCore.dylib").path)
                else { return environment }
                var environment = environment
                environment["DYLD_LIBRARY_PATH"] = runtime.path
                return environment
            }
        #endif
        return environment
    }
#endif
