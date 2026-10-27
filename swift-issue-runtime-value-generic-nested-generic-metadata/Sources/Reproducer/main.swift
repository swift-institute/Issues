// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Runtime metadata crash for a generic type nested in a value-generic type —
// standalone exit-code probe (swift-institute/Issues#105).
//
// `Crash.swift.txt` compiles cleanly but its program crashes at run time, which
// would take the probe down with it. This executable compiles it at `-Onone`
// OUT OF PROCESS, runs the result as a child process and reports ([ISSUE-029]).
// `-O` emits this metadata statically and hides the bug, so the flag matters.
//
// Exit code:
//   1  — bug fired  (the child program died on a signal)
//   0  — bug absent (it printed the type name) OR inconclusive (could not probe)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let crashSource = here.appendingPathComponent("Crash.swift.txt")
    // The fixed output is `main.Link<1>.Node<Swift.Int>`; match its tail.
    let expected = ".Node<Swift.Int>"

    let pid = ProcessInfo.processInfo.processIdentifier
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
    let swiftCopy = temporary.appendingPathComponent("value-generic-nested-metadata-\(pid).swift")
    let program = temporary.appendingPathComponent("value-generic-nested-metadata-\(pid)")
    try? FileManager.default.removeItem(at: swiftCopy)
    try? FileManager.default.removeItem(at: program)
    do {
        try FileManager.default.copyItem(at: crashSource, to: swiftCopy)
    } catch {
        FileHandle.standardError.write(Data("could not stage crash source: \(error)\n".utf8))
        exit(0)
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
    do {
        try compile.run()
    } catch {
        FileHandle.standardError.write(Data("could not launch swiftc: \(error)\n".utf8))
        exit(0)
    }
    let compileText =
        String(
            data: compileErrors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    compile.waitUntilExit()
    guard compile.terminationStatus == 0 else {
        FileHandle.standardError.write(Data("swiftc failed, inconclusive:\n\(compileText)\n".utf8))
        exit(0)
    }

    let run = Process()
    run.executableURL = program
    var environment = ProcessInfo.processInfo.environment
    environment["SWIFT_BACKTRACE"] = "enable=no"
    run.environment = environment
    let output = Pipe()
    run.standardOutput = output
    run.standardError = FileHandle.nullDevice
    do {
        try run.run()
    } catch {
        FileHandle.standardError.write(Data("could not launch the compiled program: \(error)\n".utf8))
        exit(0)
    }
    let outputText =
        String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    run.waitUntilExit()

    if run.terminationReason == .uncaughtSignal {
        FileHandle.standardError.write(
            Data("BUG FIRED: the program died on signal \(run.terminationStatus) building Link<1>.Node<Int>.\n".utf8)
        )
        exit(1)
    } else if run.terminationStatus == 0 && outputText.contains(expected) {
        FileHandle.standardError.write(
            Data("Printed the type name — the bug is ABSENT on this toolchain.\n".utf8)
        )
        exit(0)
    } else {
        FileHandle.standardError.write(
            Data("output matched neither signature (status \(run.terminationStatus)):\n\(outputText)\n".utf8)
        )
        exit(0)
    }

#else

    print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
