# `[Compiler][Miscompile] value-generic InlineArray skips cross-module ~Copyable deinitialization`

Canonical work item: [swift-institute/Issues#7](https://github.com/swift-institute/Issues/issues/7)

Canonical evidence path: [swift-issue-inlinearray-deinit-value-generic](https://github.com/swift-institute/Issues/tree/main/swift-issue-inlinearray-deinit-value-generic)

This directory is runnable evidence for the canonical GitHub Issue.

## Summary

A value-generic `InlineArray` container silently skips element deinitialization for cross-module `~Copyable` elements when the container has only value properties. Expected: every initialized element is deinitialized. Source-observed: the container deinitializer runs but element deinitializers do not; adding an `AnyObject?` field changes the result.

Reproduce with the workspace build coordinator against this package’s `test` action. The retained source package’s original command was `swift test`. No fresh result is included in this staging packet.

Source-reported environment: Swift 6.2.3, arm64 macOS 26. Workaround: retain the documented reference-field workaround until a fix is verified.

Upstream: not filed; swiftlang/swift#75172 and #82093 are related but distinct. Privacy screen: `PUBLIC_SAFE`.

## Fixed in Swift 6.4 (re-verified 2026-10-11)

Toolchain: Apple Swift 6.4 (swiftlang-6.4.0.34.1), Xcode toolchain, arm64-apple-macosx27.2.

The container and the `~Copyable` element are built as separate modules (the cross-module shape of the report). In `swift test` at debug and at release with `-enable-testing`, all three tests pass: the value-generic `Container<TrackedElement, 4>` now runs the deinit of every pushed element (`[0, 1, 2]`). The test target stays as a regression fixture; its first test now fails if the leak returns. The `AnyObject?` field workaround can be retired. Closed as fixed.
