import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// swiftlang/swift (PENDING filing) — `~Copyable` `@_rawLayout` trailing-field
// value-witness IRGen dominance-violation compiler abort.
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// This bug aborts the COMPILER (signal 6, LLVM verifier "Instruction does not
// dominate all uses") while compiling the triggering source under `-O`. The
// triggering sources therefore cannot be compiled SwiftPM targets — they would
// abort the whole Issues package build. Instead they live as `.swift.txt`
// resources and are compiled OUT OF PROCESS here.
//
// THE TRIGGERS
// ------------
// - `Crash.swift.txt`: scalar field after the buffer, `swiftc -O`.
// - `AccessLevel.swift.txt`: the same shape with public types, `swiftc -O -wmo`.
//   Under `-wmo` an internal copy compiles; public and package copies crash.
// - `CrossModuleCore.swift.txt` + `CrossModuleMiddleware.swift.txt`: a struct
//   with two generic raw-layout fields, built as two modules at `-O -wmo`.
//
// FLIP SEMANTICS
// --------------
// `withKnownIssue` is GREEN while a trigger fires (the out-of-process `swiftc`
// aborts with the verifier error on the current toolchain) and flips RED the
// moment an upstream fix lands and that trigger compiles cleanly.
//
// The canonical trigger reproduces on every toolchain and platform sampled
// (Apple Swift 6.3.2 through 6.5-dev on macOS arm64; Swift 6.3.1-RELEASE and
// 6.4-dev nightly on Linux aarch64). All three fire on Apple Swift 6.4.2 on
// macOS arm64 (2026-10-27). The `when:` precondition is therefore the
// unconditional "a compiler is reachable" probe.

@Suite
struct NoncopyableRawLayoutTrailingFieldReproducer {

    static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // issue root
        .appendingPathComponent("Sources/Reproducer")

    /// Runs `swiftc` with `arguments` in `directory`. Returns `nil` if the
    /// compiler could not be launched.
    static func swiftc(_ arguments: [String], in directory: URL) -> (status: Int32, stderr: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc"] + arguments
        process.currentDirectoryURL = directory
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do { try process.run() } catch { return nil }
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// `true` if the verifier rejected the IR, `false` if the source compiled,
    /// `nil` if the compiler was unreachable or failed for another reason.
    static func classify(_ result: (status: Int32, stderr: String)?) -> Bool? {
        guard let result else { return nil }
        if result.stderr.contains("does not dominate all uses") || result.stderr.contains("Broken module") {
            return true
        }
        if result.status == 0 { return false }
        return nil
    }

    /// Creates a fresh temp directory, copies each `(resource, stagedName)`
    /// into it as a `.swift` file, and runs `body` with the directory.
    static func withStaged(
        _ tag: String,
        _ files: [(String, String)],
        _ body: (URL) -> Bool?
    ) -> Bool? {
        let pid = ProcessInfo.processInfo.processIdentifier
        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawlayout-trailing-test-\(tag)-\(pid)")
        try? FileManager.default.removeItem(at: work)
        guard (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: work) }
        for (resource, name) in files {
            let source = sources.appendingPathComponent(resource)
            guard FileManager.default.fileExists(atPath: source.path) else { return nil }
            guard (try? FileManager.default.copyItem(at: source, to: work.appendingPathComponent(name))) != nil else {
                return nil
            }
        }
        return body(work)
    }

    static func crashFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            return withStaged("crash", [("Crash.swift.txt", "Crash.swift")]) { work in
                classify(
                    swiftc(
                        [
                            "-O",
                            "-enable-experimental-feature", "RawLayout",
                            "-enable-experimental-feature", "ValueGenerics",
                            "Crash.swift", "-o", "crash.out",
                        ],
                        in: work
                    )
                )
            }
        #else
            return nil  // no subprocess facility
        #endif
    }

    static func accessLevelFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            return withStaged("access", [("AccessLevel.swift.txt", "AccessLevel.swift")]) { work in
                classify(
                    swiftc(
                        [
                            "-swift-version", "6", "-O", "-wmo",
                            "-enable-experimental-feature", "RawLayout",
                            "AccessLevel.swift", "-o", "access-level.out",
                        ],
                        in: work
                    )
                )
            }
        #else
            return nil  // no subprocess facility
        #endif
    }

    static func crossModuleFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let files = [
                ("CrossModuleCore.swift.txt", "CrossModuleCore.swift"),
                ("CrossModuleMiddleware.swift.txt", "CrossModuleMiddleware.swift"),
            ]
            return withStaged("cross", files) { work in
                let flags = [
                    "-swift-version", "6", "-O", "-wmo", "-parse-as-library",
                    "-enable-experimental-feature", "RawLayout",
                ]
                let core = swiftc(
                    flags + [
                        "-module-name", "Bug1Core",
                        "-emit-module", "-emit-module-path", "Bug1Core.swiftmodule",
                        "CrossModuleCore.swift", "-c", "-o", "core.o",
                    ],
                    in: work
                )
                // Module 1 must build; if it does not, the probe says nothing.
                guard let core, core.status == 0 else { return nil }
                return classify(
                    swiftc(
                        flags + [
                            "-I", ".", "-module-name", "Bug1Middleware",
                            "CrossModuleMiddleware.swift", "-c", "-o", "middleware.o",
                        ],
                        in: work
                    )
                )
            }
        #else
            return nil  // no subprocess facility
        #endif
    }

    static func expectStillBroken(_ trigger: String, _ fired: Bool?) {
        guard let fired else {
            // No reachable compiler, or an unrelated failure — nothing to assert.
            return
        }
        withKnownIssue(
            "swiftlang/swift#PENDING — ~Copyable @_rawLayout trailing-field value-witness dominance violation (\(trigger))",
            { #expect(fired == false) },
            // `when: { true }`, NOT `{ fired }`: the `guard let fired … else { return }`
            // above already skips unreachable / N-A platforms, so known-issue matching must
            // stay ACTIVE when the bug stops firing — that is what flips the leg RED on an
            // upstream fix (the cron's whole purpose). `{ fired }` disables matching on a fix,
            // leaves the body passing, and stays GREEN forever (empirically verified). The
            // "Broken module" verifier error is target-independent (it runs pre-lowering), so
            // this fires on x86_64 CI legs too, per the arch-independence noted above.
            when: { true }
        )
    }

    @Test
    func reproducer() {
        Self.expectStillBroken("scalar trailing field, -O", Self.crashFires())
    }

    @Test
    func publicTypesUnderWholeModuleOptimization() {
        Self.expectStillBroken("public types, -O -wmo", Self.accessLevelFires())
    }

    @Test
    func twoRawLayoutFieldsAcrossModules() {
        Self.expectStillBroken("two raw-layout fields across modules, -O -wmo", Self.crossModuleFires())
    }
}
