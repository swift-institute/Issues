import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
    import Foundation
#endif

// Converting a `borrowing` class parameter to `AnyObject` (Sources/Reproducer/Crash.swift.txt).
// A release toolchain crashes in MoveOnlyTypeEliminator ("Unhandled SIL Instruction" on an
// `init_existential_ref`); an assertions toolchain's SIL verifier rejects the same
// `init_existential_ref` of a `@moveOnly` value first.
//
// Fixed means it compiles, or ends with the move checker's "is borrowed and cannot be consumed"
// error, which is what swiftlang/swift#90656 (backed out by #91552) produced for this source.
@Suite
struct BorrowingClassToAnyObjectConversionReproducer {
    static func bugFires() -> Bool? {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)
            let here = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let source = here.appendingPathComponent("Sources/Reproducer/Crash.swift.txt")
            let identifier = ProcessInfo.processInfo.processIdentifier
            let staged = FileManager.default.temporaryDirectory
                .appendingPathComponent("borrowing-class-to-anyobject-\(identifier).swift")
            let object = FileManager.default.temporaryDirectory
                .appendingPathComponent("borrowing-class-to-anyobject-\(identifier).o")
            defer {
                try? FileManager.default.removeItem(at: staged)
                try? FileManager.default.removeItem(at: object)
            }
            do {
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.copyItem(at: source, to: staged)
            } catch {
                Issue.record("could not stage \(source.path): \(error)")
                return nil
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swiftc", "-c", staged.path, "-o", object.path]
            let output = Pipe()
            process.standardError = output
            process.standardOutput = output
            do {
                resolveEnv(process)
                try process.run()
            } catch {
                Issue.record("could not run swiftc: \(error)")
                return nil
            }
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            process.waitUntilExit()

            if text.contains("Unhandled SIL Instruction") && text.contains("init_existential_ref") {
                return true
            }
            if text.contains("SIL verification failed: init_existential_ref") && text.contains("$@moveOnly") {
                return true
            }
            if process.terminationReason == .exit, process.terminationStatus == 0 {
                return false
            }
            if process.terminationReason == .exit, process.terminationStatus == 1,
                text.contains("is borrowed and cannot be consumed")
            {
                return false
            }
            Issue.record("swiftc failed without the record's markers (exit \(process.terminationStatus)):\n\(text.suffix(3000))")
            return nil
        #else
            return nil
        #endif
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else {
            Issue.record("no verdict: the reproduction could not be staged, built or run here (a reason recorded above, if any, says why)")
            return
        }

        withKnownIssue(
            "swift-institute/Issues#3: converting a borrowing class parameter to AnyObject crashes MoveOnlyTypeEliminator",
            { #expect(fired == false) },
            when: { true }
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
