# [Compiler][Rejects valid] constrained Property.View extensions report invalid redeclaration cross-module

Issue number: `13`

Canonical Issue: `https://github.com/swift-institute/Issues/issues/13`

Labels: `bug`

## Staging contract

Exact source blobs from the frozen plan are clean-copied under `evidence/`. The original package topology remains authoritative because the defect depends on module, package, platform, or test-discovery boundaries.

No source ancestry is imported. No source repository is transferred or deleted. `github.com/tenthijeboonkkamp/*` is write-excluded.

Sources:

- `coenttb/swift-issue-property-view-tag-constraint-cross-module`

## Exact Issue body draft

## Summary

Extensions of Property.View that differ by tag constraints are treated as invalid redeclarations across module boundaries.

## Classification

Cross-module overload/redeclaration checking defect.

## Expected behavior

Mutually constrained extension members coexist and overload resolution selects the applicable one.

## Observed behavior

The client compilation reports an invalid redeclaration despite distinct constraints.

## Minimal reproduction

The clean-copy dossier is commit-pinned at `https://github.com/swift-institute/Issues/tree/main/swift-issue-property-view-tag-constraint-cross-module`.

```console
swift build
```

## Environment matrix

Swift 6.2.x; cross-module source package and workaround control retained.

## Impact and workaround

Blocks tag-directed views and forces API duplication.

Workaround: Use the source package's differently named workaround surface.

## Upstream

https://github.com/swiftlang/swift/issues/86707

## Evidence and provenance

Original source rows:

- `coenttb/swift-issue-property-view-tag-constraint-cross-module`

Each source is accounted for by `swift-issue-property-view-tag-constraint-cross-module/evidence/source-provenance.json`, including repository identity, visibility, complete refs/tags, root/HEAD/tree OIDs, commit/tree counts, authors/license, releases/issues/PRs, and the SHA-256-verified cold archive locator. No source commit is imported into the `swift-institute/Issues` ancestry.

## Privacy/security screen

PUBLIC_SAFE. The public record contains no credentials, machine paths, private repository details, customer data, or embargoed material.

## Closure gate

Close only after the upstream fix or local resolution is verified on the required matrix, the workaround disposition is decided, and the reproducer is intentionally retained as a regression fixture or removed.

## Execution gate

Replace `13` only after the canonical Issue is created and read back. Replace `https://github.com/swift-institute/Issues/tree/main/swift-issue-property-view-tag-constraint-cross-module` only after this dossier lands by normal push and the commit-pinned path is readable. Before any later source deletion, create and independently read back a cold archive bundle and update `evidence/source-provenance.json`; deletion is not authorized by this dossier.

## Swift 6.4 re-test: a language rule, not a compiler defect (2026-10-11)

**The drift.** The source package no longer builds on Apple Swift 6.4 (swiftlang-6.4.0.34.1). `Workaround.swift` puts `@_lifetime(&self)` on a `mutating func` that returns `Void`, which 6.4 rejects ("invalid lifetime dependence on an Escapable result"). With that attribute removed, the package builds. Restoring the two commented extensions in `Collection.swift` then reproduces "invalid redeclaration of 'all()'", unchanged.

**It needs none of the recorded conditions.** No second module, no `~Copyable`/`~Escapable`, no protocol refinement. This single file is enough:

```swift
struct V<Tag> {}
enum A {}; enum B {}
extension V where Tag == A { var all: Int { 42 } }
extension V where Tag == B { func all() {} }
```

Two functions named `all` in those extensions compile, and so do two properties named `all`. Only a property paired with a zero-argument function conflicts.

**This is the compiler's documented rule.** `swift::conflicting` in `lib/AST/Decl.cpp` says "Functions always conflict with non-functions with the same signature. In practice, this only applies for zero argument functions." It also says variables always conflict with non-variables. The generic signature of the extension is not consulted. Before Swift 5, a variable in an extension of a generic type was exempt; that exemption was removed deliberately.

**Disposition.** Closed as not a defect. Give the property and the method different base names, or use the separate view types in `Workaround.swift`. The upstream report swiftlang/swift#86707 (Coen's) is still open. Per Coen's 2026-10-11 ruling nothing is posted upstream; the finding lives in this record.
