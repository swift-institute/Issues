# `[Compiler][ICE] typed-throws closure using a nested generic error crashes IRGen`

Canonical work item: [swift-institute/Issues#9](https://github.com/swift-institute/Issues/issues/9)

Canonical evidence path: [swift-issue-irgen-typed-throws-nested-error-generic](https://github.com/swift-institute/Issues/tree/main/swift-issue-irgen-typed-throws-nested-error-generic)

This directory is forensic evidence for the canonical GitHub Issue.

Assigning `{ $0 }` to a stored `(T) throws(Error) -> T` closure in a constrained generic extension is expected to emit normally. The source reports signal 6 at `getMutableErrorResult` / `hasErrorResult` on Swift.org 6.2.3 release and 6.3-dev assertions builds, while the Xcode-bundled 6.2.3 toolchain passes.

The source is retained as `evidence/source/Bug.swift.txt`, not as a live target, because assertions-enabled compilation is the crash trigger. Restore the original package layout only in an isolated toolchain-matrix lane. No fresh result is asserted.

Workaround: hoist the nested error or use the Xcode-bundled toolchain. Upstream: [swiftlang/swift#87030](https://github.com/swiftlang/swift/issues/87030). Privacy screen: `PUBLIC_SAFE`.
