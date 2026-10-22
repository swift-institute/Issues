import Foundation

/// One command run to completion or timeout, with stdout and stderr combined.
public struct Invocation: Sendable {
    public var arguments: [String]
    public var directory: URL
    public var environment: [String: String]?
    public var timeout: TimeInterval

    public init(arguments: [String], directory: URL, environment: [String: String]? = nil, timeout: TimeInterval = 120) {
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
        self.timeout = timeout
    }

    public struct Result: Sendable {
        public var status: Int32
        public var output: String
        public var timedOut: Bool
    }

    /// Runs the first argument, looked up on `PATH` unless it is a path. A
    /// command that is not found exits 127, as from a shell.
    public func run() throws -> Result {
        let name = arguments.first ?? ""
        guard let executable = Invocation.executable(name, environment: environment ?? ProcessInfo.processInfo.environment) else {
            return Result(status: 127, output: "\(name): command not found on PATH\n", timedOut: false)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = Array(arguments.dropFirst())
        process.currentDirectoryURL = directory
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let collected = Collected()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collected.append(data) }
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            process.waitUntilExit()
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        collected.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return Result(status: process.terminationStatus, output: collected.string, timedOut: timedOut)
    }
}

extension Invocation {
    /// `name` as an executable file: itself when it is a path, else the first
    /// match on `PATH`. On Windows, `PATH` is `Path` and `;`-separated, and a
    /// name without an extension also matches with each of `PATHEXT`'s.
    static func executable(_ name: String, environment: [String: String]) -> URL? {
        #if os(Windows)
        let separator: Character = ";"
        let isPath = name.contains("/") || name.contains("\\")
        func variable(_ key: String) -> String? {
            environment.first { $0.key.uppercased() == key }?.value
        }
        let extensions = URL(fileURLWithPath: name).pathExtension.isEmpty
            ? (variable("PATHEXT") ?? ".EXE;.CMD;.BAT").split(separator: ";").map(String.init)
            : [""]
        #else
        let separator: Character = ":"
        let isPath = name.contains("/")
        func variable(_ key: String) -> String? { environment[key] }
        let extensions = [""]
        #endif
        if isPath { return URL(fileURLWithPath: name) }
        for directory in (variable("PATH") ?? "").split(separator: separator) {
            for suffix in extensions {
                let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name + suffix)
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }
}

final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    var string: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
