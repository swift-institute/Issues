// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Parameterized-typealias × parameterized-protocol opaque-return ICE —
// standalone exit-code canary.
//
// The in-cohort bug is a "failed to produce diagnostic for expression" ICE on
// Swift 6.3.2 test-target compilation. The single-file shape retained as
// `Crash.swift.txt` captures the identified trigger surface (parameterized
// protocol with 3 primary associated types, parameterized typealias for a
// generic instantiation, Base-constrained extension, `some P<I, O, F>` opaque
// return) but has NEVER reproduced the ICE standalone — the in-cohort case is
// the canonical reference (see the README). This probe therefore acts as a
// CANARY: it compiles the shape out of process and reports whether the ICE
// signature appears.
//
// Exit code:
//   1  — ICE signature appeared ("failed to produce diagnostic")
//   0  — compiled cleanly (the standalone status quo) OR inconclusive

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let crashSource = here.appendingPathComponent("Crash.swift.txt")

let pid = ProcessInfo.processInfo.processIdentifier
let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("parameterized-typealias-ice-\(pid).swift")
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("parameterized-typealias-ice-\(pid).out")
try? FileManager.default.removeItem(at: swiftCopy)
do {
    try FileManager.default.copyItem(at: crashSource, to: swiftCopy)
} catch {
    FileHandle.standardError.write(Data("could not stage source: \(error)\n".utf8))
    exit(0)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swiftc", swiftCopy.path, "-o", tmp.path]
let stderr = Pipe()
process.standardError = stderr
process.standardOutput = Pipe()

do {
    try process.run()
} catch {
    FileHandle.standardError.write(Data("could not launch swiftc: \(error)\n".utf8))
    exit(0)
}
process.waitUntilExit()

let errText = String(
    data: stderr.fileHandleForReading.readDataToEndOfFile(),
    encoding: .utf8
) ?? ""

try? FileManager.default.removeItem(at: tmp)
try? FileManager.default.removeItem(at: swiftCopy)

if errText.contains("failed to produce diagnostic") {
    FileHandle.standardError.write(Data("ICE SIGNATURE: failed to produce diagnostic for expression.\n".utf8))
    exit(1)
} else if process.terminationStatus != 0 {
    FileHandle.standardError.write(Data("swiftc failed for an unrelated reason:\n\(errText)\n".utf8))
    exit(0)
} else {
    FileHandle.standardError.write(Data("standalone shape compiled cleanly (status quo on every tested toolchain).\n".utf8))
    exit(0)
}

#else
exit(0)
#endif

// swiftlint:enable no_try_optional
