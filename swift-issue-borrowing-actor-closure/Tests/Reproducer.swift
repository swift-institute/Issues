import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

@Suite
struct BorrowingActorClosureReproducer {
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let crashSource = here.appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

        guard FileManager.default.fileExists(atPath: crashSource.path) else {
            return nil
        }

        let identifier = ProcessInfo.processInfo.processIdentifier
        let stagedSource = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("borrowing-actor-closure-test-\(identifier).swift")
        let objectFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("borrowing-actor-closure-test-\(identifier).o")

        defer {
            try? FileManager.default.removeItem(at: stagedSource)
            try? FileManager.default.removeItem(at: objectFile)
        }

        guard (try? FileManager.default.copyItem(
            at: crashSource,
            to: stagedSource
        )) != nil else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swiftc", "-parse-as-library", "-swift-version", "6", "-c",
            stagedSource.path,
            "-o", objectFile.path,
        ]

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        let output = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if output.contains("MoveOnlyTypeEliminator")
            || output.contains("Unhandled SIL Instruction") {
            return true
        }

        if process.terminationStatus == 0 {
            return false
        }

        return nil
        #else
        return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else {
            return
        }

        withKnownIssue(
            "swift-institute/Issues#3 — MoveOnlyTypeEliminator crash for a borrowed actor parameter captured by a closure",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
