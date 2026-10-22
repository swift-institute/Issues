import Foundation

/// Runs a report's minimal reproduction on the toolchain it names, and says
/// whether the output still shows the report's signature.
public struct Reproduction: Sendable {
    public var source: String
    public var fileName: String
    public var command: [String]
    public var toolchain: String
    public var signature: Signature

    public init?(report: Report) {
        guard let source = report.source, let fileName = report.fileName, let commandLine = report.commandLine,
              let signature = report.signature, !report[.reproducesOn].isEmpty
        else { return nil }
        self.source = source
        self.fileName = fileName
        self.command = commandLine.split(separator: " ").map(String.init)
        self.toolchain = report[.reproducesOn]
        self.signature = signature
    }

    /// The command as run: through `swiftly run … +<toolchain>` for a swiftly
    /// toolchain, as written for `xcode-<version>`.
    public var arguments: [String] {
        Matrix.arguments(command, on: toolchain)
    }

    public struct Outcome: Sendable {
        public var reproduced: Bool
        public var version: String
        public var output: String
    }

    public func run(timeout: TimeInterval = 600) throws -> Outcome {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try source.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)

        let versionArguments = toolchain.hasPrefix("xcode-")
            ? ["xcrun", "swiftc", "--version"]
            : ["swiftly", "run", "swiftc", "--version", "+" + toolchain]
        let version = try Invocation(arguments: versionArguments, directory: directory, timeout: 120).run().output
            .components(separatedBy: "\n").first { $0.contains("Swift version") } ?? "unknown"
        var result = try Invocation(arguments: arguments, directory: directory, timeout: timeout).run()
        result.output = Symbolizer.symbolize(result.output)
        return Outcome(reproduced: !result.timedOut && signature.matches(result.output), version: version, output: result.output)
    }
}
