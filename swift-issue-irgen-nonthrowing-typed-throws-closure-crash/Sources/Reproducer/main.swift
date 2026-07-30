// This harness stages/compiles/cleans up temp reproducer files; failures in
// best-effort cleanup or staging checks are handled via guard/defer control
// flow, not silently swallowed, so the optional-chaining form is the correct idiom here.
// swiftlint:disable no_try_optional
import Foundation
import Dispatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(WinSDK)
import WinSDK
#endif

let sourceNames = [
    "ConstrainedExtension.swift.txt",
    "DirectInitialization.swift.txt",
]

func compilerURL(named name: String) -> URL? {
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

func bugFires(sourceName: String) -> Bool? {
    guard let compiler = compilerURL(named: "swiftc") else {
        return nil
    }

    let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
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
    let standardOutput = Pipe()
    process.standardError = errorOutput
    process.standardOutput = standardOutput

    do {
        try process.run()
    } catch {
        return nil
    }
    let outputGroup = DispatchGroup()
    outputGroup.enter()
    DispatchQueue.global().async {
        _ = standardOutput.fileHandleForReading.readDataToEndOfFile()
        outputGroup.leave()
    }
    outputGroup.enter()
    var errorData = Data()
    DispatchQueue.global().async {
        errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
        outputGroup.leave()
    }
    process.waitUntilExit()
    outputGroup.wait()

    let errorText = String(
        data: errorData,
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

var reproduced = false
var inconclusive = false

for sourceName in sourceNames {
    guard let fired = bugFires(sourceName: sourceName) else {
        inconclusive = true
        FileHandle.standardError.write(
            Data("INCONCLUSIVE: \(sourceName) could not be evaluated.\n".utf8)
        )
        continue
    }

    if fired {
        reproduced = true
        FileHandle.standardError.write(
            Data("BUG FIRED: \(sourceName) aborted in IRGen.\n".utf8)
        )
    } else {
        print("BUG ABSENT: \(sourceName) compiled cleanly.")
    }
}

exit(inconclusive ? 2 : reproduced ? 1 : 0)

// swiftlint:enable no_try_optional
