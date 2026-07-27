# [Compiler][ICE] cross-module property-wrapper access on a ~Copyable type crashes SILGen

Issue number: `17`

Canonical Issue: `https://github.com/swift-institute/Issues/issues/17`

Labels: `bug`

## Staging contract

Exact source blobs from the frozen plan are clean-copied under `evidence/`. The original package topology remains authoritative because the defect depends on module, package, platform, or test-discovery boundaries.

No source ancestry is imported. No source repository is transferred or deleted. `github.com/tenthijeboonkkamp/*` is write-excluded.

Sources:

- `coenttb/swift-issue-silgen-property-wrapper-noncopyable`

## Exact Issue body draft

## Summary

Reading a property wrapped by a generic wrapper on a ~Copyable type from another module crashes SILGen.

## Classification

SILGen crash in property-wrapper member access.

## Expected behavior

The cross-module wrapped property access compiles.

## Observed behavior

The frontend exits on signal 11 in getBaseAccessKind.

## Minimal reproduction

The clean-copy dossier is commit-pinned at `https://github.com/swift-institute/Issues/tree/main/swift-issue-silgen-property-wrapper-noncopyable`.

```console
swift test
```

## Environment matrix

Swift 6.2.3; arm64-apple-macosx26.0; cross-module trigger verified.

## Impact and workaround

Blocks property wrappers on move-only public types across module boundaries.

Workaround: Store the value manually instead of using the property wrapper.

## Upstream

https://github.com/swiftlang/swift/issues/81624

## Evidence and provenance

Original source rows:

- `coenttb/swift-issue-silgen-property-wrapper-noncopyable`

Each source is accounted for by `swift-issue-silgen-property-wrapper-noncopyable/evidence/source-provenance.json`, including repository identity, visibility, complete refs/tags, root/HEAD/tree OIDs, commit/tree counts, authors/license, releases/issues/PRs, and the SHA-256-verified cold archive locator. No source commit is imported into the `swift-institute/Issues` ancestry.

## Privacy/security screen

PUBLIC_SAFE. The public record contains no credentials, machine paths, private repository details, customer data, or embargoed material.

## Closure gate

Close only after the upstream fix or local resolution is verified on the required matrix, the workaround disposition is decided, and the reproducer is intentionally retained as a regression fixture or removed.

## Execution gate

Replace `17` only after the canonical Issue is created and read back. Replace `https://github.com/swift-institute/Issues/tree/main/swift-issue-silgen-property-wrapper-noncopyable` only after this dossier lands by normal push and the commit-pinned path is readable. Before any later source deletion, create and independently read back a cold archive bundle and update `evidence/source-provenance.json`; deletion is not authorized by this dossier.
