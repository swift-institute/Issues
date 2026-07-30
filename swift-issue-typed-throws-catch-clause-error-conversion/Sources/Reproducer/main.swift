// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Standalone exit-code probe for the typed-throws catch-clause error-conversion
// SILGen defect.
//
// Compiling `Crash.swift.txt` aborts swift-frontend during SILGen of `g()` on
// every toolchain tested; on 6.5-dev `main` it instead emits a hard
// "INTERNAL ERROR: feature not implemented: throw conversion" diagnostic. Both
// outcomes are the same defect and both count as FIRING — the program is not
// compilable either way.
//
// A build-time abort cannot be a normal SwiftPM compiled target without
// breaking the whole package, so the trigger ships as a `.txt` resource and is
// compiled OUT OF PROCESS here.
//
//   exit 1 — the bug FIRES (expected on every toolchain tested so far)
//   exit 0 — `Crash.swift.txt` compiled cleanly on every attempt: the fix has
//            reached this toolchain
//   exit 2 — inconclusive (no reachable compiler, or an unrelated failure)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation

// On 6.3.3-RELEASE the failure is a bad pointer dereference in a NoAsserts
// build, so it is undefined behaviour and survives roughly one attempt in ten
// (measured 11/12 aborts, macOS arm64, 2026-07-30). Every assertions-enabled
// toolchain and Apple Swift 6.4 abort deterministically. Retrying keeps the
// "fix landed" verdict from being announced by a single lucky run.
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
    .appendingPathComponent("typed-throws-catch-conversion-probe-\(pid)")
try? FileManager.default.removeItem(at: work)
guard (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil
else { inconclusive("could not create a scratch directory") }
defer { try? FileManager.default.removeItem(at: work) }

let staged = work.appendingPathComponent("Crash.swift")
guard (try? FileManager.default.copyItem(at: crashSource, to: staged)) != nil
else { inconclusive("could not stage the trigger source as .swift") }

func compile() -> (status: Int32, stderr: String)? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "swiftc", "-swift-version", "6", "-parse-as-library",
        "-c", "Crash.swift", "-o", "Crash.o",
    ]
    process.currentDirectoryURL = work
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = Pipe()
    do { try process.run() } catch { return nil }
    let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()
    return (process.terminationStatus, text)
}

var lastFailure = ""
for _ in 0..<attempts {
    guard let result = compile() else { inconclusive("could not launch swiftc") }
    guard result.status != 0 else { continue }
    if result.stderr.contains("INTERNAL ERROR: feature not implemented: throw conversion")
        || result.stderr.contains("While silgen") {
        FileHandle.standardError.write(Data(
            "BUG FIRES: swiftc rejected or crashed on the typed-throws catch-clause conversion.\n".utf8
        ))
        exit(1)
    }
    lastFailure = result.stderr
}

if lastFailure.isEmpty {
    print("bug appears FIXED: Crash.swift.txt compiled cleanly on \(attempts) attempts.")
    exit(0)
}
inconclusive("swiftc failed for an unrelated reason:\n\(lastFailure)")
#else
exit(2)
#endif

// swiftlint:enable no_try_optional
