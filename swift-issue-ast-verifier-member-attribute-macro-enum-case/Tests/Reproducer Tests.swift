import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation
#endif

// swift-institute/Issues#175, same root cause as open swiftlang/swift#90139 — an attached
// member-attribute macro's attribute is left on the `EnumCaseDecl` of an enum case, and
// the AST verifier aborts `swift-frontend` with "EnumCaseDecl should not have attributes".
//
// `Crash.swift.txt` is a macro plugin (`-D PLUGIN`, speaking the plugin protocol
// directly, no swift-syntax) and its client in one file. The plugin is built and the
// client type-checked OUT OF PROCESS, because the client aborts the compiler ([ISSUE-029]).
//
// Assertions builds run the AST verifier by default; release toolchains run it with
// `-Xfrontend -enable-ast-verifier`, which this harness passes. The abort is recorded on
// macOS release (Xcode Swift 6.4.2, run locally), on Linux release (Swift 6.4.1-RELEASE
// x86_64, Issues CI run 40584416933) and on assertions builds (Windows 6.4.1, Linux nightly,
// macOS snapshots; CI). It fires wherever this harness runs, so `when:` is `true`.

@Suite
struct ASTVerifierMemberAttributeMacroEnumCaseReproducer {

    static func swiftc(_ arguments: [String]) -> (status: Int32, output: String)? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc"] + arguments
            let output = Pipe()
            process.standardError = output
            process.standardOutput = output
            do { try process.run() } catch { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        #else
            return nil
        #endif
    }

    /// `true` when the AST verifier rejected the attribute, `false` when it accepted the
    /// client, `nil` when inconclusive (including a plugin that did not build).
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
            let crashSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let work = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ast-verifier-enum-case-test-\(pid)")
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
                    "-typecheck", "-Xfrontend", "-enable-ast-verifier",
                    "-load-plugin-executable", "\(plugin.path)#P", source.path,
                ])
            else { return nil }

            if result.output.contains("EnumCaseDecl should not have attributes") { return true }
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
            "swiftlang/swift#90139 (Issues#175) — member-attribute macro attribute left on an EnumCaseDecl; AST verifier aborts",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
