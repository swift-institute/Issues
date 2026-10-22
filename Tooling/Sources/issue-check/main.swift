import Foundation
import Toolchain_Report

let usage = """
    USAGE: issue-check (<issue-number> | --body-file <path>) [options]

    Checks a "Toolchain bug" record against what its readiness label demands
    (see UPSTREAM-PROCEDURE.md). Exits 1 when anything is missing.

    OPTIONS:
      --repo <owner/name>   Repository of the issue (default: swift-institute/Issues)
      --label <label>       Check as upstream-ready or upstream-filed
                            (default: the highest readiness label on the issue)
      --run                 Also run the minimal reproduction on the stated
                            toolchain and require the signature
      --enforce             On failure, remove the label and comment why; on
                            success, comment the verified toolchain. Needs
                            an issue number and `gh` with write access.
      --date <YYYY-MM-DD>   Check as of this date (default: today)
      --print-toolchain     Print the "Reproduces on" toolchain and stop
      --print-setup         Print, as $GITHUB_OUTPUT lines, the runner and installs
                            for the "Reproduces on" toolchain (or, with --matrix,
                            for those toolchains; no issue needed) and stop
      --matrix <a,b,...>    Run the reproduction on these toolchains (swiftly names,
                            xcode-<version> for that Xcode, or windows-<swiftly name>
                            for the Windows toolchain on PATH), print the
                            Toolchain matrix table and stop
      --post                With --matrix: also post the table on the issue
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func gh(_ arguments: [String]) throws -> String {
    let result = try Invocation(arguments: ["gh"] + arguments, directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).run()
    guard result.status == 0 else { fail("gh \(arguments.joined(separator: " ")) failed:\n\(result.output)") }
    return result.output
}

var number: String?
var bodyFile: String?
var repository = "swift-institute/Issues"
var labelName: String?
var runs = false
var enforces = false
var printsToolchain = false
var printsSetup = false
var matrixToolchains: [String] = []
var posts = false
var date = Date()

var options = CommandLine.arguments.dropFirst().makeIterator()
while let argument = options.next() {
    func value() -> String {
        guard let next = options.next() else { fail("Missing value for \(argument).") }
        return next
    }
    switch argument {
    case "--body-file": bodyFile = value()
    case "--repo": repository = value()
    case "--label": labelName = value()
    case "--run": runs = true
    case "--enforce": enforces = true
    case "--print-toolchain": printsToolchain = true
    case "--print-setup": printsSetup = true
    case "--matrix": matrixToolchains = value().split(separator: ",").map(String.init)
    case "--post": posts = true
    case "--date":
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: value()) else { fail("--date takes YYYY-MM-DD.") }
        date = parsed
    case "-h", "--help": print(usage); exit(0)
    case _ where number == nil && argument.allSatisfy(\.isNumber): number = argument
    default: fail("Unknown option \(argument).\n\n" + usage)
    }
}

if printsSetup, !matrixToolchains.isEmpty { print(Platform.setup(matrixToolchains)); exit(0) }

let body: String
var labels: [String] = []
if let bodyFile {
    guard let text = try? String(contentsOfFile: bodyFile, encoding: .utf8) else { fail("Cannot read \(bodyFile).") }
    body = text
} else if let number {
    let json = try gh(["issue", "view", number, "--repo", repository, "--json", "body,labels"])
    struct Issue: Decodable { var body: String; var labels: [Label] }
    struct Label: Decodable { var name: String }
    let issue = try JSONDecoder().decode(Issue.self, from: Data(json.utf8))
    body = issue.body
    labels = issue.labels.map(\.name)
} else {
    fail(usage)
}
if enforces, number == nil { fail("--enforce needs an issue number.") }

let readiness: Readiness
if let labelName {
    guard let parsed = Readiness(rawValue: labelName) else { fail("Unknown label \(labelName).") }
    readiness = parsed
} else {
    readiness = Readiness.allCases.last { labels.contains($0.rawValue) } ?? .ready
}

let report = Report(body: body)
if printsToolchain { print(report[.reproducesOn]); exit(0) }
if printsSetup { print(Platform.setup([report[.reproducesOn]])); exit(0) }
if !matrixToolchains.isEmpty {
    guard let source = report.source, let fileName = report.fileName, let commandLine = report.commandLine else {
        fail("--matrix needs one swift block and one command in Minimal reproduction.")
    }
    let command = commandLine.split(separator: " ").map { $0 == Substring(fileName) ? "{}" : String($0) }
    let rows = try Matrix(source: source, fileName: fileName, command: command, toolchains: matrixToolchains, required: report.signature?.required ?? []).run()
    let table = Matrix.table(rows)
    print(table)
    if posts, let number {
        let run = ProcessInfo.processInfo.environment["GITHUB_RUN_URL"].map { " ([run](\($0)))" } ?? ""
        _ = try gh(["issue", "comment", number, "--repo", repository, "--body", "<!-- issue-check matrix -->\n**Toolchain matrix**\(run), from the record's minimal reproduction:\n\n\(table)"])
    }
    exit(0)
}
var findings = readiness.findings(report, on: date)
var verified: String?

if runs, findings.isEmpty {
    if let reproduction = Reproduction(report: report) {
        print("Running on \(reproduction.toolchain): \(reproduction.arguments.joined(separator: " "))")
        let outcome = try reproduction.run()
        if outcome.reproduced {
            verified = "\(reproduction.toolchain) (\(outcome.version))"
        } else {
            findings.append(Readiness.Finding(field: .reproducesOn, message: "the reproduction did not show the signature on \(reproduction.toolchain) (\(outcome.version)). Output:\n\(outcome.output.suffix(4000))"))
        }
    } else {
        findings.append(Readiness.Finding(field: .reproduction, message: "cannot be run: needs one swift block, one command, a signature and a toolchain"))
    }
}

let subject = number.map { "\(repository)#\($0)" } ?? bodyFile ?? "report"
if findings.isEmpty {
    print("PASS \(subject) meets \(readiness.rawValue)" + (verified.map { "; reproduced on \($0)" } ?? " (static checks only)"))
} else {
    print("FAIL \(subject) does not meet \(readiness.rawValue):")
    for finding in findings { print("  - \(finding)") }
}

if enforces, let number {
    let marker = "<!-- issue-check -->"
    let run = ProcessInfo.processInfo.environment["GITHUB_RUN_URL"].map { " ([run](\($0)))" } ?? ""
    let comment: String
    if findings.isEmpty {
        comment = "\(marker)\n**`\(readiness.rawValue)` verified**\(run): every required field is present and the reproduction shows the signature on \(verified ?? "the stated toolchain (static checks only)")."
    } else {
        comment = "\(marker)\n**`\(readiness.rawValue)` removed**\(run). Missing or inconsistent:\n\n" + findings.map { "- \($0)" }.joined(separator: "\n")
        if labels.contains(readiness.rawValue) {
            _ = try gh(["issue", "edit", number, "--repo", repository, "--remove-label", readiness.rawValue])
        }
    }
    // One check comment per issue, updated in place.
    let existing = try gh(["api", "repos/\(repository)/issues/\(number)/comments", "--paginate", "--jq", ".[] | select(.body | startswith(\"\(marker)\")) | .id"])
        .split(separator: "\n").last.map(String.init)
    if let existing {
        _ = try gh(["api", "-X", "PATCH", "repos/\(repository)/issues/comments/\(existing)", "-f", "body=\(comment)"])
    } else {
        _ = try gh(["issue", "comment", number, "--repo", repository, "--body", comment])
    }
}

exit(findings.isEmpty ? 0 : 1)
