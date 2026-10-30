// "Forming a CanType out of a non-canonical type!" for `any A.P` with `typealias A = E`
// — standalone exit-code probe.
//
// `../../repro.swift` aborts `swift-frontend`, so it cannot be a compiled target: this
// executable compiles it OUT OF PROCESS ([ISSUE-029]). The assertion exists only in
// assertions builds (snapshots, and the Windows release toolchain); release toolchains
// without assertions accept the file, so the probe reports them as inconclusive.
//
// Exit code:
//   1  — bug fired  (swiftc asserted "Forming a CanType out of a non-canonical type!")
//   0  — bug absent (an assertions toolchain compiled the file) OR inconclusive

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)

    import Foundation

    func swiftc(_ arguments: [String]) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc"] + arguments
        let output = Pipe()
        process.standardError = output
        process.standardOutput = output
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Reproducer/
        .deletingLastPathComponent()  // Sources/
        .deletingLastPathComponent()  // issue root
        .appendingPathComponent("repro.swift")

    guard let version = swiftc(["--version"]) else {
        FileHandle.standardError.write(Data("could not launch swiftc\n".utf8))
        exit(0)
    }
    guard version.output.contains("+assertions") else {
        FileHandle.standardError.write(
            Data("swiftc has no assertions; the defect cannot show here (inconclusive).\n".utf8)
        )
        exit(0)
    }
    guard let result = swiftc(["-g", "-c", source.path, "-o", "/dev/null"]) else {
        FileHandle.standardError.write(Data("could not launch swiftc\n".utf8))
        exit(0)
    }

    if result.output.contains("Forming a CanType out of a non-canonical type!") {
        FileHandle.standardError.write(
            Data("BUG FIRED: non-canonical CanType for `any A.P` through `typealias A = E`.\n".utf8)
        )
        exit(1)
    } else if result.status == 0 {
        FileHandle.standardError.write(Data("The assertions toolchain compiled repro.swift — the bug is FIXED.\n".utf8))
        exit(0)
    } else {
        FileHandle.standardError.write(
            Data("swiftc output did not match either signature:\n\(result.output)\n".utf8)
        )
        exit(0)
    }

#else

    print("subprocess probe unavailable on this platform; skipping")

#endif
