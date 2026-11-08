import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation

    @Suite
    struct SPMDiamondTraitConditionalDependencyReproducer {
        /// Runs the standalone reproducer; `true` when SwiftPM fails to resolve the fixture graph.
        static func bugFires() throws -> Bool? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "swift",
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Sources/Reproducer/main.swift").path,
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            resolveEnv(process)
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            // Exit 1 alone is not a verdict: a script that fails to compile exits 1 too.
            switch process.terminationStatus {
            case 1 where output.contains("bug fired"): return true
            case 0: return false
            default:
                Issue.record("the reproducer ended without a verdict (exit \(process.terminationStatus)):\n\(output.suffix(3000))")
                return nil
            }
        }

        @Test
        func `A package reached with and without a trait resolves its trait-gated dependency`()
            throws
        {
            guard let fired = try Self.bugFires() else { return }
            withKnownIssue(
                "SwiftPM: a diamond with and without a trait leaves the trait-gated dependency unresolved"
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

#endif
