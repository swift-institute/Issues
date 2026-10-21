import Testing

// This entry records a PERFORMANCE defect (nested generic type under a
// generic enum with `~Copyable` + value-generic parameter generates ~1.6x
// slower subscript access than an equivalent flat struct — upstream
// swiftlang/swift#86666). Performance cannot be asserted by a unit test in
// this lane; the measurement lives in the
// `swift-issue-nested-generic-subscript-performance-Repro` executable
// (`Sources/Reproducer/main.swift`), which also emits SIL at -O for the
// specialization question raised upstream. The library-shaped sources are
// retained at `Sources/NestedGenericPerformance/` as the reduced shape.
// Building both targets is the compile-level regression canary; run the
// executable by hand for numbers.

@Test("The benchmark executable is the measurement vehicle for nested-generic-subscript-performance")
func benchmarkContract() {
    #expect(!"swift-issue-nested-generic-subscript-performance-Repro".isEmpty)
}
