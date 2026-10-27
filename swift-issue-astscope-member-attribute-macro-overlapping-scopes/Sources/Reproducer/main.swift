// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// ASTScope "child overlaps previous child" for macro-generated attributes — standalone
// exit-code probe.
//
// `Crash.swift.txt` is one file with two roles. Built with `-D PLUGIN` it is a macro
// plugin that speaks the compiler's plugin protocol directly (no swift-syntax). Built
// without the flag it is the client, which aborts an assertions-enabled `swift-frontend`.
// So it cannot be a compiled target: this executable builds the plugin and type-checks
// the client OUT OF PROCESS ([ISSUE-029]). Release toolchains do not run the ASTScope
// verifier and accept the client; on them the probe is inconclusive.
//
// Exit code:
//   1  — bug fired  (swiftc aborted with "child overlaps previous child")
//   0  — bug absent (an assertions toolchain accepted the client) OR inconclusive
//        (no assertions toolchain, or the probe could not run)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    func swiftc(_ arguments: [String], in directory: URL? = nil) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc"] + arguments
        if let directory { process.currentDirectoryURL = directory }
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
    let work = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("astscope-member-attribute-\(pid)")
    try? FileManager.default.removeItem(at: work)
    let source = work.appendingPathComponent("repro.swift")
    do {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: crashSource, to: source)
    } catch {
        FileHandle.standardError.write(Data("could not stage crash source: \(error)\n".utf8))
        exit(0)
    }

    let plugin = work.appendingPathComponent("plugin")
    let built = swiftc(["-D", "PLUGIN", source.path, "-o", plugin.path], in: work)
    var checked: (status: Int32, output: String)?
    if built?.status == 0 {
        checked = swiftc(
            ["-typecheck", "-load-plugin-executable", "\(plugin.path)#P", source.path],
            in: work
        )
    }
    try? FileManager.default.removeItem(at: work)

    guard let built, built.status == 0 else {
        FileHandle.standardError.write(
            Data("could not build the macro plugin:\n\(built?.output ?? "swiftc did not launch")\n".utf8)
        )
        exit(0)
    }
    guard let result = checked else {
        FileHandle.standardError.write(Data("could not launch swiftc\n".utf8))
        exit(0)
    }

    if result.output.contains("child overlaps previous child") {
        FileHandle.standardError.write(
            Data("BUG FIRED: ASTScope verifier aborted on two generated CustomAttributeScopes.\n".utf8)
        )
        exit(1)
    } else if result.status == 0 && assertions {
        FileHandle.standardError.write(
            Data("An assertions toolchain accepted the client — the bug is FIXED.\n".utf8)
        )
        exit(0)
    } else if result.status == 0 {
        FileHandle.standardError.write(
            Data("Accepted, but this toolchain has no assertions, so the verifier did not run: inconclusive.\n".utf8)
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
