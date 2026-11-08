import Foundation

// root depends on b and on m. m asks for b's trait T but uses none of b's products.
// T guards b's dependency on c. Exit 1 (SwiftPM's status) when resolution fails.
let manifests = [
    "c": #"Package(name: "c", products: [.library(name: "C", targets: ["C"])], targets: [.target(name: "C")])"#,
    "b": #"Package(name: "b", products: [.library(name: "B", targets: ["B"])], traits: ["T"], dependencies: [.package(path: "../c")], targets: [.target(name: "B", dependencies: [.product(name: "C", package: "c", condition: .when(traits: ["T"]))])])"#,
    "m": #"Package(name: "m", dependencies: [.package(path: "../b", traits: ["T"])])"#,
    "root": #"Package(name: "root", dependencies: [.package(path: "../b"), .package(path: "../m")])"#,
]
let base = FileManager.default.temporaryDirectory.appendingPathComponent("repro-\(UUID().uuidString)")
for (name, manifest) in manifests {
    let directory = base.appendingPathComponent(name)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try! "// swift-tools-version: 6.1\nimport PackageDescription\nlet package = \(manifest)\n"
        .write(to: directory.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
}

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

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swift", "package", "resolve"]
process.currentDirectoryURL = base.appendingPathComponent("root")
resolveEnv(process)
try! process.run()
process.waitUntilExit()
exit(process.terminationStatus)
