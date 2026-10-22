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
