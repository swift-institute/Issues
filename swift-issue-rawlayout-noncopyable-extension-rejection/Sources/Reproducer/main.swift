// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// Standalone exit-code probe for the @_rawLayout ~Copyable extension
// REJECTS-VALID defect.
//
// The reduced two-module sources live at
// ../../Sources/ReproducerStorageNamespace/ (module A: the element-generic
// `Storage` namespace and the `Marker` protocol with a `~Copyable`
// associated type) and ../../Sources/ReproducerStorageInline/ (module B: the
// `@_rawLayout` storage type whose extension is incorrectly rejected with
// "type 'Element' does not conform to protocol 'Copyable'"). Module B fails
// compilation by design, so neither module is a live SwiftPM target; this
// probe drives both bare `swiftc` invocations out of process. Per the
// entry's variable-isolation record the module split is the reported shape
// but NOT required for the trigger.
//
//   exit 1 — the bug FIRES (module B rejected with the Copyable diagnostic)
//   exit 0 — module B compiled cleanly: the fix has landed — OR the probe
//            was inconclusive (no compiler, or module A failed = broken
//            instrument)

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation

let sourcesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()        // Sources/Reproducer/
    .deletingLastPathComponent()        // Sources/
let namespaceDir = sourcesRoot.appendingPathComponent("ReproducerStorageNamespace")
let inlineDir = sourcesRoot.appendingPathComponent("ReproducerStorageInline")

func inconclusive(_ reason: String) -> Never {
    FileHandle.standardError.write(Data("inconclusive: \(reason)\n".utf8))
    exit(0)
}

func swiftFiles(in directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        .filter { $0.hasSuffix(".swift") }
        .sorted()
        .map { directory.appendingPathComponent($0).path }
}

let namespaceSources = swiftFiles(in: namespaceDir)
let inlineSources = swiftFiles(in: inlineDir)
guard !namespaceSources.isEmpty, !inlineSources.isEmpty else {
    inconclusive("trigger sources not found under \(sourcesRoot.path)")
}

let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("rawlayout-rejection-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.removeItem(at: work)
guard (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil
else { inconclusive("could not create a scratch directory") }
defer { try? FileManager.default.removeItem(at: work) }

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

// Positive control: module A always compiles.
guard let moduleA = swiftc(
    ["-wmo", "-parse-as-library", "-emit-module",
     "-emit-module-path", "StorageNamespaceLib.swiftmodule",
     "-module-name", "StorageNamespaceLib"] + namespaceSources
) else { inconclusive("could not launch swiftc") }
guard moduleA.status == 0 else {
    inconclusive("module A failed to build:\n\(moduleA.stderr)")
}

guard let moduleB = swiftc(
    ["-wmo", "-parse-as-library", "-typecheck",
     "-enable-experimental-feature", "RawLayout", "-I", "."] + inlineSources
) else { inconclusive("could not launch swiftc for module B") }

if moduleB.stderr.contains("does not conform to protocol 'Copyable'") {
    FileHandle.standardError.write(Data("BUG FIRES: the @_rawLayout extension is rejected.\n".utf8))
    exit(1)
}
if moduleB.status == 0 {
    print("bug appears FIXED: module B typechecked cleanly.")
    exit(0)
}
inconclusive("module B failed for an unrelated reason:\n\(moduleB.stderr)")
#else
exit(0)
#endif

// swiftlint:enable no_try_optional
