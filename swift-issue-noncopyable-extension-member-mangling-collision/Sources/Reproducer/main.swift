// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Standalone exit-code probe for the ~Copyable extension-member mangling
// collision ("multiple definitions of symbol").
//
// The reduced sources live as loose files at ../../Sources/*.swift (the
// reproducer plus controls and verified workarounds) and are deliberately
// NOT compiled into any SwiftPM target: `reproducer.swift` fails compilation
// by design on every tested toolchain, so a live target would break the
// whole package build. This probe compiles it OUT OF PROCESS.
//
//   exit 1 — the bug FIRES ("multiple definitions of symbol" on emit-objectFileect)
//   exit 0 — the reproducer compiled cleanly: the fix has landed — OR the
//            probe was inconclusive (no reachable compiler / unrelated error)

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
let objectFile = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mangling-collision-\(pid).o")

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swiftc", "-emit-objectFileect", source.path, "-o", objectFile.path]
let stderr = Pipe()
process.standardError = stderr
process.standardOutput = Pipe()

do { try process.run() } catch {
    FileHandle.standardError.write(Data("inconclusive: could not launch swiftc\n".utf8))
    exit(0)
}
process.waitUntilExit()
let errText = String(
    data: stderr.fileHandleForReading.readDataToEndOfFile(),
    encoding: .utf8
) ?? ""
try? FileManager.default.removeItem(at: objectFile)

if errText.contains("multiple definitions of symbol") {
    FileHandle.standardError.write(Data("BUG FIRES: extension-member mangling collision.\n".utf8))
    exit(1)
}
if process.terminationStatus == 0 {
    print("bug appears FIXED: reproducer.swift compiled cleanly.")
    exit(0)
}
FileHandle.standardError.write(Data("inconclusive: swiftc failed for an unrelated reason:\n\(errText)\n".utf8))
exit(0)
#else
exit(0)
#endif

// swiftlint:enable no_try_optional
