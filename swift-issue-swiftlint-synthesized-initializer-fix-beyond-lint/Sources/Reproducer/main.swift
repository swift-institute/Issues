// This probe stages/lints/fixes/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct
// idiom here.
// swiftlint:disable no_try_optional
// Standalone exit-code probe for SwiftLint's fix-surface / lint-surface
// divergence on `unneeded_synthesized_initializer`.
//
// The rule's REPORTING path visits only types whose enclosing declaration is a
// struct or a class (or that are top level). Its CORRECTION path descends into
// types nested in an `enum` and into types declared inside an `extension`. The
// consequence is structural: a lane that measures with `--strict`, applies
// `--fix`, and re-verifies with `--strict` sees a clean before/after while
// unmeasured deletions rode along.
//
//   exit 1 — the divergence FIRES: `--fix` corrected strictly more sites than
//            `lint --strict` reported.
//   exit 0 — correction count equals reported count on this instrument. That is
//            the fix-detection signal.
//   exit 2 — inconclusive (no reachable `swiftlint`, or an unrelated failure).
//            CI images for this repository install SwiftLint only in the lint
//            job, so exit 2 is the ordinary outcome under `swift test`.

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
    .appendingPathComponent("swiftlint-synthesized-initializer-probe-\(pid)")
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

// MEASURE — what a lane running `--strict` would see.
guard let linted = run(["swiftlint", "lint", "--strict", "--no-cache", "--reporter", "json"])
else { inconclusive("could not launch swiftlint") }
let reported = linted.output.components(separatedBy: "unneeded_synthesized_initializer").count - 1

// POSITIVE CONTROL — the three CONTROL sites must be reported. A run reporting
// nothing is a broken instrument (rule disabled, config not found, fixture not
// linted), not a rule that has been fixed.
guard reported > 0 else {
    inconclusive("the instrument reported no `unneeded_synthesized_initializer` violation at all — control failed")
}

// MUTATE — what `--fix` actually does.
guard let fixed = run(["swiftlint", "--fix", "--no-cache"]), fixed.status == 0
else { inconclusive("could not apply `swiftlint --fix`") }

// DIFF THE WORKING TREE against the measured set. Counting the surviving
// initializers is the direct observation; the tool's own "Corrected N times"
// line is a secondary witness, not the measurement.
guard let mutated = try? String(contentsOf: staged, encoding: .utf8) else {
    inconclusive("could not read the fixture back after the correction")
}
let originalCount = 6
let surviving = mutated.components(separatedBy: "internal init(value: Int)").count - 1
let corrected = originalCount - surviving

FileHandle.standardError.write(Data("reported by lint --strict: \(reported)\ncorrected by --fix: \(corrected)\n".utf8))

guard corrected > reported else {
    print("fix surface equals report surface (\(corrected) == \(reported)): divergence not reproduced")
    exit(0)
}

print("DEFECT FIRES — `--fix` corrected \(corrected) sites; `lint --strict` reported \(reported).")
print("\(corrected - reported) mutation(s) were applied to code that was never reported as violating.")
exit(1)
#endif
// swiftlint:enable no_try_optional
