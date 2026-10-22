import Foundation
import Testing
@testable import Toolchain_Report

@Suite("Readiness")
struct ReadinessTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func fixture(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Tooling/Tests/Fixtures/\(name)"), encoding: .utf8)
    }

    @Test func `the form's labels are the fields the check reads`() throws {
        let form = try String(contentsOf: Self.root.appendingPathComponent(".github/ISSUE_TEMPLATE/toolchain-bug.yml"), encoding: .utf8)
        let labels = form.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("label: ") }
            .map { String($0.dropFirst("label: ".count)) }
        #expect(labels == Report.Field.allCases.map(\.rawValue))
        for owner in Report.Owner.allCases {
            #expect(form.contains("- " + owner.rawValue), "form lacks owner \(owner.rawValue)")
        }
        for action in Report.Action.allCases {
            #expect(form.contains("- " + action.rawValue), "form lacks action \(action.rawValue)")
        }
    }

    @Test func `an incomplete record is not upstream-ready`() throws {
        let report = Report(body: try Self.fixture("incomplete.md"))
        let findings = Readiness.ready.findings(report, on: Date())
        let fields = Set(findings.compactMap(\.field))
        #expect(fields.isSuperset(of: [.matrix, .duplicates, .reproduction, .reduction, .draft, .readiness]))
    }

    @Test func `a complete record is upstream-ready but not upstream-filed`() throws {
        let report = Report(body: try Self.fixture("complete.md"))
        let date = Readiness.snapshotDate("2026-10-22")!
        #expect(Readiness.ready.findings(report, on: date).map(\.description) == [])
        let filed = Readiness.filed.findings(report, on: date)
        #expect(filed.allSatisfy { $0.field == .filing } && filed.count == 2)
    }

    @Test func `a stale main snapshot or a new issue for a bug fixed on main is rejected`() throws {
        let report = Report(body: try Self.fixture("complete.md"))
        let late = Readiness.snapshotDate("2027-01-01")!
        #expect(Readiness.ready.findings(report, on: late).contains { $0.field == .matrix && $0.message.contains("days old") })

        let fixed = try Self.fixture("complete.md")
            .replacingOccurrences(of: "Cherry-pick request on the fixing pull request", with: "New issue")
        #expect(Readiness.ready.findings(Report(body: fixed), on: Readiness.snapshotDate("2026-10-22")!)
            .contains { $0.field == .action && $0.message.contains("fixed on main") })
    }

    @Test func `our own code and third-party imports never go upstream`() throws {
        let body = try Self.fixture("complete.md")
            .replacingOccurrences(of: "swiftlang/swift (compiler, standard library, runtime, SourceKit)", with: "Our own code (never upstream)")
            .replacingOccurrences(of: "```swift\n", with: "```swift\nimport IssueReporting\n")
        let findings = Readiness.ready.findings(Report(body: body), on: Readiness.snapshotDate("2026-10-22")!)
        #expect(findings.contains { $0.field == .owner })
        #expect(findings.contains { $0.field == .reproduction && $0.message.contains("IssueReporting") })
    }
}

@Suite("Windows")
struct WindowsTests {
    static let date = Readiness.snapshotDate("2026-10-22")!

    @Test func `windows- names a swift.org Windows toolchain, and nothing else does`() {
        for name in ["windows-6.4.1", "windows-6.4", "windows-6.4.x-snapshot-2026-10-17", "windows-main-snapshot-2026-10-17"] {
            #expect(Readiness.isToolchain(name), "\(name)")
            #expect(Platform(toolchain: name) == .windows)
        }
        for name in ["windows-", "windows-latest", "windows-xcode-27.2", "windows-windows-6.4.1", "win-6.4.1"] {
            #expect(!Readiness.isToolchain(name), "\(name)")
        }
        for name in ["6.4.1", "xcode-27.2", "main-snapshot-2026-10-17", ""] {
            #expect(Platform(toolchain: name) == .macOS)
        }
    }

