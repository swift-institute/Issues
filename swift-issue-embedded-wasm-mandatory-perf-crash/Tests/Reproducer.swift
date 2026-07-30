import Testing

#if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
import Foundation
#endif

// Swift 6.3.x wasm32 Embedded — `MandatoryPerformanceOptimizations` SIL crash
// (signal 11, `eliminateDeadAllocations`, `isLegalSILType()` assertion) when
// a consumer module calls the cross-Tagged `Index<T> + Index<T>.Count`
// operator from `swift-index-primitives` under the wasm-embedded SDK.
//
// WHY THIS TEST CANNOT PROBE
// --------------------------
// The verified minimal trigger is two lines of consumer code, but it is
// irreducibly dependent on the production `swift-index-primitives` package
// (single-file and synthetic multi-module standalone reductions all failed to
// reproduce — see the README's reduction log) and on the wasm32 Embedded SDK
// on a 6.3.x toolchain. Neither is available in this repository's
// dependency-free local lane, so there is no in-lane probe whose green or red
// would mean anything. This test compiles on host and checks only fixture
// integrity: that the retained trigger source is present and still carries
// its two live lines. The reproduction itself is the documented container
// invocation in the README, exactly as verified.

@Suite
struct EmbeddedWasmMandatoryPerfCrashFixture {

    @Test
    func `trigger fixture is present and carries the two live lines`() {
        #if canImport(Glibc) || canImport(Musl) || canImport(Darwin)
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Tests/
            .deletingLastPathComponent()        // issue root
            .appendingPathComponent("Sources/Reproducer/Crash.swift.txt")

        guard let text = try? String(contentsOf: fixture, encoding: .utf8) else {
            Issue.record("Crash.swift.txt missing beside the reproducer target")
            return
        }
        #expect(text.contains("public import Index_Primitives"))
        #expect(text.contains("public let x: Index<Int> = .zero + .zero"))
        #endif
    }
}
