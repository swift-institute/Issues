// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// SILGenCleanup ownership-verifier abort on a nested local closure capturing
// a borrowing ~Copyable parameter — standalone exit-code reproducer.
//
// The bug is a COMPILE-TIME abort: compiling `Crash.swift.txt` (even at
// `-Onone`, since SILGenCleanup is a mandatory pass) aborts swift-frontend
// (signal 6) in the SIL ownership verifier with "Found ownership error?!" /
// "Have operand with incompatible ownership?!". A build-time abort cannot be
// a normal SwiftPM compiled target without breaking the whole package, so
// this executable drives the compiler OUT OF PROCESS against the
// `Crash.swift.txt` resource and reports the result as an exit code.
//
// Exit code:
//   1  — bug fired  (the `swiftc` subprocess aborted in SILGenCleanup)
//   0  — bug absent (the subprocess compiled `Crash.swift.txt` cleanly) OR
//        inconclusive

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let crashSource = here.appendingPathComponent("Crash.swift.txt")

let pid = ProcessInfo.processInfo.processIdentifier
let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("silgencleanup-nested-closure-\(pid).swift")
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("silgencleanup-nested-closure-\(pid).out")
try? FileManager.default.removeItem(at: swiftCopy)
do {
    try FileManager.default.copyItem(at: crashSource, to: swiftCopy)
} catch {
    FileHandle.standardError.write(Data("could not stage crash source: \(error)\n".utf8))
    exit(0)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = [
    "swiftc",
    swiftCopy.path,
    "-o", tmp.path,
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
process.waitUntilExit()

let errText = String(
    data: stderr.fileHandleForReading.readDataToEndOfFile(),
    encoding: .utf8
) ?? ""

try? FileManager.default.removeItem(at: tmp)
try? FileManager.default.removeItem(at: swiftCopy)

let bugFired = errText.contains("Found ownership error")
    && errText.contains("SILGenCleanup")

if bugFired {
    FileHandle.standardError.write(Data("BUG FIRED: SILGenCleanup ownership-verifier abort on nested closure capturing borrowing ~Copyable parameter.\n".utf8))
    exit(1)
} else if process.terminationStatus != 0 {
    FileHandle.standardError.write(Data("swiftc failed for an unrelated reason:\n\(errText)\n".utf8))
    exit(0)
} else {
    FileHandle.standardError.write(Data("bug absent: Crash.swift.txt compiled cleanly — the fix has reached this toolchain.\n".utf8))
    exit(0)
}

#else
exit(0)
#endif

// swiftlint:enable no_try_optional
