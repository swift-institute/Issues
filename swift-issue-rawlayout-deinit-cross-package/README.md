# [Compiler][Miscompile] @_rawLayout element deinit is skipped across package boundaries

Issue number: `14`

Canonical Issue: `https://github.com/swift-institute/Issues/issues/14`

Labels: `bug`

## Staging contract

Exact source blobs from the frozen plan are clean-copied under `evidence/`. The original package topology remains authoritative because the defect depends on module, package, platform, or test-discovery boundaries.

No source ancestry is imported. No source repository is transferred or deleted. `github.com/tenthijeboonkkamp/*` is write-excluded.

Sources:

- `coenttb/swift-issue-rawlayout-deinit-cross-package`

## Exact Issue body draft

## Summary

A generic-dependent @_rawLayout container does not invoke element deinit when the element type is defined in another package/module.

## Classification

Cross-package runtime miscompile in @_rawLayout destruction.

## Expected behavior

Destroying the container invokes every initialized element's deinit.

## Observed behavior

The cross-package test misses the deinit while the same-module control succeeds.

## Minimal reproduction

The clean-copy dossier is commit-pinned at `https://github.com/swift-institute/Issues/tree/main/swift-issue-rawlayout-deinit-cross-package`.

```console
swift test
```

## Environment matrix

Swift 6.2.x; source cross-package and single-module controls retained.

## Impact and workaround

Can leak resources held by move-only raw-layout elements.

Workaround: Keep affected element/container definitions together or use the documented layout workaround.

## Upstream

https://github.com/swiftlang/swift/issues/86652

## Evidence and provenance

Original source rows:

- `coenttb/swift-issue-rawlayout-deinit-cross-package`

Each source is accounted for by `swift-issue-rawlayout-deinit-cross-package/evidence/source-provenance.json`, including repository identity, visibility, complete refs/tags, root/HEAD/tree OIDs, commit/tree counts, authors/license, releases/issues/PRs, and the SHA-256-verified cold archive locator. No source commit is imported into the `swift-institute/Issues` ancestry.

## Privacy/security screen

PUBLIC_SAFE. The public record contains no credentials, machine paths, private repository details, customer data, or embargoed material.

## Closure gate

Close only after the upstream fix or local resolution is verified on the required matrix, the workaround disposition is decided, and the reproducer is intentionally retained as a regression fixture or removed.

## Execution gate

Replace `14` only after the canonical Issue is created and read back. Replace `https://github.com/swift-institute/Issues/tree/main/swift-issue-rawlayout-deinit-cross-package` only after this dossier lands by normal push and the commit-pinned path is readable. Before any later source deletion, create and independently read back a cold archive bundle and update `evidence/source-provenance.json`; deletion is not authorized by this dossier.
