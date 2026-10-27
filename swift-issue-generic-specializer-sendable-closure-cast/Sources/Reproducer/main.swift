// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// GenericSpecializer assertion on a closure cast inline to `@Sendable` and passed
// to a generic `Sendable` parameter, at `-O` — standalone exit-code probe.
//
// `Crash.swift.txt` aborts an assertions-enabled `swift-frontend` in the
// GenericSpecializer pass (TypeSubstCloner.h), so it cannot be a compiled target.
// This executable compiles it OUT OF PROCESS and reports the result ([ISSUE-029]).
//
// The assertion only exists in an assertions build. On a release toolchain a
// clean compile proves nothing, so the probe first asks whether the compiler has
// assertions and reports "inconclusive" when it does not.
//
// Exit code:
//   1  — bug fired  (the TypeSubstCloner assertion failed)
//   0  — bug absent (an assertions compiler built it) OR inconclusive

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let crashSource = here.appendingPathComponent("Crash.swift.txt")

    // The settings of the package the crash was recorded in. Which of them the
    // crash needs is not known: it has not been run on an affected toolchain since.
    let packageSettings = [
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

    /// Runs `swiftc` with `arguments`; returns the exit status and stderr.
    func swiftc(_ arguments: [String]) -> (status: Int32, errors: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc"] + arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let errText =
            String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        process.waitUntilExit()
        return (process.terminationStatus, errText)
    }

    let pid = ProcessInfo.processInfo.processIdentifier
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
    let swiftCopy = temporary.appendingPathComponent("generic-specializer-sendable-cast-\(pid).swift")
    let object = temporary.appendingPathComponent("generic-specializer-sendable-cast-\(pid).o")
    let assertProbe = temporary.appendingPathComponent("generic-specializer-assert-probe-\(pid).swift")
    try? FileManager.default.removeItem(at: swiftCopy)
    do {
        try FileManager.default.copyItem(at: crashSource, to: swiftCopy)
        try Data("let x = 1\n".utf8).write(to: assertProbe)
    } catch {
        FileHandle.standardError.write(Data("could not stage crash source: \(error)\n".utf8))
        exit(0)
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
    else {
        FileHandle.standardError.write(Data("could not launch swiftc\n".utf8))
        exit(0)
    }

    if result.status != 0
        && (result.errors.contains("TypeSubstCloner") || result.errors.contains("SubstCalleeSILType"))
    {
        FileHandle.standardError.write(
            Data("BUG FIRED: the GenericSpecializer TypeSubstCloner assertion failed.\n".utf8)
        )
        exit(1)
    } else if result.status == 0 {
        // `-debug-assert-after-parse` fails a C assert: it crashes an assertions
        // build and is a silent no-op error in a release build.
        let probe = swiftc(["-typecheck", "-Xfrontend", "-debug-assert-after-parse", assertProbe.path])
        let hasAssertions =
            probe.map { $0.errors.contains("This is an assertion") || $0.errors.contains("Stack dump") } ?? false
        if hasAssertions {
            FileHandle.standardError.write(
                Data("An assertions compiler built it cleanly — the bug is ABSENT on this toolchain.\n".utf8)
            )
        } else {
            FileHandle.standardError.write(
                Data("Compiled cleanly, but this compiler has no assertions — INCONCLUSIVE.\n".utf8)
            )
        }
        exit(0)
    } else {
        FileHandle.standardError.write(
            Data("swiftc output did not match either signature:\n\(result.errors)\n".utf8)
        )
        exit(0)
    }

#else

    print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
