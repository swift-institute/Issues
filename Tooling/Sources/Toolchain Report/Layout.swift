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

            for input in unusedInputs(in: base) {
                finding("\(input) is never named by Tests/ or Sources/Reproducer/, so nothing runs it. Delete it, or move what it shows onto the issue.")
            }
        }
        findings += manifestFindings(in: root)
        return findings
    }

    /// Everything in a folder that the build doesn't compile — files beside
    /// `ISSUE`, `Tests/` and `Sources/`, entries of `Sources/` other than
    /// `Reproducer/`, and non-Swift entries of `Tests/` and `Sources/Reproducer/` —
    /// that no harness file names in quotes or as a path component.
    static func unusedInputs(in base: URL) -> [String] {
        let files = FileManager.default
        func entries(_ path: String) -> [String] {
            ((try? files.contentsOfDirectory(atPath: base.appendingPathComponent(path).path)) ?? [])
                .filter { $0 != ".DS_Store" }
        }
        var candidates: [String] = []
        candidates += entries("").filter { !["ISSUE", "Tests", "Sources"].contains($0) }
        candidates += entries("Sources").filter { $0 != "Reproducer" }.map { "Sources/\($0)" }
        for harness in ["Tests", "Sources/Reproducer"] {
            candidates += entries(harness).filter { !$0.hasSuffix(".swift") }.map { "\(harness)/\($0)" }
        }
        let harnessText = ["Tests", "Sources/Reproducer"].flatMap { harness in
            entries(harness).filter { $0.hasSuffix(".swift") }.compactMap {
                try? String(contentsOf: base.appendingPathComponent("\(harness)/\($0)"), encoding: .utf8)
            }
        }.joined(separator: "\n")
        // Notes are reported as notes, not again as unused inputs.
        return candidates.sorted().filter { !$0.hasSuffix(".md") && ($0 as NSString).lastPathComponent != "evidence" }.filter { candidate in
            let name = NSRegularExpression.escapedPattern(for: (candidate as NSString).lastPathComponent)
            return harnessText.range(of: "[\"/]\(name)[\"/]", options: .regularExpression) == nil
        }
    }

    /// The root manifest lists every folder by name, because SwiftPM caches a
    /// manifest by its text and would not notice a folder added or removed.
    static func manifestFindings(in root: URL) -> [Finding] {
        guard let manifest = try? String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8) else { return [] }
        let listed = Set(manifest.matches(of: /"(swift-issue-[^"\/]+)"/).map { String($0.output.1) })
        let present = Set(folders(in: root))
        return present.subtracting(listed).sorted().map { Finding(folder: $0, message: "not listed in Package.swift's folders, so it isn't built. Add it to the list.") }
            + listed.subtracting(present).sorted().map { Finding(folder: $0, message: "listed in Package.swift but no such folder exists. Remove it from the list.") }
    }

    public static func folders(in root: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0.hasPrefix("swift-issue-") }
            .sorted()
    }
}
