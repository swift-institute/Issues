import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// With CopyToBorrowOptimization, a client built with -O against a library built
// with -O -wmo reads an actor's `state` as `.running` after an awaited call set
// it to `.shuttingDown`. The two modules need their own flags, so they are built
// and run OUT OF PROCESS ([ISSUE-029]).
//
// The client loops 100 times and the probe runs it `runs` times: the bug was
// recorded as flaky (about 50 of 100 on 6.3.1). On 6.4.2 it is wrong 100 of 100.
//
// Seen on macOS only (6.3, 6.3.1, 6.4.2), so `when:` is macOS. The test stays
// green while the stale read happens and flips red once it stops.

// swiftlint:disable no_try_optional

@Suite
struct CopyToBorrowCrossModuleActorStateMiscompileReproducer {

    static let runs = 5

    static func run(_ arguments: [String], in directory: URL) -> (status: Int32, output: String)? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
            process.currentDirectoryURL = directory
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        #else
            return nil
        #endif
    }

    /// `true` when an iteration read stale actor state, `false` when every
    /// iteration of every run was correct, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let reproducer = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer")

            let pid = ProcessInfo.processInfo.processIdentifier
            let work = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("copytoborrow-actor-state-test-\(pid)")
            try? FileManager.default.removeItem(at: work)
            defer { try? FileManager.default.removeItem(at: work) }
            guard
                (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil,
                (try? FileManager.default.copyItem(
                    at: reproducer.appendingPathComponent("BugLib.swift.txt"),
                    to: work.appendingPathComponent("BugLib.swift")
                )) != nil,
                (try? FileManager.default.copyItem(
                    at: reproducer.appendingPathComponent("BugTest.swift.txt"),
                    to: work.appendingPathComponent("main.swift")
                )) != nil
            else { return nil }

            let library = [
                "swiftc", "-O", "-wmo", "-swift-version", "6", "-parse-as-library",
                "-module-name", "BugLib",
                "-emit-module", "-emit-module-path", "BugLib.swiftmodule",
                "-emit-object", "-o", "BugLib.o", "BugLib.swift",
            ]
            let client = [
                "swiftc", "-O", "-wmo", "-swift-version", "6",
                "-module-name", "BugTest", "-I", ".",
                "main.swift", "BugLib.o", "-o", "BugTest",
            ]
            for step in [library, client] {
                guard let result = run(step, in: work), result.status == 0 else { return nil }
            }

            var wrong = 0
            var clean = 0
            for _ in 0..<runs {
                guard let result = run(["./BugTest"], in: work), result.status == 0 else { continue }
                let bugLines = result.output.split(separator: "\n").filter { $0.hasPrefix("BUG") }.count
                wrong += bugLines
                if bugLines == 0 && result.output.contains("PASS") { clean += 1 }
            }
            if wrong > 0 { return true }
            if clean == runs { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "CopyToBorrowOptimization: client reads stale actor state from a -O -wmo library",
            { #expect(fired == false) },
            when: {
                #if os(macOS)
                    true
                #else
                    false
                #endif
            }
        )
    }
}

// swiftlint:enable no_try_optional
