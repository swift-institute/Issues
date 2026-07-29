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

    static func bugFires(sourceName: String) -> Bool? {
        guard let compiler = compilerURL(named: "swiftc") else {
            return nil
        }

        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Reproducer")
            .appendingPathComponent(sourceName)

        guard FileManager.default.fileExists(atPath: source.path) else {
            return nil
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
            return nil
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
            return nil
        }
        process.waitUntilExit()

        let errorText = String(
            data: errorOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if errorText.contains("hasErrorResult()")
            && errorText.contains("IRGenRequest") {
            return true
        }
        if process.terminationStatus == 0 {
            return false
        }
        return nil
    }

    @Test(
        "non-throwing closure conversion emits valid debug IR",
        arguments: sources
    )
    func conversion(sourceName: String) {
        guard let fired = Self.bugFires(sourceName: sourceName) else {
            Issue.record("The Swift compiler subprocess could not be evaluated for \(sourceName).")
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
