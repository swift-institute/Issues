# `[Compiler][Rejects valid] same-file extension of a deeply nested ~Copyable type corrupts name lookup`

Canonical work item: [swift-institute/Issues#11](https://github.com/swift-institute/Issues/issues/11)

Canonical evidence path: [swift-issue-nested-copyable-extension-bug](https://github.com/swift-institute/Issues/tree/main/swift-issue-nested-copyable-extension-bug)

This directory is forensic evidence for the canonical GitHub Issue.

The source report says an empty same-file extension on a deeply nested generic `~Copyable` type incorrectly resolves `Binary.Mutable` as `Binary.Binary.Mutable`; moving the extension to another file works. Correct behavior is identical name lookup in either file placement.

The source repository explicitly says its standalone package does not reproduce the defect, so no runnable harness is claimed. The retained `.txt` resources preserve the attempted reduction and the original `SWIFT_ISSUE.md` without presenting a passing package as proof.

Source-reported environment: Swift 6.2.3, arm64 macOS 26. Workaround: move the extension to another file or inline its methods. Upstream: not filed; #43248 and #63866 are distinct. Privacy screen: `PUBLIC_SAFE`.

## Re-verification (2026-07-30) — reduction still does not reproduce

The retained attempted reduction (`evidence/source/*.txt`, staged as
`NestedCopyableExtensionBug.swift` + `Dimension.swift`, one module) was
re-typechecked with bare `swiftc -typecheck`, each row
`swift --version`-confirmed on the arm64 macOS host:

| Toolchain | Result |
|---|---|
| 6.3.3-RELEASE | exit 0, clean |
| Apple Swift 6.4 (Xcode) | exit 0, clean |
| 6.4.x-snapshot-2026-07-23 (+assertions) | exit 0, clean |
| main-snapshot-2026-07-11 (+assertions) | exit 0, clean |

This is consistent with the source repository's own statement that the
standalone package never reproduced the defect. The blobs are therefore not
promoted into a `Sources/` reproducer: there is no failing case to declare.

**Eligibility statement — not yet eligible for upstream filing.** The only
recorded trigger is the in-package shape in `swift-standards`
(`Sources/Binary/Binary.Cursor.swift` with the commented
`extension Binary.Cursor.Set.Reader {}` restored) on Swift 6.2.3. Missing
evidence, precisely: an in-package reproduction at a pinned `swift-standards`
revision on a currently supported toolchain (6.3.3 or later). Producing it
means restoring that extension at the historical revision and building the
`Binary` target on a current toolchain; a clean result there would close this
record as fixed-or-unreproducible, a failing one would yield the reduction
this directory still lacks.

Duplicate-coverage check against the extension-semantics siblings: distinct.
[`swift-issue-conditional-extension-typealias-name-capture`](../swift-issue-conditional-extension-typealias-name-capture/README.md)
(filed as swiftlang/swift#89684) is a generic-parameter name-capture defect
with a working single-file reducer, and
[`swift-issue-rawlayout-noncopyable-extension-rejection`](../swift-issue-rawlayout-noncopyable-extension-rejection/README.md)
is a compile-time rejection with no name-lookup doubling; neither exhibits the
`Binary.Binary` namespace-doubling signature recorded here.
