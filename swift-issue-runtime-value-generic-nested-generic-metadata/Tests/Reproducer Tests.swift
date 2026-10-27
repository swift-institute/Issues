import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// swift-institute/Issues#105. Instantiating metadata at run time for a generic
// type nested in a value-generic type (`Link<1>.Node<Int>`) crashes inside
// libswiftCore. `Crash.swift.txt` compiles cleanly but its program crashes, so it
// is compiled at `-Onone` and run OUT OF PROCESS ([ISSUE-029]). `-O` hides it.
//
// A regression in Swift 6.4 (swiftlang/swift#89965, cherry-picked to 6.4.x as
// #89995). Fixed on main by swiftlang/swift#91267, not backported to 6.4.x. So
// `when:` is the 6.4 compiler family: green while 6.4.x crashes, red if a 6.4.x
// release stops crashing. On 6.3 and 6.5+ the test is ordinary regression
// coverage.

@Suite
struct RuntimeValueGenericNestedGenericMetadataReproducer {

    /// The toolchains known to crash: every 6.4.x checked so far.
    static var knownAffected: Bool {
        #if compiler(>=6.4) && !compiler(>=6.5)
            return true
        #else
            return false
        #endif
    }

    /// `true` when the compiled program died on a signal, `false` when it printed
    /// the type name, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let crashSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            let swiftCopy = temporary.appendingPathComponent("value-generic-nested-metadata-test-\(pid).swift")
            let program = temporary.appendingPathComponent("value-generic-nested-metadata-test-\(pid)")
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
                "swiftc", "-Onone", "-swift-version", "6", "-module-name", "main",
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
            run.standardOutput = output
            run.standardError = FileHandle.nullDevice
            do { try run.run() } catch { return nil }
            let outputText =
                String(
                    data: output.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            run.waitUntilExit()

            if run.terminationReason == .uncaughtSignal { return true }
            if run.terminationStatus == 0 && outputText.contains(".Node<Swift.Int>") { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "swift-institute/Issues#105 — runtime SIGSEGV: metadata for a generic type nested in a value-generic type",
            { #expect(fired == false) },
            when: { Self.knownAffected }
        )
    }
}
