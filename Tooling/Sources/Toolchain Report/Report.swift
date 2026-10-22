import Foundation

/// An issue filed with the "Toolchain bug" form
/// (`.github/ISSUE_TEMPLATE/toolchain-bug.yml`), read back from its body.
///
/// GitHub renders each form field as `### <label>` followed by the value,
/// and an empty optional field as `_No response_`. The labels below must
/// match the form exactly; the form's own test checks that they do.
public struct Report: Sendable {
    public enum Field: String, CaseIterable, Sendable {
        case owner = "Owner"
        case ownerReason = "Why this owner"
        case action = "Upstream action"
        case signature = "Crash signature"
        case matrix = "Toolchain matrix"
        case regression = "Regression range"
        case duplicates = "Duplicate search"
        case reproduction = "Minimal reproduction"
        case reproducesOn = "Reproduces on"
        case reduction = "Reduction record"
        case draft = "Upstream draft"
        case readiness = "Readiness"
        case filing = "Filing record"
    }

    public var values: [Field: String]

    public init(body: String) {
        let labels = Dictionary(uniqueKeysWithValues: Field.allCases.map { ("### " + $0.rawValue, $0) })
        var values: [Field: String] = [:]
        var current: Field?
        var lines: [String] = []
        func flush() {
            guard let current else { return }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            values[current] = text == "_No response_" ? "" : text
        }
        // Only a known label ends a field, so headings inside a field (the
        // upstream draft has its own) stay part of that field.
        for line in body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if let field = labels[line.trimmingCharacters(in: .whitespaces)], values[field] == nil, field != current {
                flush()
                current = field
                lines = []
            } else {
                lines.append(line)
            }
        }
        flush()
        self.values = values
    }

    public subscript(field: Field) -> String { values[field] ?? "" }
}

// MARK: - Owners and their templates

extension Report {
    public enum Owner: String, CaseIterable, Sendable {
        case swift = "swiftlang/swift"
        case packageManager = "swiftlang/swift-package-manager"
        case format = "swiftlang/swift-format"
        case syntax = "swiftlang/swift-syntax"
        case foundation = "swiftlang/swift-foundation"
        case feedbackAssistant = "Feedback Assistant"
        case institute = "Our own code"

        /// The dropdown option starts with the owner's name.
        public init?(option: String) {
            guard let owner = Owner.allCases.first(where: { option.hasPrefix($0.rawValue + " ") || option == $0.rawValue }) else { return nil }
            self = owner
        }

        public var isGitHub: Bool { rawValue.hasPrefix("swiftlang/") }

        /// The headings an upstream draft carries, in the target's order: the
        /// fields of the repository's own issue template (read 2026-10-22).
        public func headings(crash: Bool) -> [String] {
            switch self {
            case .swift where crash:
                // .github/ISSUE_TEMPLATE/crash-report.yml
                ["Description", "Reproduction", "Stack dump", "Expected behavior", "Environment", "Additional information"]
            case .swift:
                // .github/ISSUE_TEMPLATE/bug-report.yml
                ["Description", "Reproduction", "Expected behavior", "Environment", "Additional information"]
            case .packageManager:
                // .github/ISSUE_TEMPLATE/BUG_REPORT.yml
                ["Description", "Expected behavior", "Actual behavior", "Steps to reproduce",
                 "Swift Package Manager version/commit hash", "Swift & OS version"]
            case .syntax:
                // .github/ISSUE_TEMPLATE/BUG_REPORT.yml
                ["Description", "Steps to Reproduce"]
            case .foundation:
                // .github/ISSUE_TEMPLATE/bug_report.md
                ["Describe the bug", "To Reproduce", "Expected behavior", "Configuration", "Regression information", "Additional context"]
            case .format:
                // No issue template; the Institute's fixed order.
                ["Description", "Reproduction", "Expected behavior", "Actual behavior", "Environment"]
            case .feedbackAssistant:
                // Feedback Assistant's own fields for a developer-tools report.
                ["Title", "Description", "Steps to reproduce", "Expected results", "Actual results", "Configuration"]
            case .institute:
                []
            }
        }
    }

    public enum Action: String, CaseIterable, Sendable {
        case newIssue = "New issue"
        case comment = "Comment on an existing open issue"
        case cherryPick = "Cherry-pick request on the fixing pull request"
        case none = "Do not file"

        public init?(option: String) {
            guard let action = Action.allCases.first(where: { option.hasPrefix($0.rawValue) }) else { return nil }
            self = action
        }
    }

    public var owner: Owner? { Owner(option: self[.owner]) }
    public var action: Action? { Action(option: self[.action]) }
}

// MARK: - Pieces

extension Report {
    /// Fenced code blocks of `text` as (info string, contents).
    public static func codeBlocks(_ text: String) -> [(info: String, code: String)] {
        var blocks: [(String, String)] = []
        var info: String?
        var fence = ""
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = info {
                if trimmed == fence { blocks.append((open, lines.joined(separator: "\n"))); info = nil; lines = [] } else { lines.append(line) }
            } else if trimmed.hasPrefix("```") {
                fence = String(trimmed.prefix(while: { $0 == "`" }))
                info = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return blocks
    }

    /// The single Swift file of the reproduction.
    public var source: String? {
        let blocks = Report.codeBlocks(self[.reproduction]).filter { $0.info == "swift" }
        return blocks.count == 1 ? blocks[0].code + "\n" : nil
    }

    /// The single command of the reproduction, from its shell block.
    public var commandLine: String? {
        let blocks = Report.codeBlocks(self[.reproduction]).filter { ["sh", "console", "bash", "shell", "zsh"].contains($0.info) }
        guard blocks.count == 1 else { return nil }
        let lines = blocks[0].code.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("$ ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return lines.count == 1 ? lines[0] : nil
    }

    /// The file name the command compiles: the one `.swift` argument.
    public var fileName: String? {
        guard let commandLine else { return nil }
        let files = commandLine.split(separator: " ").map(String.init).filter { $0.hasSuffix(".swift") }
        return files.count == 1 ? files[0] : nil
    }

    /// The signature, as `issue-reduce --signature` printed it.
    public var signature: Signature? {
        var crashed = false
        var assertion: String?
        var phase: String?
        var frames: [String] = []
        var required: [String] = []
        let text = Report.codeBlocks(self[.signature]).first?.code ?? self[.signature]
        for line in text.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "crashed": crashed = parts[1] == "yes"
            case "assertion": assertion = parts[1]
            case "phase": phase = parts[1]
            case "requires": required.append(parts[1])
            case let key where key.hasPrefix("frame "): frames.append(parts[1])
            default: continue
            }
        }
        guard crashed || !required.isEmpty else { return nil }
        return Signature(crashed: crashed, assertion: assertion, phase: phase, frames: frames, required: required)
    }

    public struct Row: Sendable, Equatable {
        public var toolchain: String
        public var version: String
        public var result: String
    }

    /// Rows of the toolchain matrix table: toolchain | version | result.
    public var matrix: [Row] {
        self[.matrix].components(separatedBy: "\n").compactMap { line in
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 5, !cells[1].isEmpty, !cells[1].hasPrefix("-"), cells[1].lowercased() != "toolchain" else { return nil }
            return Row(toolchain: cells[1], version: cells[2], result: cells[3].lowercased())
        }
    }

    /// The headings of the upstream draft, in order.
    public var draftHeadings: [String] {
        var inFence = false
        return self[.draft].components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); return nil }
            guard !inFence, trimmed.hasPrefix("#") else { return nil }
            return trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        }
    }
}
