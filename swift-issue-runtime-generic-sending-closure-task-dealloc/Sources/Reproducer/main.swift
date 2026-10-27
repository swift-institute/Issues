// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Task-allocator abort ("freed pointer was not the last allocation") when a
// `sending` closure is passed through a generic `@Sendable` async function value
// — standalone exit-code probe.
//
// `Crash.swift.txt` compiles cleanly but its program aborts at run time, which
// would take the probe down with it. This executable compiles it at `-Onone`
// OUT OF PROCESS, runs the result as a child process and reports ([ISSUE-029]).
// `-O` hides the bug, so the flag matters.
//
// Exit code:
//   1  — bug fired  (the child aborted with "freed pointer was not the last allocation")
//   0  — bug absent (it printed "hello") OR inconclusive (could not probe)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let crashSource = here.appendingPathComponent("Crash.swift.txt")

    let pid = ProcessInfo.processInfo.processIdentifier
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
    let swiftCopy = temporary.appendingPathComponent("sending-thunk-freed-pointer-\(pid).swift")
    let program = temporary.appendingPathComponent("sending-thunk-freed-pointer-\(pid)")
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
        "swiftc", "-Onone", "-swift-version", "6", "-parse-as-library",
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
    let errors = Pipe()
    run.standardOutput = output
    run.standardError = errors
    do {
        try run.run()
    } catch {
        FileHandle.standardError.write(Data("could not launch the compiled program: \(error)\n".utf8))
        exit(0)
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
        FileHandle.standardError.write(
            Data("BUG FIRED: the program aborted: freed pointer was not the last allocation.\n".utf8)
        )
        exit(1)
    } else if run.terminationStatus == 0 && outputText.contains("hello") {
        FileHandle.standardError.write(
            Data("Printed hello and exited 0 — the bug is ABSENT on this toolchain.\n".utf8)
        )
        exit(0)
    } else {
        FileHandle.standardError.write(
            Data("output matched neither signature (status \(run.terminationStatus)):\n\(errorText)\n".utf8)
        )
        exit(0)
    }

#else

    print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
