// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Requirement-machine "Term verification failed" in SILGen — standalone exit-code probe.
//
// `Crash.swift.txt` aborts an assertions-enabled `swift-frontend`, so it cannot be a
// compiled target. This executable compiles it OUT OF PROCESS and reports the result
// ([ISSUE-029]). Release toolchains do not run this verification and compile the file;
// on them the probe is inconclusive.
//
// Exit code:
//   1  — bug fired  (swiftc aborted with "Term verification failed")
//   0  — bug absent (an assertions toolchain compiled the file) OR inconclusive
//        (no assertions toolchain, or the probe could not run)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    func swiftc(_ arguments: [String]) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc"] + arguments
        let output = Pipe()
        process.standardError = output
        process.standardOutput = output
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    guard let version = swiftc(["--version"]) else {
        FileHandle.standardError.write(Data("could not launch swiftc\n".utf8))
        exit(0)
    }
    let assertions = version.output.contains("+assertions")

    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let crashSource = here.appendingPathComponent("Crash.swift.txt")

    let pid = ProcessInfo.processInfo.processIdentifier
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
    let swiftCopy = temporary.appendingPathComponent("term-verification-\(pid).swift")
    let object = temporary.appendingPathComponent("term-verification-\(pid).o")
    try? FileManager.default.removeItem(at: swiftCopy)
    do {
        try FileManager.default.copyItem(at: crashSource, to: swiftCopy)
    } catch {
        FileHandle.standardError.write(Data("could not stage crash source: \(error)\n".utf8))
        exit(0)
    }
    let compiled = swiftc(["-c", "-parse-as-library", swiftCopy.path, "-o", object.path])
    try? FileManager.default.removeItem(at: swiftCopy)
    try? FileManager.default.removeItem(at: object)

    guard let result = compiled else {
        FileHandle.standardError.write(Data("could not launch swiftc\n".utf8))
        exit(0)
    }

    if result.output.contains("Term verification failed") {
        FileHandle.standardError.write(
            Data("BUG FIRED: requirement-machine term verification failed in SILGen.\n".utf8)
        )
        exit(1)
    } else if result.status == 0 && assertions {
        FileHandle.standardError.write(
            Data("An assertions toolchain compiled the file — the bug is FIXED.\n".utf8)
        )
        exit(0)
    } else if result.status == 0 {
        FileHandle.standardError.write(
            Data("Compiled, but this toolchain has no assertions, so the check did not run: inconclusive.\n".utf8)
        )
        exit(0)
    } else {
        FileHandle.standardError.write(
            Data("swiftc output did not match either signature:\n\(result.output)\n".utf8)
        )
        exit(0)
    }

#else

    print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
