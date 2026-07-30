import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// Throwing the ENCLOSING function's typed error from inside a `catch` clause
// whose `do` block throws a DIFFERENT concrete error type crashes SILGen: the
// `throw` is emitted against the do block's thrown type instead of the
// function's.
//
//   func make() throws(Inner) { throw .a }
//   func g() throws(Outer) {
//       do { try make() } catch let error as Inner { _ = error; throw Outer.x }
//   }
//
// Observed forms, all the same defect:
//   6.3.3-RELEASE ......... signal 11 in SILGenFunction::emitExistentialErasure,
//                           reached from emitThrow inside emitCatchDispatch
//   Apple Swift 6.4 ....... assert (FormalConcreteType->isBridgeableObjectType()),
//                           createInitExistentialRef, SILBuilder.h:2244
//   6.4.x-snapshot-2026-07-23 (+assertions)
//                           assert (destErrorType == SILType::getExceptionType(...)),
//                           emitThrow, SILGenStmt.cpp:1758
//   main-snapshot-2026-07-11 (6.5-dev)
//                           no crash, but a hard "INTERNAL ERROR: feature not
//                           implemented: throw conversion from 'Inner' to 'Outer'"
//
// The 6.5-dev diagnostic is the clearest statement of the defect and is treated
// as FIRING: the program is still not compilable.
//
// Load-bearing: the enclosing function's `throws(Outer)` (an untyped `throws`
// is clean) and a concrete-type catch pattern, `as Inner` or `is Inner` (a bare
// `catch` is clean). NOT required: an initializer (a plain `func` crashes
// identically, though the Institute's production instance is an `init`),
// optimization (`-Onone` and `-O` behave identically), whole-module, or more
// than one module.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// The bug aborts the COMPILER, so the trigger cannot be a compiled SwiftPM
// target — a live target would break every leg of the package. The trigger
// therefore ships as `Crash.swift.txt` and is compiled out of process.
//
// FLIP SEMANTICS
// --------------
// `withKnownIssue` is GREEN while the bug fires and flips RED the moment
// `Crash.swift.txt` compiles cleanly. NOT fixed on any tested toolchain
// (2026-07-30), so `when:` is `{ true }`.

@Suite
struct TypedThrowsCatchClauseErrorConversionReproducer {

    /// On 6.3.3-RELEASE the failure is a bad pointer dereference in a NoAsserts
    /// build — undefined behaviour that survives roughly one attempt in ten
    /// (measured 11/12 aborts, macOS arm64, 2026-07-30). Every
    /// assertions-enabled toolchain and Apple Swift 6.4 abort deterministically.
    /// Retrying keeps a single lucky run from announcing a fix that has not
    /// landed.
    static let attempts = 3

    /// Compiles `Crash.swift.txt` in a child process, up to `attempts` times.
    /// Returns `true` if any attempt failed with this defect's signature,
    /// `false` if every attempt compiled cleanly (fix landed), and `nil` if no
    /// compiler could be reached or a failure was unrelated — in which case the
    /// probe proved nothing.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let crashSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")
        guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

        let pid = ProcessInfo.processInfo.processIdentifier
        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("typed-throws-catch-conversion-\(pid)")
        try? FileManager.default.removeItem(at: work)
        guard (try? FileManager.default.createDirectory(
            at: work, withIntermediateDirectories: true
        )) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: work) }

        let staged = work.appendingPathComponent("Crash.swift")
        guard (try? FileManager.default.copyItem(at: crashSource, to: staged)) != nil
        else { return nil }

        func compile() -> (status: Int32, stderr: String)? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "swiftc", "-swift-version", "6", "-parse-as-library",
                "-c", "Crash.swift", "-o", "Crash.o",
            ]
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

        var sawUnrelatedFailure = false
        for _ in 0..<attempts {
            guard let result = compile() else { return nil }
            guard result.status != 0 else { continue }
            if result.stderr.contains("INTERNAL ERROR: feature not implemented: throw conversion")
                || result.stderr.contains("While silgen") {
                return true
            }
            sawUnrelatedFailure = true
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
            SILGen emits a `throw` inside a catch clause against the do block's \
            thrown type instead of the enclosing typed-throws function's, \
            crashing swift-frontend (6.3.3 / Apple 6.4 / 6.4.x snapshot) or \
            failing with "feature not implemented: throw conversion" (6.5-dev)
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
