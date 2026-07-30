import Testing

// The reproducer for this entry is the PAIR of library targets
// `…-Core` and `…-Repro` (Ring): the original defect was a cross-module
// REJECTS-VALID failure where the protocol's `associatedtype Element` and
// the conforming type's generic parameter `Element` were confused by the
// constraint checker under a conditional `where Element: Copyable`
// conformance (`Swift.Sequence` is the trigger protocol). The module
// boundary (Ring imports Core) is the reported shape, so it is preserved as
// two root targets; building them IS the probe — a regression turns the
// package build red. Re-verified 2026-07-30 via bare two-invocation
// `swiftc`: clean on 6.3.3-RELEASE and Apple Swift 6.4 (originally
// reported on 6.2.x).

@Test("Building -Core plus -Repro is the cross-module probe for noncopyable-sequence-conformance")
func crossModuleProbeContract() {
    #expect(!"swift-issue-noncopyable-sequence-conformance-Repro".isEmpty)
}
