import Foundation
import Toolchain_Report

let usage = """
    USAGE: issue-reduce <input.swift> [options] -- <command, with {} for the file>

    Reduces a single-file toolchain failure to a fixed point. A step is kept
    only while the command still fails with the input's signature: assertion
    text, innermost pretty-stack phase, and the top stack frames.

    OPTIONS:
      -o, --output <path>    Reduced file (default: <input>.reduced.swift)
      --frames <n>           Stack frames in the signature (default: 4)
      --require <text>       Output must also contain <text>; repeatable.
                             Alone, it reduces a diagnostic, not a crash.
      --timeout <seconds>    Per-run timeout (default: 120)
      --jobs <n>             Runs in parallel (default: half the cores)
      --keep-arguments       Do not try to drop command arguments
      --signature            Print the input's signature and stop
      --matrix <a,b,...>     Run the input on these toolchains (swiftly names, or
                             xcode for the selected Xcode) and print the matrix

    EXAMPLE:
      issue-reduce all.swift -- xcrun swiftc -O -wmo -DDEBUG -c {} -o /dev/null
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let separator = arguments.firstIndex(of: "--") else { fail(usage) }
let command = Array(arguments[(separator + 1)...])
arguments = Array(arguments[..<separator])
guard !command.isEmpty, command.contains(where: { $0.contains("{}") }) else { fail("The command must contain {} for the file.\n\n" + usage) }

var input: String?
var output: String?
var frames = 4
var required: [String] = []
var timeout: TimeInterval = 120
var jobs = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
var reducesArguments = true
var signatureOnly = false
var matrix: [String] = []

var options = arguments.makeIterator()
while let argument = options.next() {
    func value() -> String {
        guard let next = options.next() else { fail("Missing value for \(argument).") }
        return next
    }
    switch argument {
    case "-o", "--output": output = value()
    case "--frames": frames = Int(value()) ?? frames
    case "--require": required.append(value())
    case "--timeout": timeout = TimeInterval(value()) ?? timeout
    case "--jobs": jobs = Int(value()) ?? jobs
    case "--keep-arguments": reducesArguments = false
    case "--signature": signatureOnly = true
    case "--matrix": matrix = value().split(separator: ",").map(String.init)
    case "-h", "--help": print(usage); exit(0)
    case _ where input == nil && !argument.hasPrefix("-"): input = argument
    default: fail("Unknown option \(argument).\n\n" + usage)
    }
}
guard let input else { fail(usage) }

let inputURL = URL(fileURLWithPath: input)
guard let source = try? String(contentsOf: inputURL, encoding: .utf8) else { fail("Cannot read \(input).") }
let fileName = inputURL.lastPathComponent

if !matrix.isEmpty {
    let rows = try Matrix(source: source, fileName: fileName, command: command, toolchains: matrix, required: required).run()
    for row in rows { print("\(row.toolchain):\n\(row.signature)\n") }
    print(Matrix.table(rows))
    exit(0)
}

// The signature comes from the input itself, never from a quoted log.
let probe = Reduction(command: command, fileName: fileName, signature: Signature(crashed: false, assertion: nil, phase: nil, frames: []), timeout: timeout)
let first = try probe.invoke(source: source, command: command)
let signature = Signature(output: first.output, frameCount: frames, required: required)
print("Signature of \(fileName) (exit \(first.status)):\n\(signature)\n")
if signatureOnly { exit(0) }
guard signature.crashed || !required.isEmpty else {
    fail("The input does not crash with this command; pass --require <text> to reduce a diagnostic instead.")
}

let reduction = Reduction(
    command: command,
    fileName: fileName,
    signature: signature,
    timeout: timeout,
    jobs: jobs,
    reducesArguments: reducesArguments,
    log: { FileHandle.standardError.write(Data(("  " + $0 + "\n").utf8)) }
)
let started = Date()
let outcome: Reduction.Outcome
do { outcome = try reduction.run(source: source) } catch { fail("\(error)") }

let outputURL = URL(fileURLWithPath: output ?? inputURL.deletingPathExtension().path + ".reduced.swift")
try outcome.source.write(to: outputURL, atomically: true, encoding: .utf8)

// One more run of the result, so the record carries its own full output.
let final = try reduction.invoke(source: outcome.source, command: outcome.command)
let logURL = outputURL.appendingPathExtension("log")
try final.output.write(to: logURL, atomically: true, encoding: .utf8)
let lines = outcome.source.split(separator: "\n").count

print("""
    Reduced \(source.utf8.count) → \(outcome.source.utf8.count) bytes (\(lines) lines) in \(outcome.steps) steps, \
    \(outcome.tests) runs, \(outcome.passes) passes (last pass kept nothing: fixed point), \
    \(Int(Date().timeIntervalSince(started))) s.
    Signature still matches on the result: \(signature.matches(final.output) ? "yes" : "NO")
    File:    \(outputURL.path)
    Output:  \(logURL.path)
    Command: \(outcome.command.map { $0.replacingOccurrences(of: "{}", with: fileName) }.joined(separator: " "))
    """)
