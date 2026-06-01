// swiftlang/swift (PENDING filing) — standalone exit-code reproducer.
//
// The bug is a COMPILE-TIME abort: compiling `Crash.swift.txt` under `-O`
// aborts swift-frontend (signal 6) with an LLVM verifier "Instruction does
// not dominate all uses" on a `~Copyable` value witness. A build-time abort
// cannot be a normal SwiftPM compiled target without breaking the whole
// package, so this executable drives the compiler OUT OF PROCESS against the
// `Crash.swift.txt` resource and reports the result as an exit code.
//
// Exit code:
//   1  — bug fired  (the `swiftc -O` subprocess aborted with the verifier error)
//   0  — bug absent (the subprocess compiled `Crash.swift.txt` cleanly)
//
// The companion `Tests/Reproducer.swift` wraps the same probe in
// `withKnownIssue` so CI flips red the moment the upstream fix lands.

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let crashSource = here.appendingPathComponent("Crash.swift.txt")

// swiftc keys off the file extension; copy the `.txt` resource to a `.swift`
// temp so it is treated as a Swift source rather than a link input.
let pid = ProcessInfo.processInfo.processIdentifier
let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("rawlayout-trailing-\(pid).swift")
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("rawlayout-trailing-\(pid).out")
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
    "-enable-experimental-feature", "RawLayout",
    "-enable-experimental-feature", "ValueGenerics",
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

let bugFired = errText.contains("does not dominate all uses")
    || errText.contains("Broken module")

if bugFired {
    FileHandle.standardError.write(Data("BUG FIRED: LLVM verifier rejected the value-witness IR.\n".utf8))
    exit(1)
} else if process.terminationStatus != 0 {
    // Compiler failed for some OTHER reason (e.g. feature flag renamed on a
    // future toolchain). Not the bug under test; do not flip the signal.
    FileHandle.standardError.write(Data("swiftc failed for an unrelated reason:\n\(errText)\n".utf8))
    exit(0)
} else {
    FileHandle.standardError.write(Data("Crash.swift.txt compiled cleanly — the bug appears FIXED.\n".utf8))
    exit(0)
}

#else

// No subprocess facility on this platform; nothing to probe.
print("subprocess probe unavailable on this platform; skipping")

#endif
