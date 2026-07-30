import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// swiftlang/swift#90406 — swift-frontend aborts compiling a module that adds its
// own conformance to a protocol imported from another module, when that protocol
// has a coroutine-accessor (`@_borrowed`) requirement whose default lives in a
// protocol extension of the DEFINING module, and the defining module also has a
// conformer. The extension default's `.read` coroutine is emitted as
// `sil shared [serialized]` with NO body; the importing module's MandatorySILLinker
// tries to deserialize it and trips
// `(!hasSharedVisibility(F->getLinkage()) || F->hasForeignBody())`.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// Two things force it. First, the bug aborts the COMPILER (signal 6), so the
// trigger cannot be a compiled SwiftPM target. Second, the defect is inherently
// CROSS-MODULE: it needs two separate frontend invocations, the second importing
// the first's `.swiftmodule`. Both trigger files therefore ship as `.txt`
// resources and are compiled out of process here.
//
// FLIP SEMANTICS
// --------------
// `withKnownIssue` is GREEN while the bug fires and flips RED the moment the
// importing module compiles cleanly. That red flip is the fix-detection signal.
//
// VERSION STORY (every row `swift --version`-confirmed; see ../README.md)
//   6.3.3-RELEASE (macOS arm64, Linux aarch64, Linux x86_64) . abort, MandatorySILLinker
//   Apple Swift 6.4 (Xcode) ................................. abort, MandatorySILLinker
//   6.4.x-snapshot-2026-07-23 (+assertions) ................. abort, earlier: SIL verifier
//   main-snapshot-2026-07-11 (+assertions) .................. abort, earlier: SIL verifier
// NOT fixed on any tested toolchain, and NOT architecture-dependent. The two
// assertions-enabled snapshots catch the same malformed function earlier, during
// ASTLoweringRequest, with the clearer message
// `public/package/shared function must have a body` naming
// `sil shared [serialized] @…MyVector.subscript.read`. Both messages are the
// same defect, so the probe accepts either.

@Suite
struct SILLinkerBorrowedProtocolDefaultSharedCoroutineAbortReproducer {

    /// Compiles `LibA.swift.txt` as a module, then compiles `Consumer.swift.txt`
    /// against it, in child processes. Returns `true` if the second invocation
    /// aborted with this defect's signature, `false` if it compiled cleanly (fix
    /// landed), and `nil` if no compiler could be reached or the FIRST invocation
    /// failed — in which case the probe proved nothing.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer")

        let libSource = root.appendingPathComponent("LibA.swift.txt")
        let consumerSource = root.appendingPathComponent("Consumer.swift.txt")
        guard FileManager.default.fileExists(atPath: libSource.path),
              FileManager.default.fileExists(atPath: consumerSource.path)
        else { return nil }

        // swiftc keys off the file extension, and the second invocation needs the
        // first's `.swiftmodule` on its import search path — so both files are
        // staged as `.swift` inside one scratch directory that doubles as `-I`.
        let pid = ProcessInfo.processInfo.processIdentifier
        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sillinker-borrowed-default-\(pid)")
        try? FileManager.default.removeItem(at: work)
        guard (try? FileManager.default.createDirectory(
            at: work, withIntermediateDirectories: true
        )) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: work) }

        let lib = work.appendingPathComponent("LibA.swift")
        let consumer = work.appendingPathComponent("Consumer.swift")
        guard (try? FileManager.default.copyItem(at: libSource, to: lib)) != nil,
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

        // Step 1 — the defining module. This ALWAYS compiles; if it does not, the
        // environment is at fault and the probe is inconclusive. This is the
        // probe's positive control: it proves swiftc was reached and ran.
        guard let defining = run([
            "-emit-module", "-emit-library", "-module-name", "LibA", "LibA.swift",
        ]), defining.status == 0 else { return nil }

        // Step 2 — the importing module. This is the one that aborts.
        guard let importing = run(["-c", "-I", ".", "Consumer.swift"]) else { return nil }

        if importing.stderr.contains("cannot deserialize shared function")
            || importing.stderr.contains("shared function must have a body") {
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
            swiftlang/swift#90406 — MandatorySILLinker cannot deserialize the \
            bodiless `sil shared [serialized]` `.read` coroutine of a `@_borrowed` \
            protocol requirement defaulted in the defining module's extension
            """,
            { #expect(fired == false) },
            // `when: { true }`, NOT `{ fired }`: the `guard let fired … else { return }`
            // above already skips unreachable / N-A platforms, so known-issue matching
            // must stay ACTIVE when the bug stops firing — that is what flips the leg
            // RED on an upstream fix. `{ fired }` disables matching on a fix, leaves the
            // body passing, and stays GREEN forever.
            when: { true }
        )
    }
}
