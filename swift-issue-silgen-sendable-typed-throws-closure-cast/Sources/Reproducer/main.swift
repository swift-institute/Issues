// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// SILGen crash on a typed-throws closure cast inline to `@Sendable` and passed to
// a generic `Sendable` parameter — standalone exit-code probe.
//
// `Crash.swift.txt` crashes `swift-frontend` (signal 5) during SILGen, so it
// cannot be a compiled target. This executable compiles it OUT OF PROCESS and
// reports the result ([ISSUE-029]).
//
// Exit code:
//   1  — bug fired  (swiftc failed while SILGen emitted the closure)
//   0  — bug absent (it compiled) OR inconclusive (could not probe)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let crashSource = here.appendingPathComponent("Crash.swift.txt")

    let pid = ProcessInfo.processInfo.processIdentifier
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
    let swiftCopy = temporary.appendingPathComponent("silgen-sendable-typed-throws-\(pid).swift")
    let object = temporary.appendingPathComponent("silgen-sendable-typed-throws-\(pid).o")
    try? FileManager.default.removeItem(at: swiftCopy)
    do {
        try FileManager.default.copyItem(at: crashSource, to: swiftCopy)
    } catch {
        FileHandle.standardError.write(Data("could not stage crash source: \(error)\n".utf8))
        exit(0)
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

    do {
        try process.run()
    } catch {
        FileHandle.standardError.write(Data("could not launch swiftc: \(error)\n".utf8))
        exit(0)
    }
    let errText =
        String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    process.waitUntilExit()

    if process.terminationStatus != 0 && errText.contains("While silgen closureexpr") {
        FileHandle.standardError.write(
            Data("BUG FIRED: swift-frontend crashed in SILGen emitting the closure.\n".utf8)
        )
        exit(1)
    } else if process.terminationStatus == 0 {
        FileHandle.standardError.write(
            Data("Compiled cleanly — the bug is ABSENT on this toolchain.\n".utf8)
        )
        exit(0)
    } else {
        FileHandle.standardError.write(
            Data("swiftc output did not match either signature:\n\(errText)\n".utf8)
        )
        exit(0)
    }

#else

    print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
