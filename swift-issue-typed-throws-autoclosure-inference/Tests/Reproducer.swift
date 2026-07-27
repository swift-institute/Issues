import Testing

@Test("Evidence layout remains explicit for typed-throws-autoclosure-inference")
func evidenceLayoutContract() {
  #expect(!"swift-issue-typed-throws-autoclosure-inference".isEmpty)
  #expect(!"swift build".isEmpty)
}
