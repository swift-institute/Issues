import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
    import Foundation

    @Suite
    struct MacroConformancePublicImportAccountingReproducer {
        /// Runs the standalone reproducer; `true` when `public import` is reported unused.
        static func bugFires() throws -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "swift",
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Sources/Reproducer/main.swift").path,
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 1
        }

        @Test
        func `A public conformance added by a macro counts toward public import use`() throws {
            let fired = try Self.bugFires()
            withKnownIssue(
                "Swift: macro-generated public declarations do not count toward public import accounting",
                { #expect(!fired) },
                when: { Self.beforeFix }
            )
        }

        /// Fixed on main before 6.5 (clean on main-snapshot-2026-10-27; fix PR not identified); every 6.4 toolchain still has it. From 6.5 on,
        /// the bug firing again is a regression and fails the test.
        static var beforeFix: Bool {
            #if compiler(>=6.5)
                return false
            #else
                return true
            #endif
        }
    }
#endif
