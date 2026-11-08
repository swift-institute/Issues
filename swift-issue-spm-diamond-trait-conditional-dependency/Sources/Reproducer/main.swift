// Stages five fixture packages in a temporary directory and resolves the root.
// Exit 1 when SwiftPM fails to resolve the graph (bug fired), 0 when it resolves.
#if canImport(Glibc) || canImport(Musl) || canImport(Darwin) || os(Windows)

    import Foundation

/// `/usr/bin/env` does not exist on Windows. There, a process set up to run a tool
/// through it runs the tool found on Path instead; elsewhere nothing changes.
func resolveEnv(_ process: Process) {
    #if os(Windows)
        guard process.executableURL?.path.hasSuffix("/usr/bin/env") == true,
            let arguments = process.arguments, let name = arguments.first
        else { return }
        let path = ProcessInfo.processInfo.environment["Path"] ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ";") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(name.hasSuffix(".exe") ? name : "\(name).exe")
            if FileManager.default.fileExists(atPath: candidate.path) {
                process.executableURL = candidate
                process.arguments = Array(arguments.dropFirst())
                return
            }
        }
    #endif
}


    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixture")
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("spm-diamond-trait-\(ProcessInfo.processInfo.processIdentifier)")

    // REASON: Process.run() throws an untyped Foundation error in this out-of-process harness.
    // swiftlint:disable:next typed_throws_required
    func run(_ arguments: [String], in directory: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        resolveEnv(process)
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // REASON: Foundation file-system and String I/O APIs throw untyped errors.
    // swiftlint:disable:next typed_throws_required
    func stage(_ name: String, module: String, commit: Bool) throws -> URL {
        let directory = root.appendingPathComponent(name)
        let sources = directory.appendingPathComponent("Sources/\(module)")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "public let value = 1\n".write(
            to: sources.appendingPathComponent("\(module).swift"),
            atomically: true,
            encoding: .utf8
        )
        let manifest = try String(
            contentsOf: fixture.appendingPathComponent("\(name).Package.swift.txt"),
            encoding: .utf8
        )
        .replacingOccurrences(of: "@ROOT@", with: root.path)
        try manifest.write(
            to: directory.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        if commit {
            _ = try run(["git", "init", "-q", "-b", "main"], in: directory)
            _ = try run(["git", "add", "-A"], in: directory)
            _ = try run(
                [
                    "git", "-c", "user.name=repro", "-c", "user.email=repro@example.com", "commit",
                    "-qm", "fixture",
                ],
                in: directory
            )
        }
        return directory
    }

    // REASON: FileManager.removeItem(at:) throws an untyped error during best-effort cleanup.
    // swiftlint:disable:next no_try_optional
    defer { try? FileManager.default.removeItem(at: root) }

    do {
        for (name, module) in [("c", "C"), ("b", "B"), ("n", "N"), ("m", "M")] {
            _ = try stage(name, module: module, commit: true)
        }
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
