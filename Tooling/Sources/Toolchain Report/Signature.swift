import Foundation

/// What identifies one toolchain failure across reductions, platforms and runs.
///
/// A signature is read from the combined output of a failing command. It
/// keeps only what survives a reduction unchanged: the assertion text without
/// its file and line, the innermost pretty-stack phase without quoted names,
/// and the names (not addresses or parameter lists) of the top stack frames
/// once signal-handling frames are dropped.
public struct Signature: Equatable, Sendable, CustomStringConvertible {
    public var crashed: Bool
    public var assertion: String?
    public var phase: String?
    public var frames: [String]
    /// Extra patterns (plain substrings) the output must contain, such as a
    /// diagnostic for a wrong-diagnostic bug.
    public var required: [String]

    public init(crashed: Bool, assertion: String?, phase: String?, frames: [String], required: [String] = []) {
        self.crashed = crashed
        self.assertion = assertion
        self.phase = phase
        self.frames = frames
        self.required = required
    }

    public var description: String {
        var lines: [String] = []
        lines.append("crashed: \(crashed ? "yes" : "no")")
        if let assertion { lines.append("assertion: \(assertion)") }
        if let phase { lines.append("phase: \(phase)") }
        for (index, frame) in frames.enumerated() { lines.append("frame \(index): \(frame)") }
        for pattern in required { lines.append("requires: \(pattern)") }
        return lines.joined(separator: "\n")
    }
}

extension Signature {
    /// Frames that belong to crash reporting, not to the defect.
    static let handlerPrefixes = [
        "llvm::sys::", "SignalHandler", "_sigtramp", "__pthread_kill", "pthread_kill",
        "abort", "__assert_rtn", "__assert_fail", "__restore_rt", "raise", "gsignal",
        "llvm::llvm_unreachable_internal", "llvm::report_fatal_error", "PrintStackTrace",
        "CrashRecoveryContext", "llvm::CrashRecoveryContext", "_assert", "<deduplicated_symbol>",
    ]

    /// Reads a signature from command output, keeping `frameCount` frames.
    public init(output: String, frameCount: Int = 4, required: [String] = []) {
        let lines = output.components(separatedBy: "\n")
        var assertion: String?
        var phase: String?
        var frames: [String] = []

        for line in lines {
            if assertion == nil, let text = Signature.assertionText(line) { assertion = text }
            if let text = Signature.phaseText(line) { phase = text }
            if let frame = Signature.frameName(line) {
                if Signature.handlerPrefixes.contains(where: { frame.hasPrefix($0) }) { continue }
                if frames.last == frame { continue }
                frames.append(frame)
            }
        }

        let crashed = output.contains("Stack dump:")
            || assertion != nil
            || output.contains("failed due to signal")
            || output.contains("Program arguments:")
        self.init(
            crashed: crashed,
            assertion: assertion,
            phase: phase,
            frames: Array(frames.prefix(frameCount)),
            required: required
        )
    }

    /// Whether `output` shows the same failure as this signature.
    public func matches(_ output: String) -> Bool {
        for pattern in required where !output.contains(pattern) { return false }
        guard crashed else { return !required.isEmpty }
        let other = Signature(output: output, frameCount: frames.count)
        guard other.crashed else { return false }
        if let assertion, other.assertion != assertion { return false }
        if let phase, other.phase != phase { return false }
        return other.frames == frames
    }

    /// Whether `other`, taken on a different toolchain, is the same defect.
    ///
    /// Across toolchains the top frames shift (inlining differs between
    /// Xcode's and swift.org's builds, and an assertions build stops earlier),
    /// so this asks for less than `matches`: the same phase, and at least one
    /// shared frame outside LLVM.
    public func sharesDefect(with other: Signature) -> Bool {
        guard crashed, other.crashed, phase == other.phase else { return false }
        let ours = Set(frames.filter { !$0.hasPrefix("llvm::") })
        return other.frames.contains { ours.contains($0) }
    }

    // Darwin: `Assertion failed: (cond), function f, file x.cpp, line 12.`
    // Linux:  `swift-frontend: x.cpp:12: void f(): Assertion `cond' failed.`
    static func assertionText(_ line: String) -> String? {
        if let range = line.range(of: "Assertion failed: ") {
            var text = String(line[range.upperBound...])
            if let cut = text.range(of: ", function ") { text = String(text[..<cut.lowerBound]) }
            return text.trimmingCharacters(in: .whitespaces)
        }
        if let start = line.range(of: "Assertion `"), let end = line.range(of: "' failed", range: start.upperBound..<line.endIndex) {
            return "(" + String(line[start.upperBound..<end.lowerBound]) + ")"
        }
        return nil
    }

    // `4.	While emitting IR SIL function "@$s...".` → `While emitting IR SIL function`
    static func phaseText(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: "."),
              trimmed[..<dot].allSatisfy(\.isNumber), !trimmed[..<dot].isEmpty
        else { return nil }
        var text = trimmed[trimmed.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        // Entries that describe the invocation, not where it failed.
        let context = ["Program arguments", "Apple Swift version", "Swift version", "Compiling with", "Contents of", "swift-driver version"]
        guard !text.isEmpty, !context.contains(where: { text.hasPrefix($0) }) else { return nil }
        for cut in ["\"", "(", " at ", " for '"] {
            if let range = text.range(of: cut) { text = String(text[..<range.lowerBound]) }
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }

    // Darwin: `8  swift-frontend  0x0000000103 swift::irgen::f(swift::X&) + 716`
    // Linux:  `#8 0x000055d5 swift::irgen::f(swift::X&) (/usr/bin/swift-frontend+0x123)`
    static func frameName(_ line: String) -> String? {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3 else { return nil }
        let first = fields[0].hasPrefix("#") ? fields[0].dropFirst() : fields[0][...]
        guard !first.isEmpty, first.allSatisfy(\.isNumber) else { return nil }
        guard let addressIndex = fields.firstIndex(where: { $0.hasPrefix("0x") }), addressIndex <= 2 else { return nil }
        var symbol = fields[(addressIndex + 1)...].joined(separator: " ")
        if let plus = symbol.range(of: " + ", options: .backwards) { symbol = String(symbol[..<plus.lowerBound]) }
        if symbol.hasSuffix(")"), let open = symbol.range(of: " (/", options: .backwards) {
            symbol = String(symbol[..<open.lowerBound])
        }
        return normalize(symbol)
    }

    /// `(anonymous namespace)::IRGenSILFunction::visitFullApplySite(swift::FullApplySite)`
    /// → `IRGenSILFunction::visitFullApplySite`
    static func normalize(_ symbol: String) -> String? {
        var text = symbol.replacingOccurrences(of: "(anonymous namespace)::", with: "")
        // Drop the return type, if any, then the parameter list.
        var depth = 0
        var cut: String.Index?
        var lastSpace: String.Index?
        for index in text.indices {
            switch text[index] {
            case "<": depth += 1
            case ">": depth -= 1
            case " " where depth == 0: lastSpace = index
            case "(" where depth == 0: cut = index
            default: break
            }
            if cut != nil { break }
        }
        if let cut { text = String(text[..<cut]) }
        if let lastSpace, lastSpace < text.endIndex, !text.contains("operator") {
            text = String(text[text.index(after: lastSpace)...])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.hasPrefix("0x") else { return nil }
        return text
    }
}
