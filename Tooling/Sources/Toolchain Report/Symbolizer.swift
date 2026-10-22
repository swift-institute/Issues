import Foundation

/// Names the frames a swift.org toolchain prints without symbols.
///
/// Release and snapshot toolchains from swift.org print frames as
/// `#7 0x0000000108 (/path/swift-frontend+0x10087a160)`, where the offset is
/// the binary's own address. On macOS `atos` turns those into names, so a
/// signature from a swift.org toolchain can be compared with one from Xcode's.
public enum Symbolizer {
    public static func symbolize(_ output: String) -> String {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/atos") else { return output }
        let lines = output.components(separatedBy: "\n")
        var requests: [String: [(line: Int, address: String)]] = [:]
        for (index, line) in lines.enumerated() {
            guard let (binary, address) = unsymbolized(line) else { continue }
            requests[binary, default: []].append((index, address))
        }
        guard !requests.isEmpty else { return output }

        var result = lines
        for (binary, entries) in requests {
            let invocation = Invocation(
                arguments: ["/usr/bin/atos", "-o", binary] + entries.map(\.address),
                directory: URL(fileURLWithPath: "/"),
                timeout: 60
            )
            guard let names = try? invocation.run().output.components(separatedBy: "\n"), names.count >= entries.count else { continue }
            for (entry, name) in zip(entries, names) where !name.hasPrefix("0x") {
                let number = lines[entry.line].trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? ""
                result[entry.line] = "\(number) \(entry.address) \(name)"
            }
        }
        return result.joined(separator: "\n")
    }

    /// `#7 0x0000000108 (/path/swift-frontend+0x10087a160)` → (path, 0x10087a160)
    static func unsymbolized(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#"), trimmed.hasSuffix(")"),
              let open = trimmed.range(of: " (/"), let plus = trimmed.range(of: "+0x", options: .backwards),
              open.upperBound < plus.lowerBound
        else { return nil }
        let fields = trimmed[..<open.lowerBound].split(separator: " ")
        guard fields.count == 2 else { return nil }  // already named frames have more fields
        let binary = "/" + trimmed[open.upperBound..<plus.lowerBound]
        guard binary.hasSuffix("swift-frontend") || binary.hasSuffix("swift-driver") || binary.contains("/usr/bin/") else { return nil }
        let address = "0x" + trimmed[plus.upperBound...].dropLast()
        return (binary, String(address))
    }
}
