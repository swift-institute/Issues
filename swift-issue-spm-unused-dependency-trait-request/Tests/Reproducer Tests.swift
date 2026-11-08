import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation

    @Suite
    struct SPMUnusedDependencyTraitRequestReproducer {
        /// Runs the standalone reproducer; `true` when SwiftPM fails to resolve its graph.
        static func bugFires() throws -> Bool? {
            let script = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("repro.swift")
            // Compiled, then run: `swift <file>` runs it in the interpreter, whose JIT
            // can't load Foundation on Windows.
            let program = FileManager.default.temporaryDirectory
                .appendingPathComponent(programName("issue-211-\(ProcessInfo.processInfo.processIdentifier)"))
            // REASON: best-effort cleanup of a scratch file.
            // swiftlint:disable:next no_try_optional
            defer { try? FileManager.default.removeItem(at: program) }
            let build = try launch(URL(fileURLWithPath: "/usr/bin/env"), ["swiftc", script.path, "-o", program.path])
            guard build.status == 0 else {
                Issue.record("the reproducer didn't compile (exit \(build.status)):\n\(build.output.suffix(3000))")
                return nil
            }
            let result = try launch(program, [])
            // Exit 1 alone is not a verdict: a crash or a failed step can exit 1 too.
            switch result.status {
            case 1 where result.output.contains("exhausted attempts to resolve the dependencies graph"): return true
            case 0: return false
            default:
                Issue.record("the reproducer ended without a verdict (exit \(result.status)):\n\(result.output.suffix(3000))")
                return nil
            }
        }

        // REASON: Process.run() throws an untyped Foundation error.
        // swiftlint:disable:next typed_throws_required
        static func launch(_ executable: URL, _ arguments: [String]) throws -> (status: Int32, output: String) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            resolveEnv(process)
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }

        @Test
        func `A trait requested on an unused dependency does not leave its guarded dependency unresolved`()
            throws
        {
            guard let fired = try Self.bugFires() else { Issue.record("no verdict: the reproduction could not be staged, built or run here (a reason recorded above, if any, says why)"); return }
            withKnownIssue(
                "SwiftPM: a trait requested on a dependency no target uses requires the dependency it guards, which is never resolved"
            ) {
                #expect(!fired)
            }
        }
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
