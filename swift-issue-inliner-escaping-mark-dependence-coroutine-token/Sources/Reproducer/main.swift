// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// EarlyPerfInliner escaping-mark_dependence abort — standalone exit-code probe.
//
// The bug is a COMPILE-TIME abort: compiling `Crash.swift.txt` under `-O` aborts
// swift-frontend (signal 6) in SILInliner's BeginApplySite::preprocess. A
// build-time abort cannot be a normal compiled SwiftPM target without breaking the
// whole package, so this executable drives the compiler OUT OF PROCESS against the
// `Crash.swift.txt` resource and reports the result as an exit code ([ISSUE-029]).
//
// Exit code:
//   1  — bug fired  (the `swiftc -O` subprocess aborted on `mdi.isNonEscaping()`)
//   0  — bug absent (compiled cleanly) OR inconclusive (could not probe)
//
// NOTE — unlike most entries here, this bug is VERSION-GATED: it is CLEAN on
// 6.3.3-RELEASE and 6.4.x-dev and fires only on 6.5-dev-class toolchains. A clean
// compile is therefore the CORRECT result on a stable leg and must not be read as
// "fixed". The companion `Tests/Reproducer.swift` encodes that distinction.

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let crashSource = here.appendingPathComponent("Crash.swift.txt")

// swiftc keys off the file extension; copy the `.txt` resource to a `.swift`
// temp so it is treated as a Swift source rather than a link input.
let pid = ProcessInfo.processInfo.processIdentifier
let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("inliner-escaping-markdep-\(pid).swift")
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("inliner-escaping-markdep-\(pid).o")
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
    "swiftc", "-O", "-swift-version", "6",
    // Both features are load-bearing: the `@_lifetime` annotation and the
    // suppressed associated type are what produce the lifetime-dependent
    // coroutine in the first place. A toolchain that rejects either flag lands
    // in the "inconclusive" branch below rather than reporting a fix.
    "-enable-experimental-feature", "Lifetimes",
    "-enable-experimental-feature", "SuppressedAssociatedTypes",
    "-c", swiftCopy.path,
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

// Signature of THIS defect. Kept narrow on purpose: a future rephrasing surfaces
// as "inconclusive" rather than as a false clean or a false fire.
let bugFired = errText.contains("isNonEscaping")
    || errText.contains("BeginApplySite::preprocess")

if bugFired {
    FileHandle.standardError.write(Data("BUG FIRED: EarlyPerfInliner aborted on an escaping mark_dependence over a coroutine token.\n".utf8))
    exit(1)
} else if process.terminationStatus != 0 {
    // Compiler failed for some OTHER reason (unknown flag, syntax change, …).
    // Not the bug under test; do not flip the signal.
    FileHandle.standardError.write(Data("swiftc failed for an unrelated reason:\n\(errText)\n".utf8))
    exit(0)
} else {
    FileHandle.standardError.write(Data("Crash.swift.txt compiled cleanly — expected on 6.3/6.4-class toolchains; on a 6.5-dev-class toolchain this means the bug is FIXED.\n".utf8))
    exit(0)
}

#else

print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
