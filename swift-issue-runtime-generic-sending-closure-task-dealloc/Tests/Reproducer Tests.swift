import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// A `sending` closure passed through a generic `@Sendable` async function value,
// from a function whose own parameter is `sending`, aborts the task allocator
// at `-Onone`: "freed pointer was not the last allocation" in
// `swift_task_dealloc`. `Crash.swift.txt` compiles cleanly but its program
// aborts, so it is compiled and run OUT OF PROCESS. `-O` hides it.
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

            guard FileManager.default.fileExists(atPath: crashSource.path) else {
                Issue.record("Sources/Reproducer/Crash.swift.txt is missing")
                return nil
            }

            let pid = ProcessInfo.processInfo.processIdentifier
            let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            let swiftCopy = temporary.appendingPathComponent("sending-thunk-freed-pointer-test-\(pid).swift")
            let program = temporary.appendingPathComponent("sending-thunk-freed-pointer-test-\(pid)")
            try? FileManager.default.removeItem(at: swiftCopy)
            try? FileManager.default.removeItem(at: program)
            guard (try? FileManager.default.copyItem(at: crashSource, to: swiftCopy)) != nil else {
                Issue.record("could not stage the reproduction")
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
            do { try compile.run() } catch {
                Issue.record("could not launch swiftc: \(error)")
                return nil
            }
            let compileText = String(decoding: compileErrors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            compile.waitUntilExit()
            // An assertions build rejects the function whose task allocation the release
            // build gets wrong: SIL verification (6.4.x) or ClosureLifetimeFixup (main). The
            // mangled name is matched without its module prefix, which follows the file name.
            if compile.terminationStatus != 0 && compileText.contains("3OneV6resume9returningyxn_tYaF") {
                return true
            }
            guard compile.terminationStatus == 0 else {
                Issue.record("the reproduction failed to compile without the known abort:\n\(compileText.suffix(3000))")
                return nil
            }

            let run = Process()
            run.executableURL = program
            var environment = ProcessInfo.processInfo.environment
            environment["SWIFT_BACKTRACE"] = "enable=no"
            run.environment = withToolchainRuntime(environment)
            let output = Pipe()
            let errors = Pipe()
            run.standardOutput = output
            run.standardError = errors
            do { try run.run() } catch {
                Issue.record("could not launch the reproduction: \(error)")
                return nil
            }
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
            Issue.record("the program ended without the record's output (status \(run.terminationStatus)):\n\(errorText.suffix(3000))")
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

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
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
