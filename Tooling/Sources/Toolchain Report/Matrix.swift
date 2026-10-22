import Foundation

/// Runs one reproduction on several toolchains and classifies each result
/// against the first toolchain's signature.
public struct Matrix: Sendable {
    public var source: String
    public var fileName: String
    public var command: [String]
    public var toolchains: [String]
    public var frameCount: Int
    /// Text every reproducing run must also print, as with `--require`.
    public var required: [String]

    public init(source: String, fileName: String, command: [String], toolchains: [String], frameCount: Int = 8, required: [String] = []) {
        self.source = source
        self.fileName = fileName
        self.command = command
        self.toolchains = toolchains
        self.frameCount = frameCount
        self.required = required
    }

    public struct Row: Sendable {
        public var toolchain: String
        public var version: String
        public var result: String
        public var signature: Signature
    }

    /// `xcode-<version>` (or `xcode`) runs the command as written, so through
    /// the selected Xcode; anything else runs through `swiftly run … +<name>`.
    public static func arguments(_ command: [String], on toolchain: String) -> [String] {
        if toolchain.hasPrefix("xcode") { return command }
        let tool = command.first == "xcrun" ? Array(command.dropFirst()) : command
        return ["swiftly", "run"] + tool + ["+" + toolchain]
    }

    public func run(timeout: TimeInterval = 600) throws -> [Row] {
        let probe = Reduction(command: command, fileName: fileName, signature: Signature(crashed: false, assertion: nil, phase: nil, frames: []), timeout: timeout)
        var rows: [Row] = []
        var reference: Signature?
        for toolchain in toolchains {
            let version = try probe.invoke(source: "", command: Matrix.arguments(["xcrun", "swiftc", "--version"], on: toolchain)).output
                .components(separatedBy: "\n").first { $0.contains("Swift version") }
                .flatMap { line in line.range(of: "Apple Swift version").map { String(line[$0.lowerBound...]) } ?? line } ?? "unknown"
            let output = try probe.invoke(source: source, command: Matrix.arguments(command, on: toolchain)).output
            let signature = Signature(output: output, frameCount: frameCount)
            let result: String
            if !signature.crashed && required.isEmpty || !required.allSatisfy({ output.contains($0) }) {
                result = "does not reproduce"
            } else if let reference, !reference.sharesDefect(with: signature) {
                result = "different crash"
            } else {
                result = "reproduces" + (signature.assertion.map { " (asserts: \($0))" } ?? "")
            }
            if reference == nil, signature.crashed { reference = signature }
            rows.append(Row(toolchain: toolchain, version: version, result: result, signature: signature))
        }
        return rows
    }

    public static func table(_ rows: [Row]) -> String {
        (["| Toolchain | `swiftc --version` | Result |", "|---|---|---|"]
            + rows.map { "| \($0.toolchain) | \($0.version.trimmingCharacters(in: .whitespaces)) | \($0.result) |" })
            .joined(separator: "\n")
    }
}
