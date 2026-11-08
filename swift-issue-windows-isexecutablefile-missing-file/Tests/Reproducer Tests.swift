import Testing

#if os(Windows)
    import Foundation
#endif

// On Windows, `FileManager.isExecutableFile(atPath:)` was seen returning true for a
// file that doesn't exist (`C:/Program Files/Git/ucrt64/bin/gh.COM`). The record is
// the issue named in ../ISSUE. The test also asks about a made-up `.COM` file in a
// fresh temporary directory: if that is reported executable too, the defect is in
// Foundation, not in the runner's Git install. Other platforms have nothing to check.

@Suite
struct Reproducer {
    #if os(Windows)
        /// `true` when a path that doesn't exist is reported executable.
        static func bugFires() -> Bool {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("issue-248-\(ProcessInfo.processInfo.processIdentifier)")
            // REASON: best-effort cleanup of a scratch directory.
            // swiftlint:disable:next no_try_optional
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // REASON: best-effort cleanup of a scratch directory.
            // swiftlint:disable:next no_try_optional
            defer { try? FileManager.default.removeItem(at: directory) }
            let paths = [
                "C:/Program Files/Git/ucrt64/bin/gh.COM",
                directory.appendingPathComponent("missing.COM").path,
            ]
            return paths.contains { path in
                !FileManager.default.fileExists(atPath: path) && FileManager.default.isExecutableFile(atPath: path)
            }
        }
    #endif

    @Test
    func reproducer() {
        #if os(Windows)
            let fired = Self.bugFires()
            withKnownIssue(
                "swift-institute/Issues#248",
                { #expect(fired == false) },
                when: { true }
            )
        #endif
    }
}
