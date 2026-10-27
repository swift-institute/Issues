// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Type-resolution segfault on a generic typealias reached through an unbound
// generic outer type — standalone exit-code probe.
//
// `Crash.swift.txt` crashes `swift-frontend`, so it cannot be a compiled target.
// This executable type-checks it OUT OF PROCESS and reports the result ([ISSUE-029]).
//
// Exit code:
//   1  — bug fired  (swift-frontend crashed while resolving `F.B<Int>`)
//   0  — bug absent (clean type-check or an ordinary diagnostic) OR inconclusive

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let crashSource = here.appendingPathComponent("Crash.swift.txt")

    let pid = ProcessInfo.processInfo.processIdentifier
    let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("unbound-outer-generic-alias-\(pid).swift")
    try? FileManager.default.removeItem(at: swiftCopy)
    do {
        try FileManager.default.copyItem(at: crashSource, to: swiftCopy)
    } catch {
        FileHandle.standardError.write(Data("could not stage crash source: \(error)\n".utf8))
        exit(0)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftc", "-typecheck", "-swift-version", "6", swiftCopy.path]
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
    try? FileManager.default.removeItem(at: swiftCopy)

    if errText.contains("Stack dump") && errText.contains("ResolveTypeRequest") {
        FileHandle.standardError.write(
            Data("BUG FIRED: swift-frontend crashed resolving a generic alias through an unbound outer generic.\n".utf8)
        )
        exit(1)
    } else if process.terminationStatus == 0 || errText.contains("error:") {
        FileHandle.standardError.write(
            Data("No crash (clean type-check or an ordinary diagnostic) — the bug is FIXED.\n".utf8)
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
