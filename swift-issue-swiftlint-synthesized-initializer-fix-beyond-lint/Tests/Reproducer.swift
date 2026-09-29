import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// SwiftLint's `unneeded_synthesized_initializer` corrects strictly more sites
// than it reports. The reporting path visits only types that are top level or
// nested in a struct/class; the correction path additionally descends into types
// nested in an `enum` and types declared inside an `extension`.
//
// Measured 2026-08-10 against the exact instrument the fleet's CI runs —
// SwiftLint 0.63.3 `swiftlint_linux_amd64` (sha256
// 26db741d43f2f2dc26c0cf16911100a3e186c3d1dbb59e55ad3ac87b0de4538f, the
// `SWIFTLINT_SHA256` pin in swift-institute/.github `swift-ci.yml`) inside the
// release-floor container image `swiftlang/swift@sha256:8d614165…736224`:
//
//   lint --strict ... 3 violations (top-level, struct-nested, class-nested)
//   --fix .......... 6 corrections (those three, plus both enum-nested sites and
//                    the extension-declared site)
//
// SwiftLint 0.65.0 on macOS arm64 reports the identical 3-vs-6 split.
//
// WHY AN OUT-OF-PROCESS HARNESS
// -----------------------------
// The instrument under test is SwiftLint, not the compiler. The defect is only
// observable by running the real binary over a tree and diffing the working tree
// against the measured violation set, so the fixture ships as
// `Fixture.swift.txt` and is linted OUT OF PROCESS against a staged copy.
//
// FLIP SEMANTICS
// --------------
// `when:` is gated on the instrument being PRESENT AND REPORTING. This
// repository's CI installs SwiftLint in the lint job only, so under `swift test`
// the guard is false, known-issue matching is inactive, and the body asserts
// nothing — the honest outcome when the instrument is absent. Where SwiftLint IS
// on PATH the block is active: green while the divergence fires, RED the moment
// correction count equals report count, and that flip is the fix-detection
// signal.

@Suite struct `SwiftLint Synthesized Initializer Fix Beyond Lint` {
    @Suite struct Unit {}
}

extension `SwiftLint Synthesized Initializer Fix Beyond Lint`.Unit {

    /// Sites reported by `lint --strict`, and sites actually mutated by `--fix`.
    /// `nil` when the instrument is unreachable or its positive control fails.
    static func measure() -> (reported: Int, corrected: Int)? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Reproducer")

        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftlint-synth-init-test-\(ProcessInfo.processInfo.processIdentifier)")

        // FileManager's removeItem/createDirectory/copyItem and
        // String(contentsOf:) are untyped cross-module throwing APIs; every
        // outcome is handled by the guards below rather than swallowed. No
        // suppression is needed: `no_try_optional` excludes `Tests/.*`.
        try? FileManager.default.removeItem(at: work)
        guard (try? FileManager.default.createDirectory(
            at: work.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: work) }

        let staged = work.appendingPathComponent("Sources/Fixture.swift")
        guard (try? FileManager.default.copyItem(
                  at: sources.appendingPathComponent("Fixture.swift.txt"), to: staged
              )) != nil,
              (try? FileManager.default.copyItem(
                  at: sources.appendingPathComponent("Config.yml.txt"),
                  to: work.appendingPathComponent(".swiftlint.yml")
              )) != nil
        else { return nil }

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

        guard let linted = run(["swiftlint", "lint", "--strict", "--no-cache", "--reporter", "json"])
        else { return nil }
        let reported = linted.output.components(separatedBy: "unneeded_synthesized_initializer").count - 1
        // POSITIVE CONTROL: an instrument reporting nothing is broken — rule
        // disabled, configuration not found, fixture not linted — not fixed.
        guard reported > 0 else { return nil }

        guard let fixed = run(["swiftlint", "--fix", "--no-cache"]), fixed.status == 0 else { return nil }
        guard let mutated = try? String(contentsOf: staged, encoding: .utf8) else { return nil }
        let surviving = mutated.components(separatedBy: "internal init(value: Int)").count - 1
        return (reported, 6 - surviving)
        #else
        return nil
        #endif
    }

    @Test func `--fix mutates strictly more sites than lint --strict reports`() {
        let measured = Self.measure()
        withKnownIssue(
            "swiftlint --fix corrects enum-nested and extension-declared types that lint never reports"
        ) {
            guard let measured else { return }
            #expect(
                measured.corrected == measured.reported,
                """
                lint --strict reported \(measured.reported) site(s); --fix mutated \
                \(measured.corrected). \(measured.corrected - measured.reported) \
                mutation(s) were applied to code that was never reported as violating.
                """
            )
        } when: {
            measured != nil
        }
    }
}
