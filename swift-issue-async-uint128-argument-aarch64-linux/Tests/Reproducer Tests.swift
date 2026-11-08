import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// At -Onone on Linux aarch64, a `UInt128` passed to or returned from an `async` function arrives corrupted.
// The record is the issue named in ../ISSUE; the reproduction is
// Sources/Reproducer/Repro.swift.txt, run out of process. A failure that carries none
// of the record's markers is recorded, never skipped: the bug changed.

@Suite
struct Reproducer {

    /// The defect shows only on Linux aarch64; elsewhere the program prints the right value.
    static var onLinuxArm64: Bool {
        #if os(Linux) && arch(arm64)
            return true
        #else
            return false
        #endif
    }

    static let markers: [String] = ["Fatal error: wrong:"]

    /// swiftc writes exactly the -o path, so on Windows the program must be named .exe.
    #if os(Windows)
        static let programName = "repro.exe"
    #else
        static let programName = "repro"
    #endif

    #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
        static func bugFires() -> Bool? {
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Reproducer/Repro.swift.txt")
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("issue-188-\(ProcessInfo.processInfo.processIdentifier)")
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
            let result = run(launcher, ["-Onone", "repro.swift", "-o", Self.programName], in: work, seconds: 600)
            guard !result.timedOut, result.status == 0 else {
                Issue.record("the reproduction didn't compile (exit \(result.status)):\n\(result.output.suffix(3000))")
                return nil
            }
            #if os(Windows)
                let program = (work.appendingPathComponent(Self.programName), [String]())
            #else
                let program = (work.appendingPathComponent(Self.programName), [String]())
            #endif
            let execution = run(program, [], in: work, seconds: 120)
            if markers.contains(where: execution.output.contains) { return true }
            if execution.status == 0 && ["42"].allSatisfy(execution.output.contains) { return false }
            Issue.record("the program ended without the record's output (exit \(execution.status)):\n\(execution.output.suffix(3000))")
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
        guard let fired = Self.bugFires() else { Issue.record("no verdict: the reproduction could not be staged, built or run here (a reason recorded above, if any, says why)"); return }
        withKnownIssue(
            "swift-institute/Issues#188",
            { #expect(fired == false) },
            when: { Self.onLinuxArm64 }
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
