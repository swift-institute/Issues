import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// A generic type witnessing a protocol through `extension Gen: P where
// A == Pool` — a same-type conditional conformance whose subject carries a
// `~Copyable` generic argument — compiles cleanly and crashes at RUNTIME
// (SIGSEGV) when the conforming value's protocol-constrained container is
// used. Still fires on 6.3.3-RELEASE and Apple Swift 6.4 (verified
// 2026-07-30: the compiled reproducer dies on signal 11 on both).
//
// WHY A SUBPROCESS HARNESS
// ------------------------
// The crash is a RUNTIME signal: an in-process reproduction would kill the
// test runner before any known issue could be recorded (the same reason the
// tagged-noncopyable-atomic entry documents). The probe compiles AND runs
// `Sources/reproducer.swift` out of process, so the signal lands in a child.

@Suite
struct NoncopyableSametypeConditionalConformanceReproducer {

    /// Compiles and runs `Sources/reproducer.swift` in child processes.
    /// Returns `true` if the compiled reproducer was killed by a signal,
    /// `false` if it ran to completion, `nil` if inconclusive (compile
    /// failure = broken instrument, not the bug).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/reproducer.swift")
            guard FileManager.default.fileExists(atPath: source.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let binary = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(programName("sametype-conformance-test-\(pid)"))
            defer { try? FileManager.default.removeItem(at: binary) }

            func run(
                _ executable: String,
                _ arguments: [String]
            ) -> (
                signaled: Bool, status: Int32
            )? {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.environment = withToolchainRuntime(ProcessInfo.processInfo.environment)
                process.arguments = arguments
                process.standardError = Pipe()
                process.standardOutput = Pipe()
                resolveEnv(process)
                do { try process.run() } catch { return nil }
                process.waitUntilExit()
                return (process.terminationReason == .uncaughtSignal, process.terminationStatus)
            }

            guard let compile = run("/usr/bin/env", ["swiftc", source.path, "-o", binary.path]),
                !compile.signaled, compile.status == 0
            else { return nil }
            guard let execution = run(binary.path, []) else { return nil }
            return execution.signaled
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }
        withKnownIssue(
            "~Copyable same-type conditional conformance: compiled reproducer crashes at runtime (SIGSEGV)",
            { #expect(fired == false) },
            when: { true }
        )
    }
}

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    /// On macOS, a program built by a toolchain other than Xcode's still loads the system's
    /// Swift runtime, so a snapshot run would test the system's runtime, not the snapshot's.
    /// When the `swiftc` on PATH belongs to such a toolchain, point the loader at its runtime.
    /// Elsewhere, and for Xcode's toolchain, the environment is returned unchanged.
    func withToolchainRuntime(_ environment: [String: String]) -> [String: String] {
        #if os(macOS)
            for directory in (environment["PATH"] ?? "").split(separator: ":") {
                let swiftc = URL(fileURLWithPath: String(directory)).appendingPathComponent("swiftc")
                guard FileManager.default.isExecutableFile(atPath: swiftc.path) else { continue }
                let resolved = swiftc.resolvingSymlinksInPath()
                guard !resolved.path.contains(".app/Contents/Developer") else { return environment }
                let runtime = resolved.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("lib/swift/macosx")
                guard FileManager.default.fileExists(atPath: runtime.appendingPathComponent("libswiftCore.dylib").path)
                else { return environment }
                var environment = environment
                environment["DYLD_LIBRARY_PATH"] = runtime.path
                return environment
            }
        #endif
        return environment
    }
#endif

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    /// `/usr/bin/env` does not exist on Windows. There, a process set up to run a tool
    /// through it runs the tool found on Path instead; elsewhere nothing changes.
    func resolveEnv(_ process: Process) {
        #if os(Windows)
            guard process.executableURL?.path.hasSuffix("/usr/bin/env") == true,
                let arguments = process.arguments, let name = arguments.first
            else { return }
            let path = ProcessInfo.processInfo.environment["Path"] ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
            for directory in path.split(separator: ";") {
                let candidate = URL(fileURLWithPath: String(directory))
                    .appendingPathComponent(name.hasSuffix(".exe") ? name : "\(name).exe")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    process.executableURL = candidate
                    process.arguments = Array(arguments.dropFirst())
                    return
                }
            }
        #endif
    }

    /// A program's file name: swiftc writes exactly the -o path, so on Windows it ends in .exe.
    func programName(_ base: String) -> String {
        #if os(Windows)
            return "\(base).exe"
        #else
            return base
        #endif
    }
#endif
