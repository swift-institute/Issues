import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation

    @Suite
    struct MacroConformancePublicImportAccountingReproducer {
        /// Runs the standalone reproducer; `true` when `public import` is reported unused.
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
        func `A public conformance added by a macro counts toward public import use`() throws {
            guard let fired = try Self.bugFires() else { return }
            withKnownIssue(
                "Swift: macro-generated public declarations do not count toward public import accounting",
                { #expect(!fired) },
                when: { Self.beforeFix }
            )
        }

        /// Fixed on main before 6.5 (clean on main-snapshot-2026-10-27; fix PR not identified); every 6.4 toolchain still has it. From 6.5 on,
        /// the bug firing again is a regression and fails the test.
        static var beforeFix: Bool {
            #if compiler(>=6.5)
                return false
            #else
                return true
            #endif
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
