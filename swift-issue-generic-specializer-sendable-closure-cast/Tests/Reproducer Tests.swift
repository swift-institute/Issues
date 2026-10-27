import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// At `-O`, GenericSpecializer fails the TypeSubstCloner assertion
// `Subs.empty() || SubstCalleeSILType == …` specializing `insert<Value: Sendable>`
// for a closure literal cast inline with `as @Sendable (Int) -> Int`.
// `Crash.swift.txt` aborts the compiler, so it is compiled OUT OF PROCESS
// ([ISSUE-029]).
//
// Recorded only on a Linux 6.4-dev assertions toolchain (Ubuntu 24.04 x86_64).
// Apple's macOS 6.4 and 6.4.2 release toolchains build it cleanly, but they have
// no assertions, so that is not evidence of a fix. A clean build on a compiler
// without assertions is "inconclusive" and skips. `when:` is Linux, where the
// assertions nightlies run: green while the assertion fires there, red once an
// assertions toolchain builds the source.

@Suite
struct GenericSpecializerSendableClosureCastReproducer {

    /// The settings of the package the crash was recorded in. Which of them the
    /// crash needs is not known yet.
    static let packageSettings = [
        "-strict-memory-safety",
        "-enable-upcoming-feature", "ExistentialAny",
        "-enable-upcoming-feature", "InternalImportsByDefault",
        "-enable-upcoming-feature", "MemberImportVisibility",
        "-enable-upcoming-feature", "NonisolatedNonsendingByDefault",
        "-enable-experimental-feature", "LifetimeDependence",
        "-enable-experimental-feature", "Lifetimes",
        "-enable-experimental-feature", "SuppressedAssociatedTypes",
        "-enable-upcoming-feature", "InferIsolatedConformances",
    ]

    /// Where the assertion is known to fire: the Linux assertions toolchains.
    static var knownAffected: Bool {
        #if os(Linux)
            return true
        #else
            return false
        #endif
    }

    #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        /// Runs `swiftc` with `arguments`; returns the exit status and stderr.
        static func swiftc(_ arguments: [String]) -> (status: Int32, errors: String)? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc"] + arguments
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
            return (process.terminationStatus, errText)
        }
    #endif

    /// `true` when the assertion fired, `false` when an assertions compiler built
    /// the source, `nil` when inconclusive (including a compiler without assertions).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let crashSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            let swiftCopy = temporary.appendingPathComponent("generic-specializer-sendable-cast-test-\(pid).swift")
            let object = temporary.appendingPathComponent("generic-specializer-sendable-cast-test-\(pid).o")
            let assertProbe = temporary.appendingPathComponent("generic-specializer-assert-probe-test-\(pid).swift")
            try? FileManager.default.removeItem(at: swiftCopy)
            guard (try? FileManager.default.copyItem(at: crashSource, to: swiftCopy)) != nil,
                (try? Data("let x = 1\n".utf8).write(to: assertProbe)) != nil
            else {
                return nil
            }
            defer {
                try? FileManager.default.removeItem(at: swiftCopy)
                try? FileManager.default.removeItem(at: object)
                try? FileManager.default.removeItem(at: assertProbe)
            }

            guard
                let result = swiftc(
                    ["-O", "-wmo", "-swift-version", "6"] + packageSettings
                        + ["-c", swiftCopy.path, "-o", object.path]
                )
            else { return nil }

            if result.status != 0
                && (result.errors.contains("TypeSubstCloner") || result.errors.contains("SubstCalleeSILType"))
            {
                return true
            }
            guard result.status == 0 else { return nil }

            // `-debug-assert-after-parse` fails a C assert: it crashes an assertions
            // build and is a silent no-op error in a release build.
            guard let probe = swiftc(["-typecheck", "-Xfrontend", "-debug-assert-after-parse", assertProbe.path])
            else { return nil }
            let hasAssertions = probe.errors.contains("This is an assertion") || probe.errors.contains("Stack dump")
            return hasAssertions ? false : nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "GenericSpecializer: TypeSubstCloner assertion for a closure cast to @Sendable, at -O",
            { #expect(fired == false) },
            when: { Self.knownAffected }
        )
    }
}
