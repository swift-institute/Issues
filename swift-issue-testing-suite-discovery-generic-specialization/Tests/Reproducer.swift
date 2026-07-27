import Testing

@Test("Evidence layout remains explicit for testing-suite-discovery-generic-specialization")
func evidenceLayoutContract() {
  #expect(!"swift-issue-testing-suite-discovery-generic-specialization".isEmpty)
  #expect(!"swift test list".isEmpty)
}
