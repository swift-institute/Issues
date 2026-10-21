import Testing

// The reproducer for this entry is the library target
// `swift-issue-emit-module-noncopyable-sequence-Repro` itself: the original
// defect was an `-emit-module` REJECTS-VALID failure ("type 'Element' does
// not conform to protocol 'Copyable'") on a `~Copyable & Protocol` compound
// constraint with conditional Sequence conformance under the Lifetimes
// feature. Building that target IS the probe — a regression turns the whole
// package build red. Re-verified 2026-07-30 via bare `swiftc -emit-module`:
// clean on 6.3.3-RELEASE and Apple Swift 6.4 (originally reported on 6.2.x).

@Test("Building the -Repro library target is the emit-module probe for emit-module-noncopyable-sequence")
func emitModuleProbeContract() {
    #expect(!"swift-issue-emit-module-noncopyable-sequence-Repro".isEmpty)
}
