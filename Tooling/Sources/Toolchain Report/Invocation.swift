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

    /// Runs through `/usr/bin/env`, so the first argument is looked up on `PATH`.
    public func run() throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
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
