import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// The SendNonSendable pass aborts in `Partition::merge` when a function body holds
// an immediately-invoked closure that builds a `~Copyable, ~Escapable` View through
// a public borrowing `@_lifetime` init. `Crash.swift.txt` aborts the compiler, so
// the library and the caller are compiled OUT OF PROCESS ([ISSUE-029]).
//
// Fires on release toolchains (6.3.1, 6.4.2 on macOS arm64), so `when: { true }`:
// the test stays green while the compiler aborts and flips red once the caller
// compiles.

@Suite
struct SendNonSendableIIFEBorrowingInitCrashReproducer {

    /// `true` when swiftc aborted in SendNonSendable, `false` when the caller
    /// compiled, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
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
                do { try process.run() } catch { return nil }
                let errors =
                    String(
                        data: stderr.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                process.waitUntilExit()
                return (process.terminationStatus, errors)
            }

            guard
                let library = swiftc([
                    "-emit-module", "-parse-as-library",
                    "-module-name", "ReproLib",
                    "-swift-version", "6",
                    "-enable-experimental-feature", "Lifetimes",
                    "ReproLib.swift",
                    "-emit-module-path", "ReproLib.swiftmodule",
                    "-o", "ReproLib.o",
                ]),
                library.status == 0
            else { return nil }

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

            if caller.status != 0 && caller.errors.contains("\"SendNonSendable\"") { return true }
            if caller.status == 0 { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "SendNonSendable: Partition::merge abort on an IIFE around a borrowing @_lifetime init",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
