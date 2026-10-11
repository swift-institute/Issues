import Testing

@Test("Evidence layout remains explicit for testing-suite-discovery-generic-specialization")
func evidenceLayoutContract() {
  #expect(!"swift-issue-testing-suite-discovery-generic-specialization".isEmpty)
  #expect(!"swift test list: compile error on @Suite in a generic extension since Swift 6.4".isEmpty)
}
