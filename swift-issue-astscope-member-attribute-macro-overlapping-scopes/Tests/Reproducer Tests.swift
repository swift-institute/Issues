import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// swift-institute/Issues#157 (not filed upstream) — when an attached member-attribute
// macro returns two custom attributes for one member, an assertions-enabled
// `swift-frontend` aborts in ASTScope verification: "child overlaps previous child"
// between the two generated `CustomAttributeScope`s (ASTScopePrinting.cpp).
//
// `Crash.swift.txt` is a macro plugin (`-D PLUGIN`, speaking the plugin protocol
// directly, no swift-syntax) and its client in one file. The plugin is built and the
// client type-checked OUT OF PROCESS, because the client aborts the compiler.
//
// Only assertions builds run the ASTScope verifier. Release toolchains accept the client,
// so their clean result says nothing about a fix. `when:` is therefore "this swiftc is an
// assertions build" (`swiftc --version` prints `Build config: +assertions`): green while
// the abort fires there, red once an assertions toolchain accepts the client. On a
// release toolchain the body runs unguarded and passes.

@Suite
struct ASTScopeMemberAttributeMacroOverlappingScopesReproducer {

    static func swiftc(_ arguments: [String]) -> (status: Int32, output: String)? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc"] + arguments
            let output = Pipe()
            process.standardError = output
            process.standardOutput = output
            resolveEnv(process)
            do { try process.run() } catch { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        #else
            return nil
        #endif
    }

    /// `true` when the `swiftc` on PATH is an assertions build.
    static func assertionsToolchain() -> Bool {
        swiftc(["--version"])?.output.contains("+assertions") ?? false
    }

    /// `true` when swiftc aborted with the scope overlap, `false` when it accepted the
    /// client, `nil` when inconclusive (including a plugin that did not build).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let crashSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let work = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("astscope-member-attribute-test-\(pid)")
            try? FileManager.default.removeItem(at: work)
            guard (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil
            else { return nil }
            defer { try? FileManager.default.removeItem(at: work) }

            let source = work.appendingPathComponent("repro.swift")
            let plugin = work.appendingPathComponent("plugin")
            guard (try? FileManager.default.copyItem(at: crashSource, to: source)) != nil else {
                return nil
            }

            guard let built = swiftc(["-D", "PLUGIN", source.path, "-o", plugin.path]),
                built.status == 0
            else { return nil }

            guard
                let result = swiftc([
                    "-typecheck", "-load-plugin-executable", "\(plugin.path)#P", source.path,
                ])
            else { return nil }

            if result.output.contains("child overlaps previous child") { return true }
            if result.status == 0 { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "Issues#157 — ASTScope verifier: child overlaps previous child for macro-generated attributes (assertions builds)",
            { #expect(fired == false) },
            when: { Self.assertionsToolchain() }
        )
    }
}

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
