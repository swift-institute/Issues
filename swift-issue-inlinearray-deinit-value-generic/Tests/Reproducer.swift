import Testing
// The reproducer library target is `swift-issue-inlinearray-deinit-value-generic-Repro`;
// SwiftPM exposes it under the C99-mangled module name below. The
// cross-module boundary (TrackedElement defined HERE, Container there) is
// load-bearing for the original defect report.
@testable import swift_issue_inlinearray_deinit_value_generic_Repro

/// Thread-safe tracker for deinit order
final class Tracker: @unchecked Sendable {
    nonisolated(unsafe) var deinitOrder: [Int] = []
    func append(_ id: Int) { deinitOrder.append(id) }
}

/// Element that tracks its deinit - defined in TEST module (cross-module from Container)
struct TrackedElement: ~Copyable {
    let id: Int
    let tracker: Tracker

    init(_ id: Int, tracker: Tracker) {
        self.id = id
        self.tracker = tracker
    }

    deinit {
        tracker.append(id)
    }
}

@Suite("InlineArray Deinit Bug")
struct InlineArrayDeinitTests {

    @Test("Container with value generic capacity - BUG: deinit NOT called")
    func containerWithValueGeneric() {
        let tracker = Tracker()
        do {
            var container = Container<TrackedElement, 4>()
            container.push(TrackedElement(0, tracker: tracker))
            container.push(TrackedElement(1, tracker: tracker))
            container.push(TrackedElement(2, tracker: tracker))
        }
        // BUG: deinitOrder == [] (elements leaked)
        // Expected: deinitOrder == [0, 1, 2]
        #expect(tracker.deinitOrder == [0, 1, 2], "BUG: Elements leaked (deinitOrder was \(tracker.deinitOrder))")
    }

    @Test("ContainerFixed with AnyObject? workaround - deinit IS called")
    func containerWithWorkaround() {
        let tracker = Tracker()
        do {
            var container = ContainerFixed<TrackedElement, 4>()
            container.push(TrackedElement(0, tracker: tracker))
            container.push(TrackedElement(1, tracker: tracker))
            container.push(TrackedElement(2, tracker: tracker))
        }
        #expect(tracker.deinitOrder == [0, 1, 2])
    }

    @Test("ContainerLiteral with literal capacity - deinit IS called (control)")
    func containerWithLiteralCapacity() {
        let tracker = Tracker()
        do {
            var container = ContainerLiteral<TrackedElement>()
            container.push(TrackedElement(0, tracker: tracker))
            container.push(TrackedElement(1, tracker: tracker))
            container.push(TrackedElement(2, tracker: tracker))
        }
        #expect(tracker.deinitOrder == [0, 1, 2])
    }
}
