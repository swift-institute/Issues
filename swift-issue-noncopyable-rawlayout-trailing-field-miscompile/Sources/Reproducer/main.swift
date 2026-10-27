// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
// swiftlang/swift (PENDING filing) — standalone exit-code reproducer.
//
// The bug is a COMPILE-TIME abort: compiling the trigger under `-O` aborts
// swift-frontend (signal 6) with an LLVM verifier "Instruction does not
// dominate all uses" on a `~Copyable` value witness. A build-time abort
// cannot be a normal SwiftPM compiled target without breaking the whole
// package, so this executable drives the compiler OUT OF PROCESS against the
// `.swift.txt` resources and reports the result as an exit code.
//
// Three triggers are probed:
//   1. `Crash.swift.txt`        — scalar field after the buffer, `swiftc -O`.
//   2. `AccessLevel.swift.txt`  — public types, `swiftc -O -wmo`.
//   3. `CrossModuleCore.swift.txt` + `CrossModuleMiddleware.swift.txt`
//                                — two raw-layout fields, `-O -wmo`, two modules.
//
// Exit code:
//   1  — bug fired  (at least one trigger aborted with the verifier error)
//   0  — bug absent (every trigger compiled cleanly) or inconclusive
//
// The companion `Tests/Reproducer Tests.swift` wraps the same probes in
// `withKnownIssue` so CI flips red the moment the upstream fix lands.

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let pid = ProcessInfo.processInfo.processIdentifier
    let work = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("rawlayout-trailing-\(pid)")
    try? FileManager.default.removeItem(at: work)

    /// Outcome of one trigger.
    enum Outcome {
        case fired
        case clean
        case inconclusive(String)
    }

    /// swiftc keys off the file extension; copy a `.txt` resource to a
    /// `.swift` file in the work directory so it is compiled as source.
    func stage(_ resource: String, as name: String) -> URL? {
        let source = here.appendingPathComponent(resource)
        let staged = work.appendingPathComponent(name)
        guard (try? FileManager.default.copyItem(at: source, to: staged)) != nil else {
            return nil
        }
        return staged
    }

    /// Runs `swiftc` with `arguments`; returns exit status and stderr, or
    /// `nil` if the compiler could not be launched.
    func swiftc(_ arguments: [String]) -> (status: Int32, stderr: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc"] + arguments
        process.currentDirectoryURL = work
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do { try process.run() } catch { return nil }
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    func classify(_ result: (status: Int32, stderr: String)?) -> Outcome {
        guard let result else { return .inconclusive("could not launch swiftc") }
        if result.stderr.contains("does not dominate all uses") || result.stderr.contains("Broken module") {
            return .fired
        }
        if result.status == 0 { return .clean }
        // Compiler failed for some OTHER reason (e.g. feature flag renamed on a
        // future toolchain). Not the bug under test; do not flip the signal.
        return .inconclusive(result.stderr)
    }

    func probeCrash() -> Outcome {
        guard let source = stage("Crash.swift.txt", as: "Crash.swift") else {
            return .inconclusive("could not stage Crash.swift.txt")
        }
        return classify(
            swiftc([
                "-O",
                "-enable-experimental-feature", "RawLayout",
                "-enable-experimental-feature", "ValueGenerics",
                source.path, "-o", work.appendingPathComponent("crash.out").path,
            ])
        )
    }

    func probeAccessLevel() -> Outcome {
        guard let source = stage("AccessLevel.swift.txt", as: "AccessLevel.swift") else {
            return .inconclusive("could not stage AccessLevel.swift.txt")
        }
        return classify(
            swiftc([
                "-swift-version", "6", "-O", "-wmo",
                "-enable-experimental-feature", "RawLayout",
                source.path, "-o", work.appendingPathComponent("access-level.out").path,
            ])
        )
    }

    func probeCrossModule() -> Outcome {
        guard
            let core = stage("CrossModuleCore.swift.txt", as: "CrossModuleCore.swift"),
            let middleware = stage("CrossModuleMiddleware.swift.txt", as: "CrossModuleMiddleware.swift")
        else {
            return .inconclusive("could not stage the cross-module sources")
        }
        let flags = [
            "-swift-version", "6", "-O", "-wmo", "-parse-as-library",
            "-enable-experimental-feature", "RawLayout",
        ]
        // Module 1 must build; if it does not, the probe says nothing.
        let coreResult = swiftc(
            flags + [
                "-module-name", "Bug1Core",
                "-emit-module", "-emit-module-path", work.appendingPathComponent("Bug1Core.swiftmodule").path,
                core.path, "-c", "-o", work.appendingPathComponent("core.o").path,
            ]
        )
        guard let coreResult, coreResult.status == 0 else {
            return .inconclusive("Bug1Core did not build:\n\(coreResult?.stderr ?? "")")
        }
        // Module 2 is where the verifier aborts.
        return classify(
            swiftc(
                flags + [
                    "-I", work.path, "-module-name", "Bug1Middleware",
                    middleware.path, "-c", "-o", work.appendingPathComponent("middleware.o").path,
                ]
            )
        )
    }

    do {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    } catch {
        FileHandle.standardError.write(Data("could not create work directory: \(error)\n".utf8))
        exit(0)
    }

    let outcomes: [(String, Outcome)] = [
        ("Crash.swift.txt (swiftc -O)", probeCrash()),
        ("AccessLevel.swift.txt (swiftc -O -wmo)", probeAccessLevel()),
        ("CrossModule*.swift.txt (swiftc -O -wmo, two modules)", probeCrossModule()),
    ]
    try? FileManager.default.removeItem(at: work)

    var anyFired = false
    for (name, outcome) in outcomes {
        switch outcome {
        case .fired:
            anyFired = true
            FileHandle.standardError.write(Data("BUG FIRED: \(name): LLVM verifier rejected the IR.\n".utf8))
        case .clean:
            FileHandle.standardError.write(Data("clean: \(name) compiled; the bug appears FIXED for it.\n".utf8))
        case .inconclusive(let reason):
            FileHandle.standardError.write(Data("inconclusive: \(name):\n\(reason)\n".utf8))
        }
    }
    exit(anyFired ? 1 : 0)

#else

    // No subprocess facility on this platform; nothing to probe.
    print("subprocess probe unavailable on this platform; skipping")

#endif

// swiftlint:enable no_try_optional
