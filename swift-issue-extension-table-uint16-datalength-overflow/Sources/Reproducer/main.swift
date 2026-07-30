// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// swiftlang/swift#90319 — standalone exit-code reproducer for the
// `ExtensionTableInfo::EmitKeyDataLength` uint16 `dataLength` overflow.
//
// The bug has two manifestations of one defect (Serialization.cpp:239):
//   • ASSERTS toolchain : `swiftc -emit-module` ABORTS (signal 6) in EmitKeyDataLength.
//   • RELEASE toolchain : `swiftc -emit-module` SUCCEEDS but truncates the extension
//                         table; a consumer then cannot resolve many articles.
//
// Neither manifestation can be a normal SwiftPM compiled target (the asserts one
// aborts the build), so this executable drives the compiler OUT OF PROCESS against
// the `Crash.swift.txt` resource and reports via exit code.
//
// Exit code:
//   1  — bug fired  (emit aborted in EmitKeyDataLength, OR the consumer could not
//                    resolve a high-numbered article against a silently-truncated module)
//   0  — bug absent (emit succeeded AND the consumer resolved every article) OR inconclusive

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let moduleName = "Burgerlijk_Wetboek_Boek_2"

func run(_ args: [String]) -> (Int32?, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    let err = Pipe()
    process.standardError = err
    process.standardOutput = Pipe()
    do { try process.run() } catch { return (nil, "") }
    process.waitUntilExit()
    let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, text)
}

func stderrWrite(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }

let crashSource = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Crash.swift.txt")

let pid = ProcessInfo.processInfo.processIdentifier
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
let staged = tmp.appendingPathComponent("exttable-repro-\(pid).swift")
let moduleDir = tmp.appendingPathComponent("exttable-mod-\(pid)", isDirectory: true)
try? FileManager.default.removeItem(at: staged)
try? FileManager.default.removeItem(at: moduleDir)
try? FileManager.default.createDirectory(at: moduleDir, withIntermediateDirectories: true)
do {
    try FileManager.default.copyItem(at: crashSource, to: staged)
} catch {
    stderrWrite("could not stage crash source: \(error)\n")
    exit(0)
}
defer {
    try? FileManager.default.removeItem(at: staged)
    try? FileManager.default.removeItem(at: moduleDir)
}

// Step 1 — emit the module.
let modulePath = moduleDir.appendingPathComponent("\(moduleName).swiftmodule").path
let (emitStatus, emitErr) = run([
    "swiftc", "-emit-module", "-module-name", moduleName, "-o", modulePath, staged.path,
])
guard let emitStatus else {
    stderrWrite("could not launch swiftc; inconclusive\n")
    exit(0)
}

if emitErr.contains("EmitKeyDataLength") || emitErr.contains("dataLength == static_cast<uint16_t>") {
    stderrWrite("BUG FIRED (asserts): EmitKeyDataLength uint16 dataLength assertion at emit.\n")
    exit(1)
}
if emitStatus != 0 {
    stderrWrite("swiftc -emit-module failed for an unrelated reason:\n\(emitErr)\n")
    exit(0)
}

// Step 2 — release path: emit succeeded; a truncated table drops articles.
let consumer = tmp.appendingPathComponent("exttable-consumer-\(pid).swift")
let consumerSource = """
import \(moduleName)
let _ = `Burgerlijk Wetboek`.`2`.`Artikel 999`.self
"""
try? consumerSource.write(to: consumer, atomically: true, encoding: .utf8)
defer { try? FileManager.default.removeItem(at: consumer) }

let (consumerStatus, consumerErr) = run(["swiftc", "-typecheck", "-I", moduleDir.path, consumer.path])
guard let consumerStatus else {
    stderrWrite("could not launch consumer typecheck; inconclusive\n")
    exit(0)
}
if consumerErr.contains("has no member 'Artikel") || consumerErr.contains("is not a member type") {
    stderrWrite("BUG FIRED (release): silently-truncated extension table — consumer cannot resolve `Artikel 999`.\n")
    exit(1)
}
if consumerStatus == 0 {
    stderrWrite("emit + consumer both clean — the bug appears FIXED.\n")
    exit(0)
}
stderrWrite("consumer typecheck failed for an unrelated reason:\n\(consumerErr)\n")
exit(0)

#else

print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
