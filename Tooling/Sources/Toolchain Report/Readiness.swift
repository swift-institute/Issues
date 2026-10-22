import Foundation

/// The labels a toolchain report moves through, and what each one demands.
///
///   upstream-candidate → upstream-ready → upstream-filed
///
/// `upstream-candidate` demands nothing: it marks a suspected toolchain bug
/// that is still being routed, reduced or pinned. `upstream-ready` demands a
/// complete record whose reproduction still fails on the stated toolchain.
/// `upstream-filed` adds the upstream link and Coen's recorded yes.
///
/// The checks verify that each part is present and consistent; they cannot
/// judge whether a routing argument or a duplicate verdict is right. That is
/// what the independent review in the reduction record is for.
public enum Readiness: String, CaseIterable, Sendable {
    case candidate = "upstream-candidate"
    case ready = "upstream-ready"
    case filed = "upstream-filed"

    public struct Finding: Sendable, CustomStringConvertible {
        public var field: Report.Field?
        public var message: String
        public var description: String { field.map { "\($0.rawValue): \(message)" } ?? message }

        public init(field: Report.Field?, message: String) {
            self.field = field
            self.message = message
        }
    }

    /// Modules a reproduction may import: the toolchain's own.
    static let allowedImports: Set<String> = [
        "Swift", "_Concurrency", "_StringProcessing", "Darwin", "Glibc", "Musl", "WinSDK", "Dispatch",
        "Synchronization", "Observation", "Distributed", "RegexBuilder", "Testing", "XCTest",
    ]

