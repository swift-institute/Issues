import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// SwiftLint's `redundant_nil_coalescing` treats every `?? nil` as dead code. On a
// DOUBLE optional — the `T??` that `withContiguousStorageIfAvailable` returns —
// `?? nil` is the flattening operation and is load-bearing. The rule fires
// anyway, `--fix` deletes it, the file stops compiling, and the very next
// `swiftlint lint --strict` reports the broken file clean.
//
// Measured 2026-08-10 against the exact instrument the fleet's CI runs —
// SwiftLint 0.63.3 `swiftlint_linux_amd64` (sha256
// 26db741d43f2f2dc26c0cf16911100a3e186c3d1dbb59e55ad3ac87b0de4538f, the
// `SWIFTLINT_SHA256` pin in swift-institute/.github `swift-ci.yml`) inside the
// release-floor container image `swiftlang/swift@sha256:8d614165…736224`
// (Swift 6.4-dev, x86_64-unknown-linux-gnu):
//
//   swiftc -typecheck before ... exit 0
//   lint --strict ............... 2 violations (hazard site + positive control)
//   --fix ....................... both `?? nil` deleted
//   swiftc -typecheck after ..... error: value of optional type 'Int?' must be
//                                 unwrapped to a value of type 'Int'
//   lint --strict after ......... 0 violations — the break is invisible to lint
//
// SwiftLint 0.65.0 on macOS arm64 behaves identically.
//
// The production shape this reduces (swift-foundations/swift-json
// `JSON.Decode.swift`, `JSON.Serializable.swift`) returns `Self?` from the
// closure, where the post-correction diagnostic reads `declared closure result
// 'Self?' is incompatible with contextual type 'Self'`. The concrete `Int?`
// reduction above produces the unwrap diagnostic instead; the class is the same
// — a correction that turns compiling code into non-compiling code.
//
// WHY AN OUT-OF-PROCESS HARNESS
// -----------------------------
// The instrument under test is SwiftLint, not the compiler, and the post-fix
// state does not compile by construction — so the fixture cannot be a member of
// this target. It ships as `Fixture.swift.txt`, is linted, corrected and
// typechecked OUT OF PROCESS against a staged copy.
//
// FLIP SEMANTICS
// --------------
// `when:` is gated on the instrument being PRESENT AND REPORTING BOTH sites.
// This repository's CI installs SwiftLint in the lint job only, so under
// `swift test` the guard is false, known-issue matching is inactive, and the
// body asserts nothing — the honest outcome when the instrument is absent. Where
// SwiftLint IS on PATH the block is active: green while the correction breaks
// the build, RED the moment it stops doing so, and that flip is the
// fix-detection signal.

@Suite struct `SwiftLint Redundant Nil Coalescing Double Optional` {
    @Suite struct Unit {}
}

extension `SwiftLint Redundant Nil Coalescing Double Optional`.Unit {

    /// Whether the corrected fixture still compiles, plus whether lint calls the
    /// corrected fixture clean. `nil` when the instrument is unreachable, the
    /// positive control fails, or the fixture did not compile to begin with.
    static func measure() -> (compilesAfterFix: Bool, lintCleanAfterFix: Bool)? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Reproducer")

        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftlint-nil-coalescing-test-\(ProcessInfo.processInfo.processIdentifier)")

        // FileManager's removeItem/createDirectory/copyItem are untyped
        // cross-module throwing APIs; every outcome is handled by the guards
        // below rather than swallowed. No suppression is needed:
        // `no_try_optional` excludes `Tests/.*`.
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

        // PRECONDITION: the fixture compiles BEFORE the correction. Without it
        // the measurement cannot distinguish "the fix broke it" from "it never
        // compiled".
        guard let before = run(["swiftc", "-typecheck", "-swift-version", "6", staged.path]),
              before.status == 0
        else { return nil }

        // POSITIVE CONTROL: both sites must be reported — the hazard (double
        // optional) and the genuinely-redundant single optional. A run reporting
        // fewer is either a broken instrument or a rule that has been narrowed.
        guard let linted = run(["swiftlint", "lint", "--strict", "--no-cache", "--reporter", "json"])
        else { return nil }
        guard linted.output.components(separatedBy: "redundant_nil_coalescing").count - 1 == 2
        else { return nil }

        guard let fixed = run(["swiftlint", "--fix", "--no-cache"]), fixed.status == 0 else { return nil }
        guard let after = run(["swiftc", "-typecheck", "-swift-version", "6", staged.path]) else { return nil }
        guard let recheck = run(["swiftlint", "lint", "--strict", "--no-cache"]) else { return nil }

        return (after.status == 0, recheck.status == 0)
        #else
        return nil
        #endif
    }

    @Test func `the redundant_nil_coalescing correction turns compiling code into a compile error`() {
        let measured = Self.measure()
        withKnownIssue(
            "swiftlint --fix deletes the `?? nil` that flattens a double optional"
        ) {
            guard let measured else { return }
            #expect(
                measured.compilesAfterFix,
                """
                the fixture compiled before `swiftlint --fix` and does not compile after it. \
                lint reports the broken fixture clean: \(measured.lintCleanAfterFix).
                """
            )
        } when: {
            measured != nil
        }
    }
}
