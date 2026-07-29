import Testing
import Foundation

@Suite
struct `IRGen Tests` {
    static let sources = [
        "ConstrainedExtension.swift.txt",
        "DirectInitialization.swift.txt",
    ]

    static func compilerURL(named name: String) -> URL? {
        #if os(Windows)
        let candidates = ["\(name).exe", name]
        let separator: Character = ";"
        #else
        let candidates = [name]
        let separator: Character = ":"
        #endif

        let environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? environment["Path"] ?? ""
        for directory in path.split(separator: separator).map(String.init) {
            for candidate in candidates {
                let executable = URL(fileURLWithPath: directory)
                    .appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: executable.path) {
                    return executable
                }
            }
        }
        return nil
    }

    static func compilerHasAssertions() -> Bool {
        guard let compiler = compilerURL(named: "swiftc") else {
            return false
        }

        let process = Process()
        process.executableURL = compiler
        process.arguments = ["--version"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()

        let text = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return text.contains("Build config: +assertions")
    }

    static func isKnownAffectedToolchain() -> Bool {
        #if compiler(<6.5)
        compilerHasAssertions()
        #else
        false
        #endif
    }

    static func bugFires(
        sourceName: String
    ) -> (fired: Bool?, diagnostic: String?) {
        guard let compiler = compilerURL(named: "swiftc") else {
            return (nil, "swiftc was not found on PATH.")
        }

        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Reproducer")
            .appendingPathComponent(sourceName)

        guard FileManager.default.fileExists(atPath: source.path) else {
            return (nil, "\(sourceName) was not found.")
        }

        let identifier = sourceName.replacingOccurrences(of: ".swift.txt", with: "")
        let processID = ProcessInfo.processInfo.processIdentifier
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        let swiftSource = temporary
            .appendingPathComponent("irgen-typed-throws-\(identifier)-\(processID).swift")
        let object = temporary
            .appendingPathComponent("irgen-typed-throws-\(identifier)-\(processID).o")

        try? FileManager.default.removeItem(at: swiftSource)
        guard (try? FileManager.default.copyItem(at: source, to: swiftSource)) != nil else {
            return (nil, "\(sourceName) could not be copied for compilation.")
        }
        defer {
            try? FileManager.default.removeItem(at: swiftSource)
            try? FileManager.default.removeItem(at: object)
        }

        let process = Process()
        process.executableURL = compiler
        process.arguments = [
            "-g",
            "-Onone",
            "-swift-version", "6",
            "-c", swiftSource.path,
            "-o", object.path,
        ]

        let errorOutput = Pipe()
        process.standardError = errorOutput
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            return (nil, "swiftc could not be launched: \(error)")
        }
        process.waitUntilExit()

        let errorText = String(
            data: errorOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if errorText.contains("hasErrorResult()")
            && errorText.contains("IRGenRequest") {
            return (true, nil)
        }
        if process.terminationStatus == 0 {
            return (false, nil)
        }
        return (
            nil,
            """
            swiftc exited with status \(process.terminationStatus):
            \(errorText)
            """
        )
    }

    @Test(
        "non-throwing closure conversion emits valid debug IR",
        arguments: sources
    )
    func conversion(sourceName: String) {
        let result = Self.bugFires(sourceName: sourceName)
        guard let fired = result.fired else {
            Issue.record(
                """
                The Swift compiler subprocess could not be evaluated for \(sourceName).
                \(result.diagnostic ?? "No compiler diagnostic was emitted.")
                """
            )
            return
        }

        withKnownIssue(
            "swiftlang/swift#87030 — stray $error debug_value crashes IRGen; fixed by swiftlang/swift#90789",
            {
                #expect(fired == false)
            },
            when: {
                Self.isKnownAffectedToolchain()
            }
        )
    }
}
