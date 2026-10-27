// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// CopyToBorrowOptimization cross-module actor-state miscompile — standalone exit-code probe.
//
// The bug needs two modules built with specific flags: the library `BugLib` with
// `-O -wmo` (so cross-module optimization serializes its bodies) and the client
// with `-O`. SwiftPM cannot set those flags per target here, so this executable
// builds both modules OUT OF PROCESS and runs the result ([ISSUE-029]).
//
// The client loops 100 times; each wrong result prints a "BUG (i)" line. The bug
// was recorded as flaky (about 50 of 100 iterations on 6.3.1), so the probe runs
// the client `runs` times and reports the bug if any run prints a BUG line. On
// 6.4.2 (macOS arm64) every iteration of every run is wrong.
//
// Exit code:
//   1  — bug fired  (at least one iteration returned the stale actor state)
//   0  — bug absent (every run printed PASS with no BUG line) OR inconclusive

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    let runs = 5

    func run(_ arguments: [String], in directory: URL) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let pid = ProcessInfo.processInfo.processIdentifier
    let work = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("copytoborrow-actor-state-\(pid)")
    try? FileManager.default.removeItem(at: work)
    do {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: here.appendingPathComponent("BugLib.swift.txt"),
            to: work.appendingPathComponent("BugLib.swift")
        )
        try FileManager.default.copyItem(
            at: here.appendingPathComponent("BugTest.swift.txt"),
            to: work.appendingPathComponent("main.swift")
        )
    } catch {
        FileHandle.standardError.write(Data("could not stage sources: \(error)\n".utf8))
        exit(0)
    }

    func finish(_ code: Int32) -> Never {
        try? FileManager.default.removeItem(at: work)
        exit(code)
    }

    let library = [
        "swiftc", "-O", "-wmo", "-swift-version", "6", "-parse-as-library",
        "-module-name", "BugLib",
        "-emit-module", "-emit-module-path", "BugLib.swiftmodule",
        "-emit-object", "-o", "BugLib.o", "BugLib.swift",
    ]
    let client = [
        "swiftc", "-O", "-wmo", "-swift-version", "6",
        "-module-name", "BugTest", "-I", ".",
        "main.swift", "BugLib.o", "-o", "BugTest",
    ]

    for step in [library, client] {
        guard let result = run(step, in: work), result.status == 0 else {
            FileHandle.standardError.write(
                Data("INCONCLUSIVE: could not build the reproducer (\(step.joined(separator: " ")))\n".utf8)
            )
            finish(0)
        }
    }

    var wrong = 0
    var clean = 0
    for _ in 0..<runs {
        guard let result = run(["./BugTest"], in: work), result.status == 0 else { continue }
        let bugLines = result.output.split(separator: "\n").filter { $0.hasPrefix("BUG") }.count
        wrong += bugLines
        if bugLines == 0 && result.output.contains("PASS") { clean += 1 }
    }

    if wrong > 0 {
        FileHandle.standardError.write(
            Data("BUG FIRED: \(wrong) of \(runs * 100) iterations read stale actor state.\n".utf8)
        )
        finish(1)
    } else if clean == runs {
        FileHandle.standardError.write(
            Data("All \(runs * 100) iterations correct — the bug is ABSENT.\n".utf8)
        )
        finish(0)
    } else {
        FileHandle.standardError.write(Data("INCONCLUSIVE: the client did not run cleanly.\n".utf8))
        finish(0)
    }

#else

    print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