    /// Every finding that keeps `report` from carrying this label, as of `date`.
    public func findings(_ report: Report, on date: Date = Date()) -> [Finding] {
        guard self != .candidate else { return [] }
        var findings: [Finding] = []
        func require(_ condition: Bool, _ field: Report.Field?, _ message: String) {
            if !condition { findings.append(Finding(field: field, message: message)) }
        }

        for field in Report.Field.allCases where ![.regression, .filing].contains(field) {
            require(!report[field].isEmpty, field, "required, but empty")
        }

        // Routing.
        let owner = report.owner
        require(owner != nil, .owner, "not one of the form's owners")
        require(owner != .institute, .owner, "our own code never goes upstream; remove the label and fix it here")
        let action = report.action
        require(action != nil, .action, "not one of the form's actions")
        require(action != Action.none, .action, "'Do not file' cannot be upstream-ready; keep the record without the label")

        // Signature.
        let signature = report.signature
        require(signature != nil, .signature, "no signature: paste the output of `issue-reduce --signature`")
        if let signature, signature.crashed {
            require(!signature.frames.isEmpty || signature.assertion != nil, .signature, "a crash signature needs an assertion or at least one frame")
        }

        // Toolchain matrix: the current release, the release branch's latest
        // snapshot and the latest main snapshot, each with a stated result.
        let rows = report.matrix
        let results = ["reproduces", "does not reproduce", "fixed", "different crash"]
        for row in rows {
            require(results.contains(where: { row.result.hasPrefix($0) }), .matrix, "'\(row.toolchain)': result must be one of \(results.joined(separator: ", "))")
            require(!row.version.isEmpty, .matrix, "'\(row.toolchain)': state the `swift --version` line")
        }
        // The newest of each kind decides; older rows are history.
        let main = Readiness.newest(rows.filter { $0.toolchain.hasPrefix("main-snapshot-") })
        let branch = Readiness.newest(rows.filter { $0.toolchain.range(of: #"^\d+\.\d+(\.x)?-snapshot-"#, options: .regularExpression) != nil })
        let release = rows.first { $0.toolchain.range(of: #"^(xcode-)?\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil }
        require(release != nil, .matrix, "no row for the current release toolchain (e.g. `xcode-27.2` or `6.4.1`)")
        require(branch != nil, .matrix, "no row for the latest release-branch snapshot (e.g. `6.4.x-snapshot-2026-10-20`)")
        require(main != nil, .matrix, "no row for the latest main snapshot (e.g. `main-snapshot-2026-10-17`)")
        if let main {
            if let snapshotDate = Readiness.snapshotDate(main.toolchain) {
                let age = date.timeIntervalSince(snapshotDate) / 86_400
                require(age <= 31, .matrix, "\(main.toolchain) is \(Int(age)) days old; retest on a main snapshot from the last month")
            }
            let fixedOnMain = main.result.hasPrefix("does not reproduce") || main.result.hasPrefix("fixed")
            require(!(fixedOnMain && action == .newIssue), .action, "fixed on main: do not file a new issue (find the fix; a cherry-pick request is the most that applies)")
            require(!(!fixedOnMain && action == .cherryPick), .action, "still fails on main, so there is no fix to cherry-pick")
        }

        // Duplicate search.
        let duplicates = report[.duplicates]
        if let owner, owner.isGitHub {
            require(duplicates.contains("gh search issues") && duplicates.contains(owner.rawValue), .duplicates, "record the `gh search issues ... --repo \(owner.rawValue)` queries that were run")
            require(duplicates.contains("gh search prs"), .duplicates, "record a `gh search prs` query too: a fix may exist without an issue")
        }
        require(duplicates.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil, .duplicates, "state the date of the search")
        require(duplicates.contains("Verdict:"), .duplicates, "end with a `Verdict:` line")
        if action == .comment || action == .cherryPick {
            require(duplicates.range(of: #"(#\d+|github\.com/\S+/(issues|pull)/\d+)"#, options: .regularExpression) != nil, .duplicates, "name the issue or pull request the comment goes on")
        }

        // Minimal reproduction: one file and one command, nothing of ours.
        let source = report.source
        let commandLine = report.commandLine
        if owner != .packageManager {
            require(source != nil, .reproduction, "exactly one ```swift block")
        }
        require(commandLine != nil, .reproduction, "exactly one command, in one ```sh block")
        if owner != .packageManager, let commandLine {
            require(report.fileName != nil, .reproduction, "the command compiles exactly one .swift file")
            for token in ["swift build", "xcodebuild", " -I", " -L", " -F", "Package.swift", ".build/"] where commandLine.contains(token) {
                findings.append(Finding(field: .reproduction, message: "the command uses `\(token.trimmingCharacters(in: .whitespaces))`: a single-file reproduction needs no package or search paths"))
            }
        }
        if let source {
            for line in source.components(separatedBy: "\n") {
                let words = line.split(separator: " ").map(String.init)
                guard let index = words.firstIndex(of: "import"), index + 1 < words.count,
                      words[..<index].allSatisfy({ $0.hasPrefix("@") || ["public", "internal", "package", "private", "fileprivate"].contains($0) })
                else { continue }
                let module = words[index + 1].split(separator: ".").first.map(String.init) ?? ""
                let allowed = Readiness.allowedImports.contains(module)
                    || (module == "Foundation" && (owner == .foundation || owner == .feedbackAssistant))
                    || owner == .feedbackAssistant
                require(allowed, .reproduction, "imports \(module): a reproduction depends on nothing but the toolchain")
            }
        }

        // Where it reproduces, and that the matrix agrees.
        let toolchain = report[.reproducesOn]
        if !toolchain.isEmpty {
            let isXcode = toolchain.hasPrefix("xcode-")
            require(Readiness.isToolchain(toolchain), .reproducesOn, "'\(toolchain)' is neither a swiftly toolchain name nor `xcode-<version>`")
            require(!isXcode || owner == .feedbackAssistant, .reproducesOn, "reproduces only with Xcode's toolchain: swiftlang/swift asks for such bugs to go to Feedback Assistant; retest on an open-source toolchain or reroute")
            let row = rows.first { $0.toolchain == toolchain }
            require(row?.result.hasPrefix("reproduces") == true, .reproducesOn, "the matrix has no 'reproduces' row for \(toolchain)")
        }

        // Reduction record.
        let reduction = report[.reduction]
        require(reduction.contains("issue-reduce") && reduction.contains("fixed point"), .reduction, "record the issue-reduce run and that it reached a fixed point")
        require(reduction.range(of: #"Independent review:.*reproduced"#, options: .regularExpression) != nil, .reduction, "record an `Independent review:` line saying the reviewer reproduced it from the draft alone")

        // Upstream draft: the target's own fields, in its order, and the same
        // reproduction.
        let draft = report[.draft]
        if let owner, action == .newIssue {
            let expected = owner.headings(crash: signature?.crashed ?? false)
            require(report.draftHeadings == expected, .draft, "headings must be exactly \(expected.map { "'\($0)'" }.joined(separator: ", ")) in that order, the fields of \(owner.rawValue)'s template; found \(report.draftHeadings.map { "'\($0)'" }.joined(separator: ", "))")
        }
        if let source {
            let draftSources = Report.codeBlocks(draft).filter { $0.info == "swift" }.map { $0.code + "\n" }
            require(draftSources.contains(source), .draft, "does not contain the minimal reproduction verbatim")
        }
        if let commandLine { require(draft.contains(commandLine), .draft, "does not contain the reproduction command verbatim") }
        if let signature, signature.crashed, action == .newIssue {
            for frame in signature.frames where !draft.contains(frame) {
                findings.append(Finding(field: .draft, message: "the stack dump lacks the signature frame \(frame)"))
            }
        }
        for local in ["/Users/", "/private/tmp/", "/var/folders/", "/home/"] where draft.contains(local) {
            findings.append(Finding(field: .draft, message: "contains a machine-local path (\(local)…); nobody upstream can open it"))
        }

        // Readiness checklist.
        let boxes = report[.readiness].components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [") }
        require(!boxes.isEmpty && boxes.allSatisfy { $0.contains("- [X]") || $0.contains("- [x]") }, .readiness, "every box must be checked")

        if self == .filed {
            let filing = report[.filing]
            let link: String = switch owner {
            case .feedbackAssistant: #"FB\d{6,}"#
            case let owner? where owner.isGitHub: "github\\.com/\(owner.rawValue)/(issues|pull)/\\d+"
            default: "(?!)"
            }
            require(filing.range(of: link, options: .regularExpression) != nil, .filing, "link the upstream report")
            require(filing.range(of: #"Approved by Coen: \d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil, .filing, "record `Approved by Coen: <date>` with his words; every filing needs his explicit yes")
        }
        return findings
    }

    static func newest(_ rows: [Report.Row]) -> Report.Row? {
        rows.max { (snapshotDate($0.toolchain) ?? .distantPast) < (snapshotDate($1.toolchain) ?? .distantPast) }
    }

    static func snapshotDate(_ toolchain: String) -> Date? {
        guard let range = toolchain.range(of: #"\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(toolchain[range]))
    }

    static func isToolchain(_ name: String) -> Bool {
        name.range(of: #"^(main-snapshot-\d{4}-\d{2}-\d{2}|\d+\.\d+(\.x)?-snapshot-\d{4}-\d{2}-\d{2}|\d+\.\d+(\.\d+)?|xcode-\d+(\.\d+)*)$"#, options: .regularExpression) != nil
    }
}

extension Readiness {
    typealias Action = Report.Action
}
