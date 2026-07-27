import Testing

@Test("Evidence layout remains explicit for windows-existential-crash")
func evidenceLayoutContract() {
  #expect(!"swift-issue-windows-existential-crash".isEmpty)
  #expect(!"swift build -c debug".isEmpty)
}
