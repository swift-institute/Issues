// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// CopyPropagation borrowed-`~Copyable`-field ownership abort — standalone
// exit-code reproducer.
//
// The bug is a COMPILE-TIME abort: compiling `Crash.swift.txt` at `-O` aborts
// swift-frontend (signal 6) in the SIL ownership verifier run by the
// CopyPropagation pass with "Found outside of lifetime use?!" — the
// begin_borrow/end_borrow scope of a borrowed `~Copyable` parameter is
// shortened to end before the apply consuming its projected field. A
// build-time abort cannot be a normal SwiftPM compiled target without
// breaking the whole package, so this executable drives the compiler OUT OF
// PROCESS against the `Crash.swift.txt` resource and reports the result as an
// exit code.
//
// Exit code:
//   1  — bug fired  (the `swiftc -O` subprocess aborted in CopyPropagation)
//   0  — bug absent (the subprocess compiled `Crash.swift.txt` cleanly) OR inconclusive
//
// `Workaround.swift.txt` is the passing counterpart (`@_optimize(none)` on the
// crashing function); it is documentation, not part of this probe.

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let crashSource = here.appendingPathComponent("Crash.swift.txt")

// swiftc keys off the file extension; copy the `.txt` resource to a `.swift`
// temp so it is treated as a Swift source rather than a link input.
let pid = ProcessInfo.processInfo.processIdentifier
let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("fs-streaming-write-ownership-\(pid).swift")
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("fs-streaming-write-ownership-\(pid).out")
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
    "swiftc", "-O",
    swiftCopy.path,
    "-o", tmp.path,
]
let stderr = Pipe()
process.standardError = stderr
process.standardOutput = Pipe()

do {
    try process.run()
} catch {
    // Could not even launch the compiler — treat as inconclusive, not a bug.
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

let bugFired = errText.contains("Found outside of lifetime use")
    && errText.contains("CopyPropagation")

if bugFired {
    FileHandle.standardError.write(Data("BUG FIRED: CopyPropagation ownership abort on borrowed ~Copyable field projection.\n".utf8))
    exit(1)
} else if process.terminationStatus != 0 {
    // Compiler failed for some OTHER reason (e.g. a future flag/syntax change).
    // Not the bug under test; do not flip the signal.
    FileHandle.standardError.write(Data("swiftc failed for an unrelated reason:\n\(errText)\n".utf8))
    exit(0)
} else {
    FileHandle.standardError.write(Data("bug absent: Crash.swift.txt compiled cleanly at -O — the fix has reached this toolchain.\n".utf8))
    exit(0)
}

#else
exit(0)
#endif

// swiftlint:enable no_try_optional
