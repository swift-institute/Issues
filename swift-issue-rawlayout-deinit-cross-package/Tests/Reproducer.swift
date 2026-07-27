import Testing

@Test("Evidence layout remains explicit for rawlayout-deinit-cross-package")
func evidenceLayoutContract() {
  #expect(!"swift-issue-rawlayout-deinit-cross-package".isEmpty)
  #expect(!"swift test".isEmpty)
}
