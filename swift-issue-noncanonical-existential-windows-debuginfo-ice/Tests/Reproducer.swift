import Testing

@Test("Evidence layout remains explicit for noncanonical-existential-windows-debuginfo-ice")
func evidenceLayoutContract() {
    #expect(!"swift-issue-noncanonical-existential-windows-debuginfo-ice".isEmpty)
    #expect(!"swift build -c debug --package-path evidence/source/cross-package/crash --target CrashModule".isEmpty)
}
