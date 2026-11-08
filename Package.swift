// swift-tools-version: 6.3

import Foundation
import PackageDescription

// Every swift-issue-<topic>/ folder becomes a test target, <topic>-Tests, built
// from its Tests/ folder, and, when it has Sources/Reproducer/, an executable
// target, <topic>-Repro. Files other than .swift files in those two folders are
// inputs the harness compiles out of process, so they're excluded from the
// build. A folder that doesn't have the layout fails here or in `issue-check
// --layout`; its record is the issue named in its ISSUE file.

let root = URL(fileURLWithPath: Context.packageDirectory)
let files = FileManager.default

@MainActor
func excluded(_ path: String) -> [String] {
    let entries = (try? files.contentsOfDirectory(atPath: root.appendingPathComponent(path).path)) ?? []
    return entries.filter { !$0.hasSuffix(".swift") }.sorted()
}

let folders = ((try? files.contentsOfDirectory(atPath: root.path)) ?? [])
    .filter { $0.hasPrefix("swift-issue-") }
    .sorted()

let targets: [Target] = folders.flatMap { folder -> [Target] in
    var result: [Target] = [
        .testTarget(
            name: "\(folder)-Tests",
            path: "\(folder)/Tests",
            exclude: excluded("\(folder)/Tests")
        )
    ]
    let reproducer = "\(folder)/Sources/Reproducer"
    if files.fileExists(atPath: root.appendingPathComponent(reproducer).path) {
        result.append(
            .executableTarget(
                name: "\(folder)-Repro",
                path: reproducer,
                exclude: excluded(reproducer)
            )
        )
    }
    return result
}

let package = Package(
    name: "Issues",
    platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26), .visionOS(.v26)],
    targets: targets,
    swiftLanguageModes: [.v6]
)

for target in package.targets {
    target.swiftSettings = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableExperimentalFeature("Lifetimes"),
        .treatAllWarnings(as: .error),
    ]
}
