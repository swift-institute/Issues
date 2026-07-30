// This probe stages/compiles/runs/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Standalone exit-code probe for the function-typed `@TaskLocal` null-metadata
// defect.
//
// A `@TaskLocal` whose value type is a FUNCTION type makes the optimizer emit a
// lowered (`ImplFunctionType` + pattern substitutions) mangled name through the
// CONCRETE metadata-instantiation entry point. Instantiation returns null, and
// `swift_task_localValuePush` faults reading the value witness table at
// `metadata - 8` (`0xfffffffffffffff8`).
//
// The bug crashes the PRODUCED BINARY, not the compiler — but an in-process
// trigger would take the whole test runner down with SIGSEGV, so the trigger
// ships as `Crash.swift.txt` and is compiled AND run OUT OF PROCESS here, with
// `-O` forced regardless of how this probe itself was built.
//
//   exit 1 — the bug FIRES (expected on 6.3.3, every platform)
//   exit 0 — the probe binary ran to completion on every attempt: the fix has
//            reached this toolchain (expected on 6.4 and later)
//   exit 2 — inconclusive (no reachable compiler, or an unrelated failure)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation

// Measured deterministic (5/5 aborts on 6.3.3 macOS arm64; every Linux
// invocation aborted). Retried anyway so that a single anomalous clean run
// cannot announce a fix that has not landed.
let attempts = 3

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let crashSource = here.appendingPathComponent("Crash.swift.txt")

func inconclusive(_ reason: String) -> Never {
    FileHandle.standardError.write(Data("inconclusive: \(reason)\n".utf8))
    exit(2)
}

guard FileManager.default.fileExists(atPath: crashSource.path)
else { inconclusive("trigger resource not found next to \(#filePath)") }

let pid = ProcessInfo.processInfo.processIdentifier
let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("tasklocal-function-value-null-metadata-probe-\(pid)")
try? FileManager.default.removeItem(at: work)
guard (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil
else { inconclusive("could not create a scratch directory") }
defer { try? FileManager.default.removeItem(at: work) }

// Top-level code: the trigger must be staged as `main.swift`.
let staged = work.appendingPathComponent("main.swift")
guard (try? FileManager.default.copyItem(at: crashSource, to: staged)) != nil
else { inconclusive("could not stage the trigger source as main.swift") }

let binary = work.appendingPathComponent("probe")

func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, signalled: Bool, stderr: String)? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.currentDirectoryURL = work
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = Pipe()
    do { try process.run() } catch { return nil }
    let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()
    return (process.terminationStatus, process.terminationReason == .uncaughtSignal, text)
}

guard let build = run("/usr/bin/env", ["swiftc", "-O", "-swift-version", "6", "main.swift", "-o", "probe"])
else { inconclusive("could not launch swiftc") }
guard build.status == 0 else {
    inconclusive("the trigger source did not compile:\n\(build.stderr)")
}

var sawUnrelatedFailure = ""
for _ in 0..<attempts {
    guard let outcome = run(binary.path, []) else { inconclusive("could not launch the probe binary") }
    if outcome.signalled, outcome.status == SIGSEGV {
        FileHandle.standardError.write(Data(
            "BUG FIRES: the probe binary died with SIGSEGV in swift_task_localValuePush.\n".utf8
        ))
        exit(1)
    }
    if outcome.status != 0 { sawUnrelatedFailure = outcome.stderr }
}

if sawUnrelatedFailure.isEmpty {
    print("bug appears FIXED: the probe binary ran to completion on \(attempts) attempts.")
    exit(0)
}
inconclusive("the probe binary failed for an unrelated reason:\n\(sawUnrelatedFailure)")
#else
exit(2)
#endif

// swiftlint:enable no_try_optional
