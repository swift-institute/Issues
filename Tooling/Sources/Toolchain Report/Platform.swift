import Foundation

/// The host a named toolchain runs on.
///
/// A record names its toolchains as swiftly does (`6.4.1`,
/// `6.4.x-snapshot-2026-10-20`, `main-snapshot-2026-10-17`) or as
/// `xcode-<version>`; those run on macOS. The same swiftly names prefixed with
/// `windows-` (`windows-6.4.1`, `windows-main-snapshot-2026-10-17`) are the
/// swift.org Windows x86_64 toolchains of that release or snapshot; swiftly
/// does not run on Windows, so CI installs them with setup-swift.
public enum Platform: String, Sendable, CaseIterable {
    case macOS = "macos"
    case windows

    public init(toolchain: String) {
        self = toolchain.hasPrefix(Platform.windows.prefix) ? .windows : .macOS
    }

    /// What a toolchain name of this platform starts with.
    public var prefix: String {
        switch self {
        case .macOS: ""
        case .windows: "windows-"
        }
    }

    /// The swiftly name inside a toolchain name: `windows-6.4.1` → `6.4.1`.
    public static func swiftlyName(_ toolchain: String) -> String {
        String(toolchain.dropFirst(Platform(toolchain: toolchain).prefix.count))
    }

    /// The `swift-version` input setup-swift installs a Windows toolchain
    /// from: a release's exact version (setup-swift resolves and verifies
    /// it), or a snapshot's installer on download.swift.org. Nil for a name
    /// that is not a Windows toolchain.
    public static func windowsInstall(_ toolchain: String) -> String? {
        guard Platform(toolchain: toolchain) == .windows else { return nil }
        let name = swiftlyName(toolchain)
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let result = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name))
            else { return nil }
            return (1..<result.numberOfRanges).map { index in
                Range(result.range(at: index), in: name).map { String(name[$0]) } ?? ""
            }
        }
        if let groups = match(#"^(\d+)\.(\d+)(\.\d+)?$"#) {
            // "6.4" is a version range to setup-swift; "6.4.0" is exactly 6.4.
            return "\(groups[0]).\(groups[1])" + (groups[2].isEmpty ? ".0" : groups[2])
        }
        let tag: String
        let directory: String
        if let groups = match(#"^main-snapshot-(\d{4}-\d{2}-\d{2})$"#) {
            tag = "swift-DEVELOPMENT-SNAPSHOT-\(groups[0])-a"
            directory = "development"
        } else if let groups = match(#"^(\d+\.\d+)(\.x)?-snapshot-(\d{4}-\d{2}-\d{2})$"#) {
            // As swift.org names the branch: `6.4.x` since 6.4, `6.0` before.
            let branch = groups[0] + groups[1]
            tag = "swift-\(branch)-DEVELOPMENT-SNAPSHOT-\(groups[2])-a"
            directory = "swift-\(branch)-branch"
        } else {
            return nil
        }
        return "https://download.swift.org/\(directory)/windows10/\(tag)/\(tag)-windows10.exe"
    }

    /// Whether `version`, the `swiftc --version` line of the toolchain on
    /// `PATH`, is the Windows toolchain `toolchain` names. Windows snapshots
    /// print no date, so a snapshot is checked by its branch only.
    public static func isWindowsToolchain(_ toolchain: String, version: String) -> Bool {
        let name = swiftlyName(toolchain)
        if name.hasPrefix("main-snapshot-") { return version.contains("-dev") }
        if let range = name.range(of: #"^\d+\.\d+(?=(\.x)?-snapshot-)"#, options: .regularExpression) {
            let branch = name[range].replacingOccurrences(of: ".", with: #"\."#)
            return version.range(of: #"Swift version \#(branch)(\.\d+)?-dev"#, options: .regularExpression) != nil
        }
        var release = name
        if release.hasSuffix(".0"), release.filter({ $0 == "." }).count == 2 { release.removeLast(2) }
        return version.contains("(swift-\(release)-RELEASE)")
    }

    /// Which runner runs each of `toolchains`, and what it installs, as
    /// `$GITHUB_OUTPUT` lines for the workflows:
    ///
    ///     macos=<the toolchains for the macOS runner, comma-separated>
    ///     swiftly=<those of them swiftly installs>
    ///     windows=<a JSON array of {"toolchain", "swift-version"}, one Windows job each>
    ///
    /// A `windows-` name with no installer goes to macOS, where the readiness
    /// check reports it and the matrix marks it not run.
    public static func setup(_ toolchains: [String]) -> String {
        var macOS: [String] = []
        var windows: [[String: String]] = []
        for toolchain in toolchains {
            if let install = windowsInstall(toolchain) {
                windows.append(["toolchain": toolchain, "swift-version": install])
            } else {
                macOS.append(toolchain)
            }
        }
        let swiftly = macOS.filter { Platform(toolchain: $0) == .macOS && Readiness.isToolchain($0) && !$0.hasPrefix("xcode-") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = (try? encoder.encode(windows)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        return ["macos=" + macOS.joined(separator: ","), "swiftly=" + swiftly.joined(separator: ","), "windows=" + json].joined(separator: "\n")
    }
}
