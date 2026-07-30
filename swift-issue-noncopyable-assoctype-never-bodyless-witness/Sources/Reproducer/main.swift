// Standalone exit-code probe for the bodyless `shared [serialized]`
// default-witness `read` accessor abort (`~Copyable` associated type bound to
// `Never`, cross-module).
//
// Mirrors the Swift Testing harness in ../../Tests/Reproducer.swift without
// the test framework, so the defect can be probed anywhere a compiler is
// reachable.
//
//   exit 1 — the bug FIRES (expected on every toolchain tested so far)
//   exit 0 — the consumer module compiled cleanly under -sil-verify-all:
//            the fix has landed
//   exit 2 — inconclusive (no reachable compiler, or the DEFINING module
//            failed, which means the environment is at fault and nothing was
//            proved)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let coreSource = root.appendingPathComponent("Core.swift.txt")
let consumerSource = root.appendingPathComponent("Consumer.swift.txt")

func inconclusive(_ reason: String) -> Never {
    FileHandle.standardError.write(Data("inconclusive: \(reason)\n".utf8))
    exit(2)
}

guard FileManager.default.fileExists(atPath: coreSource.path),
      FileManager.default.fileExists(atPath: consumerSource.path)
else { inconclusive("trigger resources not found next to \(#filePath)") }

let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("noncopyable-never-witness-probe-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.removeItem(at: work)
guard (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil
else { inconclusive("could not create a scratch directory") }
defer { try? FileManager.default.removeItem(at: work) }

let core = work.appendingPathComponent("Core.swift")
let consumer = work.appendingPathComponent("Consumer.swift")
guard (try? FileManager.default.copyItem(at: coreSource, to: core)) != nil,
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

// Positive control: the defining module always compiles. A failure here means
// the instrument, not the compiler under test, is what broke.
guard let defining = swiftc([
    "-enable-experimental-feature", "SuppressedAssociatedTypes",
    "-wmo", "-parse-as-library", "-emit-module",
    "-emit-module-path", "M.swiftmodule", "-module-name", "M", "Core.swift",
]) else { inconclusive("could not launch swiftc") }
guard defining.status == 0 else {
    inconclusive("the defining module failed to build:\n\(defining.stderr)")
}

// The consumer module. `-sil-verify-all` stands in for the +Asserts /
// Embedded configurations where verification is on by default; on a NoAsserts
// RELEASE toolchain the malformed SIL is emitted but never verified, so
// without the flag the bug is latent, not absent.
guard let importing = swiftc([
    "-enable-experimental-feature", "SuppressedAssociatedTypes",
    "-Xfrontend", "-sil-verify-all",
    "-wmo", "-parse-as-library", "-c", "Consumer.swift",
    "-I", ".", "-module-name", "N", "-o", "Consumer.o",
]) else {
    inconclusive("could not launch swiftc for the consumer module")
}

if importing.stderr.contains("Must have a construct to emit for")
    || importing.stderr.contains("must have a body") {
    FileHandle.standardError.write(Data(
        "BUG FIRES: the consumer module aborted on the bodyless default witness.\n".utf8
    ))
    exit(1)
}
if importing.status == 0 {
    print("bug appears FIXED: the consumer module compiled cleanly under -sil-verify-all.")
    exit(0)
}
inconclusive("the consumer module failed for an unrelated reason:\n\(importing.stderr)")
#else
exit(2)
#endif
