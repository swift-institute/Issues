// Stages a package whose extension macro adds a public conformance naming a type
// from a second module, and builds the client with `public import` and with `import`.
// Exit 1 when `public import` is reported unused (bug fired), 0 when it builds.
#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

import Foundation

let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixture")
let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("macro-conformance-import-\(ProcessInfo.processInfo.processIdentifier)")

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

func copy(_ name: String, to path: String, replacing replacements: [String: String] = [:]) throws {
    let destination = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try replacements.reduce(String(contentsOf: fixture.appendingPathComponent(name), encoding: .utf8)) {
        $0.replacingOccurrences(of: $1.key, with: $1.value)
    }
    .write(to: destination, atomically: true, encoding: .utf8)
}

func build(import keyword: String) throws -> (status: Int32, output: String) {
    try copy("Client.swift.txt", to: "Sources/Client/Client.swift", replacing: ["@IMPORT@": keyword])
    return try run(["swift", "build", "--target", "Client"], in: root)
}

defer { try? FileManager.default.removeItem(at: root) }

do {
    try copy("Package.swift.txt", to: "Package.swift")
    try copy("Lib.swift.txt", to: "Sources/Lib/Lib.swift")
    try copy("Marker.swift.txt", to: "Sources/Marker/Marker.swift")
    try copy("MarkedMacro.swift.txt", to: "Sources/MarkerMacros/MarkedMacro.swift")
    let internalImport = try build(import: "import")
    if internalImport.output.contains("cannot be declared public") {
        print("with `import Lib`: the expansion needs Lib publicly imported")
    }
    let publicImport = try build(import: "public import")
    if publicImport.status != 0 && publicImport.output.contains("public import of 'Lib' was not used") {
        print("bug fired: with `public import Lib`: the import is reported unused")
        exit(1)
    }
    if publicImport.status != 0 {
        FileHandle.standardError.write(Data("unexpected build failure:\n\(publicImport.output)\n".utf8))
        exit(2)
    }
    print("built (bug did not fire)")
    exit(0)
} catch {
    FileHandle.standardError.write(Data("could not stage reproducer: \(error)\n".utf8))
    exit(2)
}

#endif
