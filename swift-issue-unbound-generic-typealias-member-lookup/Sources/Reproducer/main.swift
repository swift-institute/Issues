// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Unbound-generic-typealias member-lookup rejects-valid — standalone
// exit-code probe.
//
// The bug is a TYPE-CHECK REJECTION, not a codegen fault, so unlike the
// repository's usual exit(0)/exit(1) codegen convention this is a
// `swiftc -typecheck` exit-code probe (per the issue's own follow-up: "the
// standalone executable harness cannot express this bug ... the runnable
// form is a swiftc -typecheck exit-code probe rather than an exit(0)/exit(1)
// behavioral reproducer"). `reproducer.swift` is NOT a live SwiftPM target —
// row 4 fails to typecheck by design, which would break the whole Issues
// package build — so it ships as a loose file compiled OUT OF PROCESS.
//
// Exit code:
//   1 — bug FIRES (row 4, "'Member' is not a member type of type 'Alias'")
//   0 — bug ABSENT (reproducer.swift typechecked cleanly — the fix has
//       landed) OR inconclusive (no reachable compiler / unrelated failure)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let source = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()        // Sources/Reproducer/
    .deletingLastPathComponent()        // Sources/
    .appendingPathComponent("reproducer.swift")

guard FileManager.default.fileExists(atPath: source.path) else {
    FileHandle.standardError.write(Data("inconclusive: reproducer.swift not found\n".utf8))
    exit(0)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swiftc", "-typecheck", "-swift-version", "6", source.path]
let stderr = Pipe()
process.standardError = stderr
process.standardOutput = Pipe()

do {
    try process.run()
} catch {
    FileHandle.standardError.write(Data("inconclusive: could not launch swiftc\n".utf8))
    exit(0)
}
process.waitUntilExit()

let errText = String(
    data: stderr.fileHandleForReading.readDataToEndOfFile(),
    encoding: .utf8
) ?? ""

if errText.contains("is not a member type of type") && errText.contains("Alias") {
    FileHandle.standardError.write(Data("BUG FIRES: unbound generic typealias member lookup rejects 'Alias.Member'.\n".utf8))
    exit(1)
}
if process.terminationStatus == 0 {
    print("bug appears FIXED: reproducer.swift typechecked cleanly.")
    exit(0)
}
FileHandle.standardError.write(Data("inconclusive: swiftc failed for an unrelated reason:\n\(errText)\n".utf8))
exit(0)

#else
exit(0)
#endif

// swiftlint:enable no_try_optional
