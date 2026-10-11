# [Compiler][ICE] cross-module parameter-pack expansion call crashes SILGen

Issue number: `16`

Canonical Issue: `https://github.com/swift-institute/Issues/issues/16`

Labels: `bug`

## Staging contract

Exact source blobs from the frozen plan are clean-copied under `evidence/`. The original package topology remains authoritative because the defect depends on module, package, platform, or test-discovery boundaries.

No source ancestry is imported. No source repository is transferred or deleted. `github.com/tenthijeboonkkamp/*` is write-excluded.

Sources:

- `coenttb/swift-issue-silgen-pack-expansion-cross-module`

## Exact Issue body draft

## Summary

Calling an @inlinable function in another module with a (repeat each T) argument crashes SIL generation; the same expression inline or in one module compiles.

## Classification

SILGen crash in pack-expansion argument emission.

## Expected behavior

The cross-module call emits SIL like the same-module control.

## Observed behavior

The frontend exits on signal 11 in emitPackExpansionIntoPack.

## Minimal reproduction

The clean-copy dossier is commit-pinned at `https://github.com/swift-institute/Issues/tree/main/swift-issue-silgen-pack-expansion-cross-module`.

```console
swift build
```

## Environment matrix

Swift 6.2.3; arm64-apple-macosx26.0; source controls verified.

## Impact and workaround

Blocks reusable cross-module tuple/parameter-pack utilities.

Workaround: Inline the pack-expansion expression at the call site.

## Upstream

Not filed; #67645, #76391, and #84568 are related.

## Evidence and provenance

Original source rows:

- `coenttb/swift-issue-silgen-pack-expansion-cross-module`

Each source is accounted for by `swift-issue-silgen-pack-expansion-cross-module/evidence/source-provenance.json`, including repository identity, visibility, complete refs/tags, root/HEAD/tree OIDs, commit/tree counts, authors/license, releases/issues/PRs, and the SHA-256-verified cold archive locator. No source commit is imported into the `swift-institute/Issues` ancestry.

## Privacy/security screen

PUBLIC_SAFE. The public record contains no credentials, machine paths, private repository details, customer data, or embargoed material.

## Closure gate

Close only after the upstream fix or local resolution is verified on the required matrix, the workaround disposition is decided, and the reproducer is intentionally retained as a regression fixture or removed.

## Execution gate

Replace `16` only after the canonical Issue is created and read back. Replace `https://github.com/swift-institute/Issues/tree/main/swift-issue-silgen-pack-expansion-cross-module` only after this dossier lands by normal push and the commit-pinned path is readable. Before any later source deletion, create and independently read back a cold archive bundle and update `evidence/source-provenance.json`; deletion is not authorized by this dossier.

## Upstream and Swift 6.4 (2026-10-11)

This was already filed as swiftlang/swift#86348 (2026-01-07, open). On Apple Swift 6.4 (swiftlang-6.4.0.34.1) it still crashes SILGen (signal 11, `emitDynamicPackLoop`, then `OpenPackElementInst::create`).

The crash does not need two modules. The 6.4 reduction below crashes in a single file with `swiftc -swift-version 6 -parse-as-library -c`:

```swift
func f<each T>(_ t: (repeat each T)) {}
func g<each T>(_ t: (repeat each T)) { f(t) }
```

Re-expanding the argument, `f((repeat each t))`, compiles. That is the workaround, and it also explains why the "inline" form in the original report worked: it re-expanded the tuple. The `@inlinable`, library-evolution and second-module ingredients are not needed. This changes the record's earlier statement that the same-module control compiles. The original package shape is equivalent to the single-file form, which crashes too.
