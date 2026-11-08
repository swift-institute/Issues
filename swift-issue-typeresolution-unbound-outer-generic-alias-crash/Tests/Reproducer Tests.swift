import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// `swift-frontend` segfaults in `TypeResolution::applyUnboundGenericArguments`
// when a generic typealias is named through its generic outer type with the
// outer's arguments left out (`F.B<Int>` for `struct F<V> { typealias B<U> = U }`).
// `Crash.swift.txt` crashes the compiler, so it is type-checked OUT OF PROCESS
//.
//
// Fires on 6.3.1 and 6.4.2 (the only toolchains run), so `when: { true }`: the
// test stays green while the compiler crashes and flips red once it accepts the
// source or reports an ordinary diagnostic.

@Suite
struct TypeResolutionUnboundOuterGenericAliasCrashReproducer {

    /// `true` when swift-frontend crashed resolving the type, `false` when it
    /// type-checked cleanly or diagnosed, `nil` when inconclusive.
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let crashSource = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // issue root
                .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

            guard FileManager.default.fileExists(atPath: crashSource.path) else { return nil }

            let pid = ProcessInfo.processInfo.processIdentifier
            let swiftCopy = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("unbound-outer-generic-alias-test-\(pid).swift")
            try? FileManager.default.removeItem(at: swiftCopy)
            guard (try? FileManager.default.copyItem(at: crashSource, to: swiftCopy)) != nil else {
                return nil
            }
            defer { try? FileManager.default.removeItem(at: swiftCopy) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc", "-typecheck", "-swift-version", "6", swiftCopy.path]
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = Pipe()

            resolveEnv(process)
            do { try process.run() } catch { return nil }
            let errText =
                String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            process.waitUntilExit()

            if errText.contains("Stack dump") && errText.contains("ResolveTypeRequest") { return true }
            if process.terminationStatus == 0 || errText.contains("error:") { return false }
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }

        withKnownIssue(
            "Type resolution: segfault in applyUnboundGenericArguments for a generic alias through an unbound outer generic",
            { #expect(fired == false) },
            when: { Self.beforeFix }
        )
    }

    /// Fixed on main before 6.5 (swiftlang/swift#93642, merged 2026-10-28); every 6.4 toolchain still has it. From 6.5 on,
    /// the bug firing again is a regression and fails the test.
    static var beforeFix: Bool {
        #if compiler(>=6.5)
            return false
        #else
            return true
        #endif
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
