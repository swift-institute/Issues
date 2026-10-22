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

    /// `xcode-<version>` runs the command as written, through that Xcode (see
    /// `environment(for:)`); `windows-<name>` runs it on the toolchain on
    /// `PATH`, which CI installed; anything else runs through
    /// `swiftly run … +<name>`.
    public static func arguments(_ command: [String], on toolchain: String) -> [String] {
        if toolchain.hasPrefix("xcode") { return command }
        let tool = command.first == "xcrun" ? Array(command.dropFirst()) : command
        if Platform(toolchain: toolchain) == .windows { return tool }
        return ["swiftly", "run"] + tool + ["+" + toolchain]
    }

    /// The environment that runs `toolchain`: for `xcode-<version>`, the
    /// installed Xcode of exactly that version, selected through
    /// `DEVELOPER_DIR`; nil when that Xcode is not installed, so a row never
    /// silently runs a different Xcode. For `windows-<name>`, the inherited
    /// environment when the toolchain on `PATH` is that one, and nil on any
    /// other host or toolchain.
    public static func environment(for toolchain: String) -> [String: String]?? {
        var environment = ProcessInfo.processInfo.environment
        if Platform(toolchain: toolchain) == .windows {
            #if os(Windows)
            let version = (try? Invocation(arguments: ["swiftc", "--version"], directory: URL(fileURLWithPath: NSTemporaryDirectory()), timeout: 60).run())?
                .output.components(separatedBy: .newlines).first { $0.contains("Swift version") } ?? ""
            return Platform.isWindowsToolchain(toolchain, version: version) ? .some(nil) : .none
            #else
            return .none
            #endif
        }
        guard toolchain.hasPrefix("xcode-") else { return .some(nil) }
        let version = String(toolchain.dropFirst("xcode-".count))
        // The selected Xcode first, so that of two installs of one version
        // (a beta and a release) the one the machine uses wins.
        let selected = (try? Invocation(arguments: ["xcode-select", "-p"], directory: URL(fileURLWithPath: "/"), timeout: 30).run())?
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        let applications = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
        let installed = applications.sorted()
            .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
            .map { "/Applications/\($0)/Contents/Developer" }
        for developer in [selected].compactMap({ $0 }).filter({ !$0.isEmpty }) + installed {
            environment["DEVELOPER_DIR"] = developer
            let invocation = Invocation(arguments: ["xcodebuild", "-version"], directory: URL(fileURLWithPath: "/"), environment: environment, timeout: 60)
            guard let first = (try? invocation.run())?.output.components(separatedBy: "\n").first else { continue }
            // "Xcode 27.2" matches xcode-27.2; "Xcode 27.2.1" does not.
            if first == "Xcode \(version)" || first == "Xcode \(version).0" { return .some(environment) }
        }
        return .none
    }

    public func run(timeout: TimeInterval = 600) throws -> [Row] {
        var rows: [Row] = []
        var reference: Signature?
        for toolchain in toolchains {
            guard case .some(let environment) = Matrix.environment(for: toolchain) else {
                rows.append(Row(toolchain: toolchain, version: "not installed here", result: "not run", signature: Signature(crashed: false, assertion: nil, phase: nil, frames: [])))
                continue
            }
            let probe = Reduction(command: command, fileName: fileName, signature: Signature(crashed: false, assertion: nil, phase: nil, frames: []), timeout: timeout, environment: environment)
            let version = try probe.invoke(source: "", command: Matrix.arguments(["xcrun", "swiftc", "--version"], on: toolchain)).output
                .components(separatedBy: .newlines).first { $0.contains("Swift version") }
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
