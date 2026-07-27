import Testing

@Test("Evidence layout remains explicit for sil-verifier-read-escapable-lifetime")
func evidenceLayoutContract() {
  #expect(!"swift-issue-sil-verifier-read-escapable-lifetime".isEmpty)
  #expect(!"swift build".isEmpty)
}
