// Stages a package with a target named `System` and a test target that uses it, and
// builds the tests with and without `import Foundation` in the test file.
// Exit 1 when only the Foundation build fails on the deployment-target mismatch (bug fired), 0 when it builds.
#if canImport(Darwin)

    import Foundation

    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixture")
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(
            "testing-foundation-system-\(ProcessInfo.processInfo.processIdentifier)")

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
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // REASON: Foundation file-system and String I/O APIs throw untyped errors.
    // swiftlint:disable:next typed_throws_required
    func copy(_ name: String, to path: String, replacing replacements: [String: String] = [:])
        throws
    {
        let destination = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try replacements.reduce(
            String(contentsOf: fixture.appendingPathComponent(name), encoding: .utf8)
        ) {
            $0.replacingOccurrences(of: $1.key, with: $1.value)
        }
        .write(to: destination, atomically: true, encoding: .utf8)
    }

    // REASON: This helper forwards the untyped Foundation errors from copy(_:to:replacing:).
    // swiftlint:disable:next typed_throws_required
    func build(import line: String) throws -> (status: Int32, output: String) {
        try copy(
            "ClientTests.swift.txt", to: "Tests/ClientTests/ClientTests.swift",
            replacing: ["@IMPORT@": line])
        return try run(["swift", "build", "--build-tests"], in: root)
    }

    // REASON: FileManager.removeItem(at:) throws an untyped error during best-effort cleanup.
    // swiftlint:disable:next no_try_optional
    defer { try? FileManager.default.removeItem(at: root) }

    do {
        try copy("Package.swift.txt", to: "Package.swift")
        try copy("System.swift.txt", to: "Sources/System/System.swift")
        let without = try build(import: "")
        if without.status != 0 {
            FileHandle.standardError.write(
                Data("unexpected failure without Foundation:\n\(without.output)\n".utf8))
            exit(2)
        }
        let with = try build(import: "import Foundation")
        if with.status != 0
            && with.output.contains("but module 'System' has a minimum deployment target")
        {
            print(
                "bug fired: _Testing_Foundation is built for the toolchain's minimum macOS and loads the package's System module"
            )
            exit(1)
        }
        if with.status != 0 {
            FileHandle.standardError.write(Data("unexpected build failure:\n\(with.output)\n".utf8))
            exit(2)
        }
        print("built (bug did not fire)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("could not stage reproducer: \(error)\n".utf8))
        exit(2)
    }

#endif
