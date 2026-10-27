// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// SendNonSendable crash on an IIFE around a borrowing @_lifetime init — standalone exit-code probe.
//
// `Crash.swift.txt` aborts the compiler, so it cannot be a compiled target.
// This executable stages `ReproLib.swift.txt` as its own module, then compiles
// `Crash.swift.txt` against it, both OUT OF PROCESS ([ISSUE-029]).
//
// Exit code:
//   1  — bug fired  (swiftc aborted in the "SendNonSendable" pass)
//   0  — bug absent (the caller compiled) OR inconclusive (could not probe)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let librarySource = here.appendingPathComponent("ReproLib.swift.txt")
    let crashSource = here.appendingPathComponent("Crash.swift.txt")

    func probe() -> Int32 {
        let pid = ProcessInfo.processInfo.processIdentifier
        let stage = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sendnonsendable-iife-\(pid)")
        try? FileManager.default.removeItem(at: stage)
        do {
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: librarySource,
                to: stage.appendingPathComponent("ReproLib.swift")
            )
            try FileManager.default.copyItem(
                at: crashSource,
                to: stage.appendingPathComponent("main.swift")
            )
        } catch {
            FileHandle.standardError.write(Data("could not stage sources: \(error)\n".utf8))
            return 0
        }
        defer { try? FileManager.default.removeItem(at: stage) }

        func swiftc(_ arguments: [String]) -> (status: Int32, errors: String)? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc"] + arguments
            process.currentDirectoryURL = stage
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let errors =
                String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            process.waitUntilExit()
            return (process.terminationStatus, errors)
        }

        // Module 1: the ~Copyable Target and the ~Copyable, ~Escapable View.
        guard
            let library = swiftc([
                "-emit-module", "-parse-as-library",
                "-module-name", "ReproLib",
                "-swift-version", "6",
                "-enable-experimental-feature", "Lifetimes",
                "ReproLib.swift",
                "-emit-module-path", "ReproLib.swiftmodule",
                "-o", "ReproLib.o",
            ]),
            library.status == 0
        else {
            FileHandle.standardError.write(Data("could not build ReproLib; inconclusive\n".utf8))
            return 0
        }

        // Module 2: the caller with the IIFE. Debug is enough.
        guard
            let caller = swiftc([
                "-c",
                "-swift-version", "6",
                "-Onone",
                "-enable-experimental-feature", "Lifetimes",
                "-I", ".",
                "main.swift",
                "-o", "main.o",
            ])
        else {
            FileHandle.standardError.write(Data("could not launch swiftc\n".utf8))
            return 0
        }

        if caller.status != 0 && caller.errors.contains("\"SendNonSendable\"") {
            FileHandle.standardError.write(
                Data("BUG FIRED: swiftc aborted in the SendNonSendable pass.\n".utf8)
            )
            return 1
        } else if caller.status == 0 {
            FileHandle.standardError.write(
                Data("The caller compiled cleanly — the bug is FIXED.\n".utf8)
            )
            return 0
        } else {
            FileHandle.standardError.write(
                Data("swiftc output did not match either signature:\n\(caller.errors)\n".utf8)
            )
            return 0
        }
    }

    exit(probe())

#else

    print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
