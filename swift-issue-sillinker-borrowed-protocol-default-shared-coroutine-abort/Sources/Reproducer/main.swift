// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Standalone exit-code probe for swiftlang/swift#90406.
//
// Mirrors the Swift Testing harness in ../../Tests/Reproducer.swift without the
// test framework, so the defect can be probed anywhere a compiler is reachable.
//
//   exit 1 — the bug FIRES (expected on every toolchain tested so far)
//   exit 0 — the importing module compiled cleanly: the fix has landed
//   exit 2 — inconclusive (no reachable compiler, or the DEFINING module failed,
//            which means the environment is at fault and nothing was proved)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let libSource = root.appendingPathComponent("LibA.swift.txt")
let consumerSource = root.appendingPathComponent("Consumer.swift.txt")

func inconclusive(_ reason: String) -> Never {
    FileHandle.standardError.write(Data("inconclusive: \(reason)\n".utf8))
    exit(2)
}

guard FileManager.default.fileExists(atPath: libSource.path),
      FileManager.default.fileExists(atPath: consumerSource.path)
else { inconclusive("trigger resources not found next to \(#filePath)") }

let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("sillinker-borrowed-default-probe-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.removeItem(at: work)
guard (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil
else { inconclusive("could not create a scratch directory") }
defer { try? FileManager.default.removeItem(at: work) }

let lib = work.appendingPathComponent("LibA.swift")
let consumer = work.appendingPathComponent("Consumer.swift")
guard (try? FileManager.default.copyItem(at: libSource, to: lib)) != nil,
      (try? FileManager.default.copyItem(at: consumerSource, to: consumer)) != nil
else { inconclusive("could not stage the trigger sources as .swift") }

func swiftc(_ arguments: [String]) -> (status: Int32, stderr: String)? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftc"] + arguments
    process.currentDirectoryURL = work
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = Pipe()
    do { try process.run() } catch { return nil }
    let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()
    return (process.terminationStatus, text)
}

// Positive control: the defining module always compiles. A failure here means the
// instrument, not the compiler under test, is what broke.
guard let defining = swiftc([
    "-emit-module", "-emit-library", "-module-name", "LibA", "LibA.swift",
]) else { inconclusive("could not launch swiftc") }
guard defining.status == 0 else {
    inconclusive("the defining module failed to build:\n\(defining.stderr)")
}

guard let importing = swiftc(["-c", "-I", ".", "Consumer.swift"]) else {
    inconclusive("could not launch swiftc for the importing module")
}

if importing.stderr.contains("cannot deserialize shared function")
    || importing.stderr.contains("shared function must have a body") {
    FileHandle.standardError.write(Data(
        "swiftlang/swift#90406 FIRES: the importing module aborted.\n".utf8
    ))
    exit(1)
}
if importing.status == 0 {
    print("swiftlang/swift#90406 appears FIXED: the importing module compiled cleanly.")
    exit(0)
}
inconclusive("the importing module failed for an unrelated reason:\n\(importing.stderr)")
#else
exit(2)
#endif

// swiftlint:enable no_try_optional
