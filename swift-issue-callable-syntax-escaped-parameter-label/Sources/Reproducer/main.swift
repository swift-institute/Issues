import Foundation

func run(_ arguments: [String]) -> Int32? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftc"] + arguments
    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    return process.terminationStatus
}

let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("callable-syntax-escaped-label", isDirectory: true)
try? FileManager.default.removeItem(at: temporary)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func stage(_ name: String) throws -> URL {
    guard let source = Bundle.module.url(forResource: name, withExtension: "swift.txt") else {
        throw CocoaError(.fileNoSuchFile)
    }
    let destination = temporary.appendingPathComponent("\(name).swift")
    try FileManager.default.copyItem(at: source, to: destination)
    return destination
}

let fixture = try stage("Fixture")
let callable = try stage("Callable")
let explicit = try stage("ExplicitInit")
let module = temporary.appendingPathComponent("Fixture.swiftmodule")

guard run(["-emit-module", "-module-name", "Fixture", "-o", module.path, fixture.path]) == 0,
      run(["-typecheck", "-I", temporary.path, explicit.path]) == 0,
      let callableStatus = run(["-typecheck", "-I", temporary.path, callable.path])
else {
    exit(2)
}

// The defect is active when callable syntax is rejected while `.init` succeeds.
exit(callableStatus == 0 ? 0 : 1)