    @Test func `a Windows toolchain installs from swift.org and runs as written`() {
        #expect(Platform.windowsInstall("windows-6.4.1") == "6.4.1")
        #expect(Platform.windowsInstall("windows-6.4") == "6.4.0")
        #expect(Platform.windowsInstall("windows-main-snapshot-2026-10-17")
            == "https://download.swift.org/development/windows10/swift-DEVELOPMENT-SNAPSHOT-2026-10-17-a/swift-DEVELOPMENT-SNAPSHOT-2026-10-17-a-windows10.exe")
        #expect(Platform.windowsInstall("windows-6.4.x-snapshot-2026-10-17")
            == "https://download.swift.org/swift-6.4.x-branch/windows10/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-10-17-a/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-10-17-a-windows10.exe")
        #expect(Platform.windowsInstall("windows-latest") == nil)
        #expect(Platform.windowsInstall("6.4.1") == nil)
        #expect(Matrix.arguments(["xcrun", "swiftc", "-c", "{}"], on: "windows-6.4.1") == ["swiftc", "-c", "{}"])
        #expect(Matrix.arguments(["swiftc", "-c", "{}"], on: "6.4.1") == ["swiftly", "run", "swiftc", "-c", "{}", "+6.4.1"])
    }

    @Test func `only the stated Windows toolchain counts as installed`() {
        #expect(Platform.isWindowsToolchain("windows-6.4.1", version: "Swift version 6.4.1 (swift-6.4.1-RELEASE)"))
        #expect(!Platform.isWindowsToolchain("windows-6.4.1", version: "Swift version 6.4 (swift-6.4-RELEASE)"))
        #expect(Platform.isWindowsToolchain("windows-6.4.0", version: "Swift version 6.4 (swift-6.4-RELEASE)"))
        #expect(Platform.isWindowsToolchain("windows-6.4.x-snapshot-2026-10-17", version: "Swift version 6.4.4-dev (LLVM a, Swift b)"))
        #expect(!Platform.isWindowsToolchain("windows-6.4.x-snapshot-2026-10-17", version: "Swift version 6.5-dev (LLVM a, Swift b)"))
        #expect(Platform.isWindowsToolchain("windows-main-snapshot-2026-10-17", version: "Swift version 6.5-dev (LLVM a, Swift b)"))
        #expect(!Platform.isWindowsToolchain("windows-main-snapshot-2026-10-17", version: "Swift version 6.4.1 (swift-6.4.1-RELEASE)"))
    }

    @Test func `the plan sends each toolchain to its runner`() {
        let lines = Platform.setup(["6.4.1", "windows-6.4.1", "xcode-27.2", "windows-latest"]).components(separatedBy: "\n")
        #expect(lines == [
            "macos=6.4.1,xcode-27.2,windows-latest",
            "swiftly=6.4.1",
            #"windows=[{"swift-version":"6.4.1","toolchain":"windows-6.4.1"}]"#,
        ])
        #expect(Platform.setup([""]) == "macos=\nswiftly=\nwindows=[]")
    }

    @Test func `a complete Windows record is upstream-ready`() throws {
        let report = Report(body: try ReadinessTests.fixture("windows.md"))
        #expect(Readiness.ready.findings(report, on: Self.date).map(\.description) == [])
        #expect(Reproduction(report: report)?.arguments == ["swiftc", "-parse-as-library", "-c", "repro.swift"])
    }

    @Test func `a Windows record is judged by its Windows rows`() throws {
        let body = try ReadinessTests.fixture("windows.md")
        // Without its Windows main row, the macOS main row does not stand in.
        let noMain = body.replacingOccurrences(of: "| windows-main-snapshot-2026-10-17 | Swift version 6.5-dev (LLVM 0000000, Swift 0000000) | reproduces |\n", with: "")
        #expect(Readiness.ready.findings(Report(body: noMain), on: Self.date)
            .contains { $0.field == .matrix && $0.message.contains("windows-main-snapshot") })
        // The macOS main row says "does not reproduce"; that is no fix on main.
        #expect(!Readiness.ready.findings(Report(body: body), on: Self.date).contains { $0.message.contains("fixed on main") })
        // A Windows main row that does not reproduce is.
        let fixed = body.replacingOccurrences(of: "Swift 0000000) | reproduces |\n| 6.4.1", with: "Swift 0000000) | does not reproduce |\n| 6.4.1")
        #expect(Readiness.ready.findings(Report(body: fixed), on: Self.date).contains { $0.message.contains("fixed on main") })
        // Reproducing on a toolchain the matrix shows only for macOS is rejected.
        let macOS = body.replacingOccurrences(of: "### Reproduces on\n\nwindows-6.4.1", with: "### Reproduces on\n\n6.4.1")
        #expect(Readiness.ready.findings(Report(body: macOS), on: Self.date).contains { $0.field == .reproducesOn })
    }

    @Test func `an incomplete Windows record is rejected`() throws {
        let body = try ReadinessTests.fixture("windows.md")
            .replacingOccurrences(of: "requires: child overlaps previous child\n", with: "")
            .replacingOccurrences(of: "### Reproduces on\n\nwindows-6.4.1", with: "### Reproduces on\n\nwindows-latest")
        let findings = Readiness.ready.findings(Report(body: body), on: Self.date)
        #expect(findings.contains { $0.field == .signature })
        #expect(findings.contains { $0.field == .reproducesOn && $0.message.contains("windows-latest") })
    }

    @Test func `a Windows crash is read from its CRLF output, without frame names`() {
        // From swift-atoms/swift-recursion run 39540639205, job 119027714331.
        let output = [
            #"ASTScopeImpl verification error in source file 'D:\a\r\Carrier Laws Tests.swift':"#,
            "child overlaps previous child:",
            "CustomAttributeScope 0x1a21c186c68, [1:154 - 1:155] ",
            "Please submit a bug report (https://swift.org/contributing/#reporting-bugs) and include the crash backtrace.",
            "Stack dump:",
            #"0.\tProgram arguments: C:\\toolchain\\swift-frontend.exe -frontend -c"#,
            "1.\tSwift version 6.4.1 (swift-6.4.1-RELEASE)",
            #"3.\tWhile evaluating request TypeCheckPrimaryFileRequest(source_file "D:\a\r\Carrier Laws Tests.swift")"#,
            "10.\tAbort: function abortWithVerificationError at ASTScopePrinting.cpp:78",
            "Exception Code: 0xC000001D",
            #" #0 0x00007ff6a774af66 (C:\toolchain\swift-frontend.exe+0x30af66)"#,
            #" #1 0x00007fff0c0c19a9 (C:\Windows\System32\ucrtbase.dll+0xc19a9)"#,
        ].joined(separator: "\r\n")
        let signature = Signature(output: output, required: ["child overlaps previous child"])
        #expect(signature == Signature(crashed: true, assertion: nil, phase: "Abort: function abortWithVerificationError", frames: [], required: ["child overlaps previous child"]))
        #expect(signature.matches(output))
        #expect(Signature.assertionText(#"Assertion failed: !type->hasError(), file C:\b\Type.cpp, line 12"#) == "!type->hasError()")
    }
}

