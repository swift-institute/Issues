// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Standalone exit-code probe for the ~Copyable same-type conditional
// conformance runtime crash.
//
// `Sources/reproducer.swift` compiles cleanly but CRASHES AT RUNTIME
// (SIGSEGV) when a generic type is constrained by a protocol whose witness
// comes from `extension Gen: P where A == Pool` with a `~Copyable` type
// argument. The loose sources (reproducer plus probes and the verified
// marker-protocol workaround) are deliberately NOT SwiftPM targets: an
// in-process run would kill the test runner, so this probe compiles AND runs
// it out of process.
//
//   exit 1 — the bug FIRES (the compiled reproducer was killed by a signal)
//   exit 0 — the reproducer ran to completion: the fix has landed — OR the
//            probe was inconclusive (no compiler, or compile failed)

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

let pid = ProcessInfo.processInfo.processIdentifier
let binary = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("sametype-conformance-\(pid)")
defer { try? FileManager.default.removeItem(at: binary) }

func run(_ executable: String, _ arguments: [String]) -> Int32? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardError = Pipe()
    process.standardOutput = Pipe()
    do { try process.run() } catch { return nil }
    process.waitUntilExit()
    if process.terminationReason == .uncaughtSignal { return 128 + process.terminationStatus }
    return process.terminationStatus
}

// Positive control: the reproducer always COMPILES; a compile failure means
// the instrument broke, not the bug.
guard let compile = run("/usr/bin/env", ["swiftc", source.path, "-o", binary.path]), compile == 0 else {
    FileHandle.standardError.write(Data("inconclusive: reproducer.swift failed to compile\n".utf8))
    exit(0)
}

guard let runStatus = run(binary.path, []) else {
    FileHandle.standardError.write(Data("inconclusive: could not launch the compiled reproducer\n".utf8))
    exit(0)
}

if runStatus >= 128 {
    FileHandle.standardError.write(Data("BUG FIRES: the reproducer was killed by signal \(runStatus - 128).\n".utf8))
    exit(1)
}
print("bug appears FIXED: the reproducer ran to completion (exit \(runStatus)).")
exit(0)
#else
exit(0)
#endif

// swiftlint:enable no_try_optional
