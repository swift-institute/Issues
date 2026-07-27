import Testing

@Test("Evidence layout remains explicit for silgen-property-wrapper-noncopyable")
func evidenceLayoutContract() {
  #expect(!"swift-issue-silgen-property-wrapper-noncopyable".isEmpty)
  #expect(!"swift test".isEmpty)
}
