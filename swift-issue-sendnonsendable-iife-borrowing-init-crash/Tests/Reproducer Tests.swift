import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// The SendNonSendable pass aborts in `Partition::merge` when a function body holds
// an immediately-invoked closure that builds a `~Copyable, ~Escapable` View through
// a public borrowing `@_lifetime` init. `Crash.swift.txt` aborts the compiler, so
// the library and the caller are compiled OUT OF PROCESS.
//
// Fires on release toolchains (6.3.1, 6.4.2 on macOS arm64), so `when: { true }`:
// the test stays green while the compiler aborts and flips red once the caller
// compiles.

@Suite
struct SendNonSendableIIFEBorrowingInitCrashReproducer {

    /// `true` when swiftc aborted in SendNonSendable, `false` when the caller
    /// compiled, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let sources = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer")
            let librarySource = sources.appendingPathComponent("ReproLib.swift.txt")
            let crashSource = sources.appendingPathComponent("Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: librarySource.path),
                FileManager.default.fileExists(atPath: crashSource.path)
            else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let stage = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("sendnonsendable-iife-test-\(pid)")
            try? FileManager.default.removeItem(at: stage)
            guard (try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)) != nil,
                (try? FileManager.default.copyItem(
                    at: librarySource,
                    to: stage.appendingPathComponent("ReproLib.swift")
                )) != nil,
                (try? FileManager.default.copyItem(
                    at: crashSource,
                    to: stage.appendingPathComponent("main.swift")
                )) != nil
            else {
                try? FileManager.default.removeItem(at: stage)
                return nil
            }
            defer { try? FileManager.default.removeItem(at: stage) }

            func swiftc(_ arguments: [String]) -> (status: Int32, errors: String)? {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["swiftc"] + arguments
                process.currentDirectoryURL = stage
                let stderr = Pipe()
                process.standardError = stderr
                process.standardOutput = FileHandle.nullDevice
                resolveEnv(process)
                do { try process.run() } catch { return nil }
                let errors =
                    String(
                        data: stderr.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                process.waitUntilExit()
                return (process.terminationStatus, errors)
            }

            let library = swiftc([
                    "-emit-module", "-parse-as-library",
                    "-module-name", "ReproLib",
                    "-swift-version", "6",
                    "-enable-experimental-feature", "Lifetimes",
                    "ReproLib.swift",
                    "-emit-module-path", "ReproLib.swiftmodule",
                    "-o", "ReproLib.o",
                ])
            guard let library, library.status == 0 else {
                Issue.record("ReproLib didn't build:\n\(library.map { String($0.errors.suffix(3000)) } ?? "swiftc did not launch")")
                return nil
            }

            guard
                let caller = swiftc([
                    "-c",
                    "-swift-version", "6",
                    "-Onone",
                    "-enable-experimental-feature", "Lifetimes",
                    "-I", ".",
                    "main.swift",
                    "-o", "main.o",
                ])
            else { return nil }

            if caller.status != 0
                // CI's Linux x86_64 leg prints only the abort (std::out_of_range from map::at),
                // without the pretty stack that names the pass.
                && (caller.errors.contains("\"SendNonSendable\"") || caller.errors.contains("While silgen closureexpr")
                    || caller.errors.contains("terminate called after throwing an instance of 'std::out_of_range'"))
            { return true }
            if caller.status == 0 { return false }
            Issue.record("swiftc failed without the record's markers (exit \(caller.status)):\n\(caller.errors.suffix(3000))")
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { Issue.record("no verdict: the reproduction could not be staged, built or run here (a reason recorded above, if any, says why)"); return }

        withKnownIssue(
            "SendNonSendable: Partition::merge abort on an IIFE around a borrowing @_lifetime init",
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
