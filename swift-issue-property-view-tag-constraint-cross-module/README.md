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
