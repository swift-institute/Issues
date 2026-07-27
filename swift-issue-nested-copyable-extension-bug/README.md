# `[Compiler][Rejects valid] same-file extension of a deeply nested ~Copyable type corrupts name lookup`

Canonical work item: [swift-institute/Issues#11](https://github.com/swift-institute/Issues/issues/11)

Canonical evidence path: [swift-issue-nested-copyable-extension-bug](https://github.com/swift-institute/Issues/tree/main/swift-issue-nested-copyable-extension-bug)

This directory is forensic evidence for the canonical GitHub Issue.

The source report says an empty same-file extension on a deeply nested generic `~Copyable` type incorrectly resolves `Binary.Mutable` as `Binary.Binary.Mutable`; moving the extension to another file works. Correct behavior is identical name lookup in either file placement.

The source repository explicitly says its standalone package does not reproduce the defect, so no runnable harness is claimed. The retained `.txt` resources preserve the attempted reduction and the original `SWIFT_ISSUE.md` without presenting a passing package as proof.

Source-reported environment: Swift 6.2.3, arm64 macOS 26. Workaround: move the extension to another file or inline its methods. Upstream: not filed; #43248 and #63866 are distinct. Privacy screen: `PUBLIC_SAFE`.
