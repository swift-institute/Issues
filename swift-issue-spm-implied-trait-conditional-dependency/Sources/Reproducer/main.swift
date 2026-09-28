// Stages four fixture packages in a temporary directory and resolves the root.
// Exit 1 when SwiftPM fails to resolve the graph (bug fired), 0 when it resolves.
#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixture")
let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("spm-implied-trait-\(ProcessInfo.processInfo.processIdentifier)")

func run(_ arguments: [String], in directory: URL) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

func stage(_ name: String, module: String, commit: Bool) throws -> URL {
    let directory = root.appendingPathComponent(name)
    let sources = directory.appendingPathComponent("Sources/\(module)")
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    try "public let value = 1\n".write(to: sources.appendingPathComponent("\(module).swift"), atomically: true, encoding: .utf8)
    let manifest = try String(contentsOf: fixture.appendingPathComponent("\(name).Package.swift.txt"), encoding: .utf8)
        .replacingOccurrences(of: "@ROOT@", with: root.path)
    try manifest.write(to: directory.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    if commit {
        _ = try run(["git", "init", "-q", "-b", "main"], in: directory)
        _ = try run(["git", "add", "-A"], in: directory)
        _ = try run(["git", "-c", "user.name=repro", "-c", "user.email=repro@example.com", "commit", "-qm", "fixture"], in: directory)
    }
    return directory
}

defer { try? FileManager.default.removeItem(at: root) }

do {
    for (name, module) in [("c", "C"), ("b", "B"), ("a", "A")] { _ = try stage(name, module: module, commit: true) }
    let rootPackage = try stage("root", module: "Root", commit: false)
    let result = try run(["swift", "package", "resolve"], in: rootPackage)
    if result.status != 0 && result.output.contains("exhausted attempts to resolve") {
        print("bug fired:\n\(result.output)")
        exit(1)
    }
    print("resolved (bug did not fire)")
    exit(0)
} catch {
    FileHandle.standardError.write(Data("could not stage reproducer: \(error)\n".utf8))
    exit(2)
}

#endif
