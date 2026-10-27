import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// SILGen crashes (signal 5, `createInputFunctionArgument` under
// `LoweredParamGenerator::claimNext`) emitting a typed-throws closure literal that
// is cast inline with `as @Sendable (Int) throws(TestError) -> Int` and passed to
// a generic `<V: Sendable>` parameter. `Crash.swift.txt` crashes the compiler, so
// it is compiled OUT OF PROCESS ([ISSUE-029]).
//
// Fires on 6.3.1 and 6.4.2 (macOS arm64) with no feature flags, at `-Onone`. SILGen
// does not depend on the target, so `when: { true }`: the test stays green while
// the crash fires and flips red once a toolchain compiles the source.

@Suite
struct SILGenSendableTypedThrowsClosureCastReproducer {

    /// `true` when swiftc crashed in SILGen, `false` when it compiled, `nil` when
    /// inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let crashSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            let swiftCopy = temporary.appendingPathComponent("silgen-sendable-typed-throws-test-\(pid).swift")
            let object = temporary.appendingPathComponent("silgen-sendable-typed-throws-test-\(pid).o")
            try? FileManager.default.removeItem(at: swiftCopy)
            guard (try? FileManager.default.copyItem(at: crashSource, to: swiftCopy)) != nil else {
                return nil
            }
            defer {
                try? FileManager.default.removeItem(at: swiftCopy)
                try? FileManager.default.removeItem(at: object)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "swiftc", "-Onone", "-g", "-swift-version", "6",
                "-c", swiftCopy.path, "-o", object.path,
            ]
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = Pipe()

            do { try process.run() } catch { return nil }
            let errText =
                String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            process.waitUntilExit()

            if process.terminationStatus != 0 && errText.contains("While silgen closureexpr") { return true }
            if process.terminationStatus == 0 { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "SILGen: signal 5 in createInputFunctionArgument for a typed-throws closure cast to @Sendable",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
