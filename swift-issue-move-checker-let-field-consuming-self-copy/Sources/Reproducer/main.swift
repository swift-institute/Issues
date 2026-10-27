// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// "copy of noncopyable typed value. This is a compiler bug." — standalone exit-code probe.
//
// `Bug.swift.txt` does not compile on affected toolchains, so it cannot be a
// compiled target. This executable compiles it OUT OF PROCESS and reports the
// result ([ISSUE-029]).
//
// Exit code:
//   1  — bug fired  (swiftc emitted "copy of noncopyable typed value")
//   0  — bug absent (the source compiled) OR inconclusive (could not probe)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let bugSource = here.appendingPathComponent("Bug.swift.txt")

    func probe() -> Int32 {
        let pid = ProcessInfo.processInfo.processIdentifier
        let stage = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("move-checker-let-field-\(pid)")
        try? FileManager.default.removeItem(at: stage)
        do {
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: bugSource,
                to: stage.appendingPathComponent("main.swift")
            )
        } catch {
            FileHandle.standardError.write(Data("could not stage bug source: \(error)\n".utf8))
            return 0
        }
        defer { try? FileManager.default.removeItem(at: stage) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swiftc", "-c",
            "-swift-version", "6",
            "-package-name", "Repro",
            "-enable-experimental-feature", "Lifetimes",
            "-enable-experimental-feature", "LifetimeDependence",
            "-enable-experimental-feature", "SuppressedAssociatedTypes",
            "main.swift",
            "-o", "main.o",
        ]
        process.currentDirectoryURL = stage
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            FileHandle.standardError.write(Data("could not launch swiftc: \(error)\n".utf8))
            return 0
        }
        let errText =
            String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        process.waitUntilExit()

        if errText.contains("copy of noncopyable typed value") {
            FileHandle.standardError.write(
                Data("BUG FIRED: copy of noncopyable typed value at the let field forwarded from consuming self.\n".utf8)
            )
            return 1
        } else if process.terminationStatus == 0 {
            FileHandle.standardError.write(
                Data("The source compiled cleanly — the bug is FIXED.\n".utf8)
            )
            return 0
        } else {
            FileHandle.standardError.write(
                Data("swiftc output did not match either signature:\n\(errText)\n".utf8)
            )
            return 0
        }
    }

    exit(probe())

#else

    print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
