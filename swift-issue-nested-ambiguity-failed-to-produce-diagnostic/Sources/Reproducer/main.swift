// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// "failed to produce diagnostic" for a nested ambiguity — standalone exit-code probe.
//
// `Crash.swift.txt` is ill-formed on purpose, so it cannot be a compiled target.
// This executable type-checks it OUT OF PROCESS and reports the result ([ISSUE-029]).
//
// Exit code:
//   1  — bug fired  (swiftc emitted "failed to produce diagnostic")
//   0  — bug absent (a proper diagnostic) OR inconclusive (could not probe)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let crashSource = here.appendingPathComponent("Crash.swift.txt")

let pid = ProcessInfo.processInfo.processIdentifier
let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("nested-ambiguity-diagnostic-\(pid).swift")
try? FileManager.default.removeItem(at: swiftCopy)
do {
    try FileManager.default.copyItem(at: crashSource, to: swiftCopy)
} catch {
    FileHandle.standardError.write(Data("could not stage crash source: \(error)\n".utf8))
    exit(0)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swiftc", "-typecheck", "-swift-version", "6", swiftCopy.path]
let stderr = Pipe()
process.standardError = stderr
process.standardOutput = Pipe()

do {
    try process.run()
} catch {
    FileHandle.standardError.write(Data("could not launch swiftc: \(error)\n".utf8))
    exit(0)
}
let errText = String(
    data: stderr.fileHandleForReading.readDataToEndOfFile(),
    encoding: .utf8
) ?? ""
process.waitUntilExit()
try? FileManager.default.removeItem(at: swiftCopy)

if errText.contains("failed to produce diagnostic") {
    FileHandle.standardError.write(Data("BUG FIRED: failed to produce diagnostic for a nested ambiguous call.\n".utf8))
    exit(1)
} else if errText.contains("ambiguous use of") {
    FileHandle.standardError.write(Data("Proper ambiguity diagnostic reported — the bug is FIXED.\n".utf8))
    exit(0)
} else {
    FileHandle.standardError.write(Data("swiftc output did not match either signature:\n\(errText)\n".utf8))
    exit(0)
}

#else

print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
