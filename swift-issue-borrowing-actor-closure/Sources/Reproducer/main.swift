// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let crashSource = here.appendingPathComponent("Crash.swift.txt")
let identifier = ProcessInfo.processInfo.processIdentifier
let stagedSource = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("borrowing-actor-closure-\(identifier).swift")
let objectFile = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("borrowing-actor-closure-\(identifier).o")

defer {
    try? FileManager.default.removeItem(at: stagedSource)
    try? FileManager.default.removeItem(at: objectFile)
}

do {
    try FileManager.default.copyItem(at: crashSource, to: stagedSource)
} catch {
    FileHandle.standardError.write(Data("could not stage reproducer: \(error)\n".utf8))
    exit(0)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = [
    "swiftc", "-parse-as-library", "-swift-version", "6", "-c",
    stagedSource.path,
    "-o", objectFile.path,
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
let output = String(
    data: stderr.fileHandleForReading.readDataToEndOfFile(),
    encoding: .utf8
) ?? ""

let bugFired = output.contains("MoveOnlyTypeEliminator")
    || output.contains("Unhandled SIL Instruction")

if bugFired {
    FileHandle.standardError.write(Data("BUG FIRED: MoveOnlyTypeEliminator crashed.\n".utf8))
    exit(1)
}

if process.terminationStatus != 0 {
    FileHandle.standardError.write(Data("swiftc failed for an unrelated reason:\n\(output)\n".utf8))
}

exit(0)

#else

print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
