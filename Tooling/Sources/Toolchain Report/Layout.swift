import Foundation

/// The shape every `swift-issue-<topic>/` folder must have.
///
/// A folder holds code only. Its record is the GitHub issue its `ISSUE` file
/// names, and its test wraps the trigger in `withKnownIssue`, so the test turns
/// red when the bug stops firing. The root manifest builds `Tests/` and, when
/// present, `Sources/Reproducer/`.
public enum Layout {
    public struct Finding: Sendable, Equatable, CustomStringConvertible {
        public var folder: String
        public var message: String
        public var description: String { "\(folder): \(message)" }
    }

    /// The folders under `root` and the issue each one names.
    public static func issues(in root: URL) -> [String: Int] {
        var result: [String: Int] = [:]
        for folder in folders(in: root) {
            let text = try? String(contentsOf: root.appendingPathComponent("\(folder)/ISSUE"), encoding: .utf8)
            if let number = text.flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
                result[folder] = number
            }
        }
        return result
    }

    /// Every way the folders under `root` depart from the layout. `openIssues`,
    /// when given, is the set of open issue numbers; an ISSUE file must name one.
    public static func findings(in root: URL, openIssues: Set<Int>? = nil) -> [Finding] {
        let files = FileManager.default
        var findings: [Finding] = []
        let issues = issues(in: root)
        for folder in folders(in: root) {
            func finding(_ message: String) { findings.append(Finding(folder: folder, message: message)) }
            let base = root.appendingPathComponent(folder)

            if let number = issues[folder] {
                if let openIssues, !openIssues.contains(number) {
                    finding("ISSUE names #\(number), which is not an open issue. Close the folder with its issue: delete it, or reopen the issue if the bug still fires.")
                }
            } else {
                finding("no ISSUE file holding the number of the issue that records this bug. Open one with the \"Toolchain bug\" form if none exists.")
            }

            let tests = base.appendingPathComponent("Tests")
            let swiftFiles = ((try? files.contentsOfDirectory(atPath: tests.path)) ?? []).filter { $0.hasSuffix(".swift") }
            if swiftFiles.isEmpty {
                finding("no Tests/*.swift. The test runs the trigger, in process or out of process, inside withKnownIssue.")
            } else if !swiftFiles.contains(where: { file in
                (try? String(contentsOf: tests.appendingPathComponent(file), encoding: .utf8))?.contains("withKnownIssue") == true
            }) {
                finding("Tests/ never calls withKnownIssue, so CI can't tell whether the bug still fires. Wrap the trigger in withKnownIssue (never .disabled(if:)).")
            }

            if let enumerator = files.enumerator(atPath: base.path) {
                for case let path as String in enumerator {
                    let name = (path as NSString).lastPathComponent
                    if name == "evidence" || name.hasSuffix(".md") {
                        finding("\(path) is notes. Notes belong on the issue: move them there and delete the file.")
                        if name == "evidence" { enumerator.skipDescendants() }
                    }
                }
            }
        }
        return findings
    }

    public static func folders(in root: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0.hasPrefix("swift-issue-") }
            .sorted()
    }
}
