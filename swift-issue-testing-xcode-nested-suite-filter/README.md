# [Compiler][Runtime] Xcode gutter action reports zero tests for deeply nested Swift Testing suites

Issue number: `19`

Canonical Issue: `https://github.com/swift-institute/Issues/issues/19`

Labels: `bug`

## Staging contract

Exact source blobs from the frozen plan are clean-copied under `evidence/`. The original package topology remains authoritative because the defect depends on module, package, platform, or test-discovery boundaries.

No source ancestry is imported. No source repository is transferred or deleted. `github.com/tenthijeboonkkamp/*` is write-excluded.

Sources:

- `coenttb/swift-issue-testing-xcode-nested-suite-filter`

## Exact Issue body draft

## Summary

The gutter diamond reports zero tests for a test nested at depth four, although swift test and Cmd+U discover and execute it.

## Classification

Xcode/Swift Testing filtered-execution defect.

## Expected behavior

The Xcode gutter action selects and runs the nested test.

## Observed behavior

Depth four yields zero tests; depth three succeeds.

## Minimal reproduction

The clean-copy dossier is commit-pinned at `https://github.com/swift-institute/Issues/tree/main/swift-issue-testing-xcode-nested-suite-filter`.

```console
swift test, then invoke the Xcode 26 gutter action for A.B.C.bug()
```

## Environment matrix

Swift 6.2.4; Xcode 26.0 beta; arm64 macOS 26.

## Impact and workaround

Breaks focused test execution for suites mirroring deeply nested APIs.

Workaround: Flatten the suite hierarchy to depth three or use Cmd+U/swift test.

## Upstream

Apple FB22115546; https://github.com/swiftlang/swift-testing/issues/1604

## Evidence and provenance

Original source rows:

- `coenttb/swift-issue-testing-xcode-nested-suite-filter`

Each source is accounted for by `swift-issue-testing-xcode-nested-suite-filter/evidence/source-provenance.json`, including repository identity, visibility, complete refs/tags, root/HEAD/tree OIDs, commit/tree counts, authors/license, releases/issues/PRs, and the SHA-256-verified cold archive locator. No source commit is imported into the `swift-institute/Issues` ancestry.

## Privacy/security screen

PUBLIC_SAFE. The public record contains no credentials, machine paths, private repository details, customer data, or embargoed material.

## Closure gate

Close only after the upstream fix or local resolution is verified on the required matrix, the workaround disposition is decided, and the reproducer is intentionally retained as a regression fixture or removed.

## Execution gate

Replace `19` only after the canonical Issue is created and read back. Replace `https://github.com/swift-institute/Issues/tree/main/swift-issue-testing-xcode-nested-suite-filter` only after this dossier lands by normal push and the commit-pinned path is readable. Before any later source deletion, create and independently read back a cold archive bundle and update `evidence/source-provenance.json`; deletion is not authorized by this dossier.
