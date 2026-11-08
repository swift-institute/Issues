import Foundation
import Testing
@testable import Toolchain_Report

@Suite("Layout")
struct LayoutTests {
    static func repository(_ folders: [String: [String: String]]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("layout-\(UUID().uuidString)")
        for (folder, files) in folders {
            for (path, contents) in files {
                let url = root.appendingPathComponent("\(folder)/\(path)")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        return root
    }

    static let good = ["ISSUE": "12\n", "Tests/Reproducer Tests.swift": "withKnownIssue(\"x\") { }"]

    @Test func `a folder with an ISSUE file and a withKnownIssue test passes`() throws {
        let root = try Self.repository(["swift-issue-a": Self.good])
        #expect(Layout.findings(in: root, openIssues: [12]) == [])
        #expect(Layout.issues(in: root) == ["swift-issue-a": 12])
    }

    @Test func `each departure from the layout is a finding`() throws {
        let root = try Self.repository([
            "swift-issue-no-issue": ["Tests/T.swift": "withKnownIssue"],
            "swift-issue-no-tests": ["ISSUE": "12"],
            "swift-issue-placeholder": ["ISSUE": "12", "Tests/T.swift": "#expect(!\"x\".isEmpty)"],
            "swift-issue-notes": Self.good.merging(["README.md": "", "evidence/run.txt": ""]) { $1 },
            "swift-issue-closed": ["ISSUE": "3", "Tests/T.swift": "withKnownIssue"],
        ])
        let findings = Layout.findings(in: root, openIssues: [12])
        #expect(Set(findings.map(\.folder)) == ["swift-issue-no-issue", "swift-issue-no-tests", "swift-issue-placeholder", "swift-issue-notes", "swift-issue-closed"])
        #expect(findings.filter { $0.folder == "swift-issue-notes" }.count == 2)
    }

    @Test func `without the open issues, an ISSUE file is only read`() throws {
        let root = try Self.repository(["swift-issue-closed": ["ISSUE": "3", "Tests/T.swift": "withKnownIssue"]])
        #expect(Layout.findings(in: root) == [])
    }

    @Test func `an input no harness names is a finding`() throws {
        let root = try Self.repository([
            "swift-issue-a": [
                "ISSUE": "12",
                "Tests/T.swift": #"withKnownIssue { }; let s = here.appendingPathComponent("Sources/Reproducer/Crash.swift.txt"); let r = "../repro.swift""#,
                "Sources/Reproducer/Crash.swift.txt": "",
                "Sources/Reproducer/Old.swift.txt": "",
                "repro.swift": "",
                "reproducer.swift": "",
                "Sources/Variant/v.swift": "",
            ]
        ])
        #expect(Layout.unusedInputs(in: root.appendingPathComponent("swift-issue-a")) == ["Sources/Reproducer/Old.swift.txt", "Sources/Variant", "reproducer.swift"])
    }

    @Test func `the manifest's list and the folders must agree`() throws {
        let root = try Self.repository(["swift-issue-a": Self.good, "swift-issue-b": Self.good])
        try "let folders = [\n    \"swift-issue-a\",\n    \"swift-issue-gone\",\n]".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let findings = Layout.findings(in: root, openIssues: [12])
        #expect(findings.map(\.folder) == ["swift-issue-b", "swift-issue-gone"])
    }
}
