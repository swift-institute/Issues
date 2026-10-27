import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// A `sending` closure passed through a generic `@Sendable` async function value,
// from a function whose own parameter is `sending`, aborts the task allocator
// at `-Onone`: "freed pointer was not the last allocation" in
// `swift_task_dealloc`. `Crash.swift.txt` compiles cleanly but its program
// aborts, so it is compiled and run OUT OF PROCESS ([ISSUE-029]). `-O` hides it.
//
// Fires on Apple Swift 6.4.2 (macOS arm64). The code is compiler-generated task
// allocation, not target code, so `when: { true }`: green while the abort
// fires, red once a toolchain runs the program to completion.

@Suite
struct RuntimeSendingThunkFreedPointerReproducer {

    /// `true` when the compiled program aborted in the task allocator, `false`
    /// when it printed "hello" and exited 0, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let crashSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            let swiftCopy = temporary.appendingPathComponent("sending-thunk-freed-pointer-test-\(pid).swift")
            let program = temporary.appendingPathComponent("sending-thunk-freed-pointer-test-\(pid)")
            try? FileManager.default.removeItem(at: swiftCopy)
            try? FileManager.default.removeItem(at: program)
            guard (try? FileManager.default.copyItem(at: crashSource, to: swiftCopy)) != nil else {
                return nil
            }
            defer {
                try? FileManager.default.removeItem(at: swiftCopy)
                try? FileManager.default.removeItem(at: program)
            }

            let compile = Process()
            compile.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            compile.arguments = [
                "swiftc", "-Onone", "-swift-version", "6", "-parse-as-library",
                swiftCopy.path, "-o", program.path,
            ]
            let compileErrors = Pipe()
            compile.standardError = compileErrors
            compile.standardOutput = Pipe()
            do { try compile.run() } catch { return nil }
            _ = compileErrors.fileHandleForReading.readDataToEndOfFile()
            compile.waitUntilExit()
            guard compile.terminationStatus == 0 else { return nil }

            let run = Process()
            run.executableURL = program
            var environment = ProcessInfo.processInfo.environment
            environment["SWIFT_BACKTRACE"] = "enable=no"
            run.environment = environment
            let output = Pipe()
            let errors = Pipe()
            run.standardOutput = output
            run.standardError = errors
            do { try run.run() } catch { return nil }
            let errorText =
                String(
                    data: errors.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            let outputText =
                String(
                    data: output.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            run.waitUntilExit()

            if run.terminationReason == .uncaughtSignal && errorText.contains("not the last allocation") {
                return true
            }
            if run.terminationStatus == 0 && outputText.contains("hello") { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "Task allocator: freed pointer was not the last allocation, sending closure through a generic async value",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
