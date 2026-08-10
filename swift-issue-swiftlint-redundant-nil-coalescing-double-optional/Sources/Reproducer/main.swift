// This probe stages/lints/fixes/compiles/cleans up temp reproducer files;
// failures in best-effort cleanup or staging checks are handled via guard/defer
// control flow, not silently swallowed, so the optional-chaining form is the
// correct idiom here.
// swiftlint:disable no_try_optional
// Standalone exit-code probe for the `redundant_nil_coalescing` double-optional
// defect.
//
// SwiftLint's `redundant_nil_coalescing` treats every `?? nil` as dead code. On
// a DOUBLE optional (`T??`) — the shape `withContiguousStorageIfAvailable`
// returns — `?? nil` is the flattening operation and is load-bearing. The rule
// fires anyway, `--fix` deletes it, the file stops compiling, and the very next
// `swiftlint lint --strict` reports the now-broken file clean.
//
// The instrument under test is SwiftLint, not the compiler, so this probe drives
// the real binary out of process rather than reimplementing the rule.
//
//   exit 1 — the defect FIRES: the fixture compiled, `--fix` mutated it, and the
//            mutated fixture no longer compiles while lint reports it clean.
//   exit 0 — the defect does NOT fire on this instrument: either the rule no
//            longer flags the double-optional site, or the correction preserves
//            compilability. That is the fix-detection signal.
//   exit 2 — inconclusive (no reachable `swiftlint` or `swiftc`, or an unrelated
//            failure). CI images for this repository install SwiftLint only in
//            the lint job, so exit 2 is the ordinary outcome under `swift test`.

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let fixtureSource = here.appendingPathComponent("Fixture.swift.txt")
let configSource = here.appendingPathComponent("Config.yml.txt")

func inconclusive(_ reason: String) -> Never {
    FileHandle.standardError.write(Data("inconclusive: \(reason)\n".utf8))
    exit(2)
}

guard FileManager.default.fileExists(atPath: fixtureSource.path),
      FileManager.default.fileExists(atPath: configSource.path)
else { inconclusive("fixture resources not found next to \(#filePath)") }

let pid = ProcessInfo.processInfo.processIdentifier
let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("swiftlint-nil-coalescing-probe-\(pid)")
try? FileManager.default.removeItem(at: work)
guard (try? FileManager.default.createDirectory(
    at: work.appendingPathComponent("Sources"),
    withIntermediateDirectories: true
)) != nil
else { inconclusive("could not create a scratch directory") }
defer { try? FileManager.default.removeItem(at: work) }

let staged = work.appendingPathComponent("Sources/Fixture.swift")
guard (try? FileManager.default.copyItem(at: fixtureSource, to: staged)) != nil,
      (try? FileManager.default.copyItem(
          at: configSource,
          to: work.appendingPathComponent(".swiftlint.yml")
      )) != nil
else { inconclusive("could not stage the fixture and its configuration") }

func run(_ arguments: [String]) -> (status: Int32, output: String)? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = work
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return nil }
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()
    return (process.terminationStatus, text)
}

guard let version = run(["swiftlint", "version"]), version.status == 0
else { inconclusive("no reachable `swiftlint` on PATH") }
FileHandle.standardError.write(Data("swiftlint \(version.output.trimmingCharacters(in: .whitespacesAndNewlines))\n".utf8))

// PRECONDITION — the fixture compiles BEFORE the correction. Without this the
// probe cannot distinguish "the fix broke it" from "it never compiled".
guard let before = run(["swiftc", "-typecheck", "-swift-version", "6", staged.path])
else { inconclusive("could not launch swiftc") }
guard before.status == 0 else {
    inconclusive("the fixture did not compile before the correction:\n\(before.output)")
}

// POSITIVE CONTROL — the instrument must report BOTH sites. One is the hazard
// (double optional), one is genuinely redundant. A run that reports neither is a
// broken instrument, not a fixed rule.
guard let linted = run(["swiftlint", "lint", "--strict", "--no-cache", "--reporter", "json"])
else { inconclusive("could not launch swiftlint") }
let reported = linted.output.components(separatedBy: "redundant_nil_coalescing").count - 1
guard reported >= 1 else {
    inconclusive("the instrument reported no `redundant_nil_coalescing` violation at all — control failed")
}
if reported == 1 {
    print("rule no longer fires on the double-optional site (only the control remains): defect not reproduced")
    exit(0)
}

guard let fixed = run(["swiftlint", "--fix", "--no-cache"]), fixed.status == 0
else { inconclusive("could not apply `swiftlint --fix`") }

guard let after = run(["swiftc", "-typecheck", "-swift-version", "6", staged.path])
else { inconclusive("could not launch swiftc after the correction") }

guard after.status != 0 else {
    print("the corrected fixture still compiles: defect not reproduced")
    exit(0)
}

// The second half of the defect: lint now reports the BROKEN file as clean.
guard let recheck = run(["swiftlint", "lint", "--strict", "--no-cache"]) else {
    inconclusive("could not re-lint after the correction")
}
let cleanAfterBreak = recheck.status == 0

FileHandle.standardError.write(Data("compiler diagnostic after `--fix`:\n\(after.output)\n".utf8))
print("DEFECT FIRES — fixture compiled before `--fix`, does not compile after.")
print("lint after the break reports clean: \(cleanAfterBreak)")
exit(1)
#endif
// swiftlint:enable no_try_optional
