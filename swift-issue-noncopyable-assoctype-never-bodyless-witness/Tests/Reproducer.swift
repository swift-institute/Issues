import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// A protocol with `associatedtype Body: ~Copyable` and a `Body == Never`
// extension default for its `body` property emits the default's `read`
// accessor into any CONSUMER module that adds a `Body == Never` conformance
// as a `shared [serialized]` SIL function with NO body. Wherever SIL
// verification runs (+Asserts toolchains, Embedded, `-sil-verify-all`),
// swift-frontend aborts:
//
//   <unknown>:0: note: Must have a construct to emit for            (6.3 line)
//   SIL verification failed: public/package/shared function must have a body  (+assertions)
//
// On a NoAsserts RELEASE toolchain the malformed SIL is emitted silently —
// the bug is latent there, not absent, which is why macOS/Linux CI legs pass
// while Windows (+Asserts) and Embedded legs fail on identical code.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// Two things force it. First, the bug aborts the COMPILER, so the trigger
// cannot be a compiled SwiftPM target — live targets would crash every
// verification-enabled leg and be silently malformed everywhere else.
// Second, the defect is inherently CROSS-MODULE: the single-module
// combination of the same declarations compiles clean under -sil-verify-all
// (checked 2026-07-30 on Apple Swift 6.4), so the module boundary is
// load-bearing and is expressed as two frontend invocations here.
//
// FLIP SEMANTICS
// --------------
// `withKnownIssue` is GREEN while the bug fires and flips RED the moment the
// consumer module compiles cleanly under -sil-verify-all. NOT fixed on any
// tested toolchain (2026-07-30: 6.3.3-RELEASE, Apple Swift 6.4,
// main-snapshot-2026-07-11 (+assertions) all abort), so `when:` is `{ true }`.

@Suite
struct NoncopyableAssoctypeNeverBodylessWitnessReproducer {

    /// Compiles `Core.swift.txt` as module M, then compiles
    /// `Consumer.swift.txt` against it with `-sil-verify-all`, in child
    /// processes. Returns `true` if the second invocation aborted with this
    /// defect's signature, `false` if it compiled cleanly (fix landed), and
    /// `nil` if no compiler could be reached or the FIRST invocation failed —
    /// in which case the probe proved nothing.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer")

        let coreSource = root.appendingPathComponent("Core.swift.txt")
        let consumerSource = root.appendingPathComponent("Consumer.swift.txt")
        guard FileManager.default.fileExists(atPath: coreSource.path),
              FileManager.default.fileExists(atPath: consumerSource.path)
        else { return nil }

        let pid = ProcessInfo.processInfo.processIdentifier
        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("noncopyable-never-witness-\(pid)")
        try? FileManager.default.removeItem(at: work)
        guard (try? FileManager.default.createDirectory(
            at: work, withIntermediateDirectories: true
        )) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: work) }

        let core = work.appendingPathComponent("Core.swift")
        let consumer = work.appendingPathComponent("Consumer.swift")
        guard (try? FileManager.default.copyItem(at: coreSource, to: core)) != nil,
              (try? FileManager.default.copyItem(at: consumerSource, to: consumer)) != nil
        else { return nil }

        func run(_ arguments: [String]) -> (status: Int32, stderr: String)? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc"] + arguments
            process.currentDirectoryURL = work
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = Pipe()
            do { try process.run() } catch { return nil }
            let text = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            process.waitUntilExit()
            return (process.terminationStatus, text)
        }

        // Step 1 — the defining module. This ALWAYS compiles; if it does not,
        // the environment is at fault and the probe is inconclusive. This is
        // the probe's positive control: it proves swiftc was reached and ran.
        guard let defining = run([
            "-enable-experimental-feature", "SuppressedAssociatedTypes",
            "-wmo", "-parse-as-library", "-emit-module",
            "-emit-module-path", "M.swiftmodule", "-module-name", "M", "Core.swift",
        ]), defining.status == 0 else { return nil }

        // Step 2 — the consumer module, with verification forced on.
        guard let importing = run([
            "-enable-experimental-feature", "SuppressedAssociatedTypes",
            "-Xfrontend", "-sil-verify-all",
            "-wmo", "-parse-as-library", "-c", "Consumer.swift",
            "-I", ".", "-module-name", "N", "-o", "Consumer.o",
        ]) else { return nil }

        if importing.stderr.contains("Must have a construct to emit for")
            || importing.stderr.contains("must have a body") {
            return true
        }
        if importing.status == 0 {
            return false          // compiled cleanly — fix has landed
        }
        return nil                // failed for an unrelated reason — inconclusive
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
            """
            Bodyless `shared [serialized]` default-witness `read` accessor for a \
            `~Copyable` associated type bound to `Never`, emitted into a consumer \
            module and rejected wherever SIL verification runs
            """,
            { #expect(fired == false) },
            // `when: { true }`, NOT `{ fired }`: the `guard let fired … else { return }`
            // above already skips unreachable / N-A platforms, so known-issue matching
            // must stay ACTIVE when the bug stops firing — that is what flips the leg
            // RED on an upstream fix.
            when: { true }
        )
    }
}
