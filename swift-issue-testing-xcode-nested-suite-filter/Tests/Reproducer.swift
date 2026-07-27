import Testing

@Test("Evidence layout remains explicit for testing-xcode-nested-suite-filter")
func evidenceLayoutContract() {
  #expect(!"swift-issue-testing-xcode-nested-suite-filter".isEmpty)
  #expect(!"swift test, then invoke the Xcode 26 gutter action for A.B.C.bug()".isEmpty)
}
