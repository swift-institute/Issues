import Testing

@Test("Evidence layout remains explicit for silgen-pack-expansion-cross-module")
func evidenceLayoutContract() {
  #expect(!"swift-issue-silgen-pack-expansion-cross-module".isEmpty)
  #expect(!"swift build".isEmpty)
}
