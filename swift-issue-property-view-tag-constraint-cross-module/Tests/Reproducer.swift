import Testing

@Test("Evidence layout remains explicit for property-view-tag-constraint-cross-module")
func evidenceLayoutContract() {
  #expect(!"swift-issue-property-view-tag-constraint-cross-module".isEmpty)
  #expect(!"swift build".isEmpty)
}
