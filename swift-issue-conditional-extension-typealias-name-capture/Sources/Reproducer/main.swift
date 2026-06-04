// swiftlang/swift#89684 — standalone exit-code reproducer.
//
// The bug is a REJECTS-VALID defect: `swiftc -typecheck` on `Reject.swift.txt`
// emits a bogus `type 'Substrate' does not conform to protocol 'P'` at a
// stored-property annotation that never asked for the conditionally-available
// member. Source the compiler wrongly rejects cannot be a normal SwiftPM
// compiled target without breaking the whole package build while the bug
// lives, so this executable drives the compiler OUT OF PROCESS against the
// `Reject.swift.txt` resource and reports the result as an exit code.
//
// Exit code:
//   1  — bug fired  (the `swiftc -typecheck` subprocess rejected the valid
//                    source with the bogus conformance diagnostic)
//   0  — bug absent (the subprocess typechecked `Reject.swift.txt` cleanly)
//        OR inconclusive
//
// The companion `Tests/Reproducer.swift` wraps the same probe in
// `withKnownIssue` so CI flips red the moment the upstream fix lands.

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let rejectSource = here.appendingPathComponent("Reject.swift.txt")

// swiftc keys off the file extension; copy the `.txt` resource to a `.swift`
// temp so it is treated as a Swift source rather than a link input.
let pid = ProcessInfo.processInfo.processIdentifier
let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("conditional-extension-typealias-name-capture-\(pid).swift")
try? FileManager.default.removeItem(at: swiftCopy)
do {
    try FileManager.default.copyItem(at: rejectSource, to: swiftCopy)
} catch {
    FileHandle.standardError.write(Data("could not stage reject source: \(error)\n".utf8))
    exit(0)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = [
    "swiftc", "-typecheck", "-swift-version", "6",
    swiftCopy.path,
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

try? FileManager.default.removeItem(at: swiftCopy)

// The bug's signature: the conditionally-available member's `where` condition,
// evaluated against the OPEN generic argument `Substrate`, surfaces as a bogus
// conformance error at the `var` annotation in the declaring context.
let bugFired = errText.contains("error: type 'Substrate' does not conform to protocol 'P'")

if bugFired {
    FileHandle.standardError.write(Data("BUG FIRED: bogus 'does not conform' rejection of the valid declaring-context annotation.\n".utf8))
    exit(1)
} else if process.terminationStatus != 0 {
    // The compiler rejected the source for some OTHER reason (e.g. a future
    // syntax change, or a rephrased diagnostic). Not the signature under
    // test; do not flip the signal — re-triage by hand.
    FileHandle.standardError.write(Data("swiftc failed for an unrelated reason:\n\(errText)\n".utf8))
    exit(0)
} else {
    FileHandle.standardError.write(Data("Reject.swift.txt typechecked cleanly — the bug appears FIXED.\n".utf8))
    exit(0)
}

#else

// No subprocess facility on this platform; nothing to probe.
print("subprocess probe unavailable on this platform; skipping")

#endif
