import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// EarlyPerfInliner aborts on an ESCAPING `mark_dependence` attached to the token
// result of a `begin_apply` (a `_read` coroutine), at -O.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// This bug aborts the COMPILER (signal 6) while compiling the triggering source
// under `-O`. The trigger therefore cannot be a compiled SwiftPM target — it would
// abort the whole Issues package build. It lives as the `Crash.swift.txt` resource
// and is compiled OUT OF PROCESS here ([ISSUE-029]).
//
// ⚠️ FLIP SEMANTICS DIFFER FROM THE OTHER ENTRIES — READ BEFORE EDITING
// ---------------------------------------------------------------------
// Most entries here reproduce on EVERY supported toolchain and so use
// `when: { true }`. This bug is **VERSION-GATED**: it is CLEAN on 6.3.3-RELEASE
// and 6.4.x-dev and fires only on 6.5-dev-class toolchains (see ../README.md).
//
// With `when: { true }` the stable 6.3 legs — where a clean compile is the CORRECT
// result — would each report "known issue was not recorded" and go RED. That is a
// false alarm, not a fix signal. So `when:` is gated on the toolchain version:
//
//   6.3/6.4-class, bug absent  → when=false → plain #expect passes         → GREEN (correct)
//   6.5-dev-class, bug fires   → when=true  → expectation fails, matched   → GREEN (known)
//   6.5-dev-class, bug absent  → when=true  → not recorded                 → RED = FIX LANDED
//   6.3/6.4-class, bug FIRES   → when=false → plain #expect fails          → RED = backport/regression
//
// The last row is deliberate: an unexpected firing on a stable leg should be loud.

@Suite
struct InlinerEscapingMarkDependenceCoroutineTokenReproducer {

    /// `swift --version`'s leading `X.Y`, or `nil` if it could not be determined.
    static func toolchainVersion() -> (major: Int, minor: Int)? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "--version"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let text = String(
            data: out.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        // "Swift version 6.5-dev (…)" / "Swift version 6.3.3 (swift-6.3.3-RELEASE)"
        guard let marker = text.range(of: "Swift version ") else { return nil }
        let rest = text[marker.upperBound...]
        let token = rest.prefix { !$0.isWhitespace }          // "6.5-dev" / "6.3.3"
        let numeric = token.prefix { $0.isNumber || $0 == "." }
        let parts = numeric.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
        #else
        return nil
        #endif
    }

    /// True when the running toolchain is one where this bug is KNOWN to fire
    /// (6.5-dev and later). Conservative: an undeterminable version yields
    /// `false`, so an unknown toolchain can never manufacture a red "fix" flip.
    static func expectedToFire() -> Bool {
        guard let v = toolchainVersion() else { return false }
        return (v.major, v.minor) >= (6, 5)
    }

    /// Compiles `Crash.swift.txt` with `swiftc -O` in a child process and reports
    /// whether the inliner aborted. `nil` when no compiler could be reached or the
    /// compile failed for an unrelated reason (inconclusive — the third
    /// disposition required by [ISSUE-029]).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let crashSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

        guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

        // swiftc keys off the file extension; stage the `.txt` resource as a
        // `.swift` temp so it is compiled rather than treated as a link input.
        let pid = ProcessInfo.processInfo.processIdentifier
        let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("inliner-escaping-markdep-test-\(pid).swift")
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("inliner-escaping-markdep-test-\(pid).o")
        try? FileManager.default.removeItem(at: swiftCopy)
        guard (try? FileManager.default.copyItem(at: crashSource, to: swiftCopy)) != nil else { return nil }
        defer {
            try? FileManager.default.removeItem(at: swiftCopy)
            try? FileManager.default.removeItem(at: out)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swiftc", "-O", "-swift-version", "6",
            // Load-bearing: these two features are what produce the
            // lifetime-dependent coroutine. A toolchain rejecting either lands in
            // the inconclusive branch rather than reporting a fix.
            "-enable-experimental-feature", "Lifetimes",
            "-enable-experimental-feature", "SuppressedAssociatedTypes",
            "-c", swiftCopy.path,
            "-o", out.path,
        ]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do { try process.run() } catch { return nil }
        process.waitUntilExit()

        let errText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        // Narrow on purpose: a future rephrasing surfaces as inconclusive rather
        // than as a false flip in either direction.
        if errText.contains("isNonEscaping") || errText.contains("BeginApplySite::preprocess") {
            return true
        }
        if process.terminationStatus == 0 {
            return false          // compiled cleanly
        }
        return nil                // unrelated failure — inconclusive
    #else
        return nil                // no subprocess facility
    #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else {
            // No reachable compiler, or an unrelated failure — nothing to assert.
            return
        }

        withKnownIssue(
            "EarlyPerfInliner: assert(mdi.isNonEscaping()) on an escaping mark_dependence over a begin_apply token (SILInliner.cpp:167) — 6.5-dev-class only",
            { #expect(fired == false) },
            // 🛑 Version-gated, NOT `{ true }`. The other entries in this repo use
            // `{ true }` because their bugs fire on EVERY toolchain; this one is
            // 6.5-dev-only, so `{ true }` would make every green 6.3 leg report
            // "known issue was not recorded" and go RED permanently. Deliberate and
            // reviewed — see the "Do not 'fix' this back to when: { true }" box in
            // ../README.md before changing this line. If the bug ever reaches the
            // stable pin, WIDEN the predicate; do not replace it with `{ true }`.
            when: { Self.expectedToFire() }
        )
    }
}
