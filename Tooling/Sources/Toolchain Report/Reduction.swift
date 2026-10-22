import Foundation

/// A mechanical reduction of a single-file toolchain failure.
///
/// Every step is a deletion or simplification proposed by `Edit.candidates`
/// (or the removal of a command argument). A step is kept only if the command
/// still fails with the same `signature`; the reduction stops at a fixed
/// point, a full pass in which no step is kept.
public struct Reduction: Sendable {
    /// The command; the token `{}` stands for the source file.
    public var command: [String]
    public var fileName: String
    public var signature: Signature
    public var timeout: TimeInterval
    public var jobs: Int
    public var reducesArguments: Bool
    public var environment: [String: String]?
    public var log: @Sendable (String) -> Void

    public init(
        command: [String],
        fileName: String,
        signature: Signature,
        timeout: TimeInterval = 120,
        jobs: Int = 4,
        reducesArguments: Bool = true,
        environment: [String: String]? = nil,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.command = command
        self.fileName = fileName
        self.signature = signature
        self.timeout = timeout
        self.jobs = max(1, jobs)
        self.reducesArguments = reducesArguments
        self.environment = environment
        self.log = log
    }

    public struct Outcome: Sendable {
        public var source: String
        public var command: [String]
        public var steps: Int
        public var tests: Int
        public var passes: Int
    }

    /// Runs `command` on `source` once and returns the combined output.
    public func invoke(source: String, command: [String]) throws -> Invocation.Result {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue-reduce-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try source.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        let arguments = command.map { $0.replacingOccurrences(of: "{}", with: fileName) }
        var result = try Invocation(arguments: arguments, directory: directory, environment: environment, timeout: timeout).run()
        result.output = Symbolizer.symbolize(result.output)
        return result
    }

    public func isInteresting(source: String, command: [String]) -> Bool {
        guard let result = try? invoke(source: source, command: command), !result.timedOut else { return false }
        return signature.matches(result.output)
    }

    /// Of `variants`, the index of the first that keeps the signature, testing
    /// up to `jobs` at a time.
    func firstInteresting(_ variants: [(source: String, command: [String])], tests: inout Int) -> Int? {
        var start = 0
        while start < variants.count {
            let batch = Array(variants[start..<min(start + jobs, variants.count)])
            let results = Results(count: batch.count)
            DispatchQueue.concurrentPerform(iterations: batch.count) { index in
                results.set(index, isInteresting(source: batch[index].source, command: batch[index].command))
            }
            tests += batch.count
            if let hit = results.values.firstIndex(of: true) { return start + hit }
            start += batch.count
        }
        return nil
    }

    public func run(source original: String) throws -> Outcome {
        var source = original
        var command = command
        var steps = 0
        var tests = 0
        var passes = 0

        guard isInteresting(source: source, command: command) else {
            throw Failure.notReproduced
        }

        let stripped = Edit.stripped(source)
        if stripped != source, isInteresting(source: stripped, command: command) {
            source = stripped
            steps += 1
            log("strip comments → \(source.utf8.count) bytes")
        }

        var changed = true
        while changed {
            changed = false
            passes += 1
            var rejected = Set<String>()

            // Source edits, largest first, restarting after each kept step.
            while true {
                let candidates = Edit.candidates(in: source).filter { !rejected.contains($0.key) }
                if candidates.isEmpty { break }
                let bytes = Array(source.utf8)
                var kept = false
                var start = 0
                while start < candidates.count {
                    let batch = Array(candidates[start..<min(start + jobs * 4, candidates.count)])
                    let variants = batch.map { (source: String(decoding: $0.apply(to: bytes), as: UTF8.self), command: command) }
                    if let hit = firstInteresting(variants, tests: &tests) {
                        for edit in batch[..<hit] { rejected.insert(edit.key) }
                        source = variants[hit].source
                        steps += 1
                        changed = true
                        kept = true
                        log("pass \(passes): \(batch[hit].kind) (−\(batch[hit].removedBytes)) → \(source.utf8.count) bytes")
                        break
                    }
                    for edit in batch { rejected.insert(edit.key) }
                    start += batch.count
                }
                if !kept { break }
            }

            // Command arguments: drop flag-and-value pairs, then single tokens.
            if reducesArguments {
                var index = 1
                while index < command.count {
                    if command[index].contains("{}") { index += 1; continue }
                    var variants: [[String]] = []
                    if index + 1 < command.count, command[index].hasPrefix("-"),
                       !command[index + 1].hasPrefix("-"), !command[index + 1].contains("{}") {
                        variants.append(Array(command[..<index]) + Array(command[(index + 2)...]))
                    }
                    variants.append(Array(command[..<index]) + Array(command[(index + 1)...]))
                    if let hit = firstInteresting(variants.map { (source: source, command: $0) }, tests: &tests) {
                        log("pass \(passes): drop argument \(command[index]) → \(variants[hit].joined(separator: " "))")
                        command = variants[hit]
                        steps += 1
                        changed = true
                    } else {
                        index += 1
                    }
                }
            }
        }

        return Outcome(source: source, command: command, steps: steps, tests: tests, passes: passes)
    }

    public enum Failure: Error, CustomStringConvertible {
        case notReproduced

        public var description: String {
            switch self {
            case .notReproduced: "the input does not show the signature with this command; nothing to reduce"
            }
        }
    }
}

final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool]

    init(count: Int) { storage = Array(repeating: false, count: count) }

    func set(_ index: Int, _ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        storage[index] = value
    }

    var values: [Bool] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
