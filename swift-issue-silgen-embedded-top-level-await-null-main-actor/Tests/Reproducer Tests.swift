import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// Embedded Swift: a top-level `await` crashes SILGen. `SILGenModule::emitEntryPoint` sets the
// async top-level code's expected executor from `getMainActorType()`, which is null where Embedded
// Swift has no `MainActor`, instead of the compiler diagnosing the program.
// The record is the issue named in ../ISSUE; the reproduction is
// Sources/Reproducer/Repro.swift.txt, compiled out of process for the host's Embedded target.
// An outcome that is neither the crash nor a clean compile or diagnostic is recorded, never
// skipped: the bug changed.

@Suite
struct Reproducer {

    /// The bug: the frontend crashes while lowering the module to SIL.
    static let markers = ["Stack dump", "ASTLoweringRequest"]

    #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
        static func embedded(_ file: String) -> [String] {
            ["-enable-experimental-feature", "Embedded", "-wmo", "-module-name", "R", "-c", file, "-o", "out.o"]
        }

        enum Verdict { case tested(fired: Bool), notApplicable(String) }

        static func verdict() -> Verdict? {
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Reproducer/Repro.swift.txt")
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("issue-299-\(ProcessInfo.processInfo.processIdentifier)")
            // REASON: best-effort cleanup of a scratch directory.
            // swiftlint:disable:next no_try_optional
            defer { try? FileManager.default.removeItem(at: work) }
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: work.appendingPathComponent("repro.swift"))
                try "let x = 1\n".write(to: work.appendingPathComponent("control.swift"), atomically: true, encoding: .utf8)
            } catch {
                Issue.record("could not stage the reproduction: \(error)")
                return nil
            }
            guard let swiftc = tool("swiftc") else {
                Issue.record("no swiftc to run")
                return nil
            }
            // Not applicable: Embedded Swift needs its own standard library for the host target, which
            // some toolchains (Xcode's, Windows') do not ship. The control is a one-line program.
            let control = run(swiftc, embedded("control.swift"), in: work, seconds: 600)
            if control.status != 0 {
                return .notApplicable("this toolchain cannot compile Embedded Swift for the host:\n\(control.output.suffix(1000))")
            }
            let result = run(swiftc, embedded("repro.swift"), in: work, seconds: 600)
            if result.timedOut {
                Issue.record("swiftc ran past its time limit")
                return nil
            }
            if markers.allSatisfy(result.output.contains) {
                return .tested(fired: true)
            }
            // Fixed: the program compiles, or the compiler rejects it with a diagnostic.
            if result.status == 0 || (result.output.contains("error:") && !result.output.contains("Stack dump")) {
                return .tested(fired: false)
            }
            Issue.record("swiftc failed differently (exit \(result.status)):\n\(result.output.suffix(3000))")
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

        @Test
        func reproducer() {
            switch Self.verdict() {
            case nil:
                Issue.record("no verdict: the reproduction could not be staged, built or run here (a reason recorded above, if any, says why)")
            case .notApplicable(let reason):
                // The one stated exception: without an Embedded standard library there is nothing to test.
                print("not applicable: \(reason)")
            case .tested(let fired):
                withKnownIssue("swift-institute/Issues#299") { #expect(fired == false) }
            }
        }
    #else
        @Test
        func reproducer() {
            Issue.record("this platform can't launch a tool from a test")
        }
    #endif
}
