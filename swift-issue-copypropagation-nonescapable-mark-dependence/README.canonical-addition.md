# Canonical-Issue addition for CopyPropagation `~Escapable` coroutine-yield crash

Canonical work item: [swift-institute/Issues#6](https://github.com/swift-institute/Issues/issues/6)

Canonical evidence path: [swift-issue-copypropagation-nonescapable-mark-dependence](https://github.com/swift-institute/Issues/tree/main/swift-issue-copypropagation-nonescapable-mark-dependence)

This proposed addition supplements the destination’s existing `README.md`; it must never replace it automatically.

The source-reported defect is an optimized SIL ownership crash: an inlinable `_read` coroutine yielding a `~Copyable, ~Escapable` view with `@_lifetime(borrow)` across control flow produces duplicate lifetime-ending uses. The source reports debug success, release failure in Swift 6.2.4, and a fix in Swift 6.3/Xcode 26.4.

The compiler-crash reproducer is retained as inert `.txt` resources. No new runnable package is staged because the destination already contains the investigation record and current supported toolchains no longer provide fix-detection value.

Upstream: [swiftlang/swift#88022](https://github.com/swiftlang/swift/issues/88022). Privacy screen: `PUBLIC_SAFE`.