@Suite("Invocation")
struct InvocationTests {
    @Test func `finds a command on PATH, and reports one that is not there`() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        #expect(try Invocation(arguments: ["swift", "--version"], directory: directory).run().status == 0)
        let missing = try Invocation(arguments: ["no-such-command-here"], directory: directory).run()
        #expect(missing.status == 127 && missing.output.contains("no-such-command-here"))
    }
}

@Suite("Edit")
struct EditTests {
    @Test func `proposes removals, largest first, and applies them`() {
        let source = """
            struct S {
                var a: Int = 1
                func f() -> Int { return a + 1 }
            }
            let s = S()
            """
        let edits = Edit.candidates(in: source)
        #expect(!edits.isEmpty)
        #expect(edits.map(\.removedBytes) == edits.map(\.removedBytes).sorted(by: >))
        let removal = edits.first { $0.kind == "remove member" && $0.key.contains("func f") }!
        let result = String(decoding: removal.apply(to: Array(source.utf8)), as: UTF8.self)
        #expect(!result.contains("func f"))
        #expect(result.contains("var a"))
    }

    @Test func `strips comments and blank runs`() {
        #expect(Edit.stripped("// a\nlet x = 1 // b\n\n\n/* c */\nlet y = 2\n") == "let x = 1\n\nlet y = 2\n")
    }
}
