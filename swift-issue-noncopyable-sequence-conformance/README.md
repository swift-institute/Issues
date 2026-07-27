# `[Compiler][Rejects valid] associatedtype Element conformance leaks Copyable into a nested ~Copyable type`

Canonical work item: [swift-institute/Issues#12](https://github.com/swift-institute/Issues/issues/12)

Canonical evidence path: [swift-issue-noncopyable-sequence-conformance](https://github.com/swift-institute/Issues/tree/main/swift-issue-noncopyable-sequence-conformance)

This directory is runnable evidence for the canonical GitHub Issue.

A conditional conformance to a protocol declaring `associatedtype Element` causes the constraint checker to confuse that name with the outer `~Copyable` generic parameter. Correct behavior leaves the nested type’s `Heap<Element>` stored property valid; the source reports an erroneous "`Element` does not conform to `Copyable`" diagnostic.

Reproduce with the workspace build coordinator against this package’s `build` action. The retained source’s original command was `swift build`. No fresh result is included here.

Source-reported environment: Apple Swift 6.2.4, arm64 macOS 26. Structural workarounds are to use a top-level type or avoid a protocol whose associated type is named `Element`.

Upstream: [swiftlang/swift#87448](https://github.com/swiftlang/swift/issues/87448). Privacy screen: `PUBLIC_SAFE`.
