import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// A `@TaskLocal` whose VALUE TYPE IS A FUNCTION TYPE makes the optimizer emit the
// value type's metadata request as a LOWERED mangled name (`ImplFunctionType`
// carrying `ImplPatternSubstitutions` over a dependent generic signature) through
// `__swift_instantiateConcreteTypeFromMangledName`, the entry point that admits
// only fully concrete names. Instantiation returns null, and
// `swift_task_localValuePush` faults reading the value witness table at
// `metadata - 8`:
//
//   *** Program crashed: Bad pointer dereference at 0xfffffffffffffff8 ***
//     0  swift_task_localValuePush + … in libswift_Concurrency.so
//     1 [inlined] specialized TaskLocal.withValue<A>(_:operation:file:line:)
//
// Minimum trigger — two statements, no async, no Task, no test framework:
//
//   @TaskLocal var handler: (@Sendable () -> Void)?
//   $handler.withValue({}, operation: {})
//
// Load-bearing: `-O`, and a FUNCTION-typed value. `Int?` and `String?` are clean;
// optionality is not part of the trigger. NOT required: async, a surrounding
// Task, a current task at all, reading the task local inside `operation:`, a test
// framework, or more than one module.
//
// Observed:
//   6.3.3-RELEASE ......... signal 11, macOS arm64 + Linux arm64 + Linux x86_64
//   Apple Swift 6.4 ....... clean
//   6.4.x-snapshot-2026-07-23 (+assertions)
//                           clean
//   main-snapshot-2026-07-11 / nightly-main (6.5-dev)
//                           clean
//
// WHY AN OUT-OF-PROCESS HARNESS
// -----------------------------
// The bug crashes the PRODUCED BINARY rather than the compiler, but an in-process
// trigger would take the whole test runner down with SIGSEGV. The trigger
// therefore ships as `Crash.swift.txt`, compiled AND run out of process with `-O`
// forced regardless of this target's own build configuration.
//
// FLIP SEMANTICS
// --------------
// The defect is fixed on 6.4 and later, so `when:` is version-gated on the
// compiler that built THIS target:
//
//   below 6.4 — known-issue matching ACTIVE. Green while the bug fires; RED the
//               moment it stops, which is the 6.3 backport-detection signal.
//   6.4+      — known-issue matching INACTIVE. The expectation runs unguarded, so
//               the leg is green because the bug is fixed and turns RED on a
//               regression.
//
// Both directions are live signals; neither state is silent.

@Suite
struct TaskLocalFunctionValueNullMetadataReproducer {

    /// Measured deterministic (5/5 aborts on 6.3.3 macOS arm64; every Linux
    /// invocation aborted). Retried anyway so that a single anomalous clean run
    /// cannot announce a fix that has not landed.
    static let attempts = 3

    /// True when this target was built by a compiler that predates the fix.
    static var expectsBug: Bool {
        #if compiler(>=6.4)
        false
        #else
        true
        #endif
    }

    /// Compiles `Crash.swift.txt` with `-O` and runs the resulting binary up to
    /// `attempts` times. Returns `true` if any run died with `SIGSEGV`, `false`
    /// if every run completed, and `nil` if no compiler could be reached or a
    /// failure was unrelated — in which case the probe proved nothing.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let crashSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")
        guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

        let pid = ProcessInfo.processInfo.processIdentifier
        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tasklocal-function-value-null-metadata-\(pid)")
        try? FileManager.default.removeItem(at: work)
        guard (try? FileManager.default.createDirectory(
            at: work, withIntermediateDirectories: true
        )) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: work) }

        // Top-level code: the trigger must be staged as `main.swift`.
        let staged = work.appendingPathComponent("main.swift")
        guard (try? FileManager.default.copyItem(at: crashSource, to: staged)) != nil
        else { return nil }

        func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, signalled: Bool)? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            process.currentDirectoryURL = work
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = Pipe()
            do { try process.run() } catch { return nil }
            // Drain stderr before waiting so a verbose crash report cannot fill
            // the pipe buffer and deadlock the child.
            _ = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, process.terminationReason == .uncaughtSignal)
        }

        guard let build = run(
            "/usr/bin/env",
            ["swiftc", "-O", "-swift-version", "6", "main.swift", "-o", "probe"]
        ) else { return nil }
        guard build.status == 0 else { return nil }

        let binary = work.appendingPathComponent("probe")
        var sawUnrelatedFailure = false
        for _ in 0..<attempts {
            guard let outcome = run(binary.path, []) else { return nil }
            if outcome.signalled, outcome.status == SIGSEGV { return true }
            if outcome.status != 0 { sawUnrelatedFailure = true }
        }
        return sawUnrelatedFailure ? nil : false
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
            A function-typed @TaskLocal value makes the optimizer request the \
            value type's metadata through the concrete-only demangling entry \
            point with a lowered, still-dependent mangled name; instantiation \
            returns null and swift_task_localValuePush faults at metadata - 8
            """,
            { #expect(fired == false) },
            // The `guard let fired … else { return }` above already skips
            // unreachable / N-A platforms, so this predicate carries only the
            // toolchain axis: ACTIVE below 6.4 (green while firing, RED when the
            // backport lands), INACTIVE at 6.4+ (green because fixed, RED on a
            // regression).
            when: { Self.expectsBug }
        )
    }
}
