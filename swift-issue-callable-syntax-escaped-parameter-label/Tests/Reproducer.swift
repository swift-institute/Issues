import Foundation
import Testing

@Suite
struct CallableSyntaxEscapedParameterLabelReproducer {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func bugFires() -> Bool? {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("callable-syntax-escaped-label-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.removeItem(at: temporary)
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: temporary) }

        func stage(_ name: String) -> URL? {
            let source = root.appendingPathComponent("Sources/Reproducer/\(name).swift.txt")
            let destination = temporary.appendingPathComponent("\(name).swift")
            guard (try? FileManager.default.copyItem(at: source, to: destination)) != nil else { return nil }
            return destination
        }

        guard let fixture = stage("Fixture"),
              let callable = stage("Callable"),
              let explicit = stage("ExplicitInit")
        else { return nil }

        let module = temporary.appendingPathComponent("Fixture.swiftmodule")
        guard run(["-emit-module", "-module-name", "Fixture", "-o", module.path, fixture.path]) == 0,
              run(["-typecheck", "-I", temporary.path, explicit.path]) == 0,
              let callableStatus = run(["-typecheck", "-I", temporary.path, callable.path])
        else { return nil }
        return callableStatus != 0
    }

    private static func run(_ arguments: [String]) -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc"] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test
    func reproducer() {
        guard let fired = Self.bugFires() else { return }
        withKnownIssue(
            "swiftlang/swift#86058 — callable syntax rejects an escaped parameter label across modules",
            { #expect(fired == false) },
            when: { true }
        )
    }
}
