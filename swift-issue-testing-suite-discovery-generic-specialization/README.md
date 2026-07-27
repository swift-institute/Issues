# [Compiler][Runtime] Swift Testing silently omits suites in generic-specialization extensions

Issue number: `18`

Canonical Issue: `https://github.com/swift-institute/Issues/issues/18`

Labels: `bug`

## Staging contract

Exact source blobs from the frozen plan are clean-copied under `evidence/`. The original package topology remains authoritative because the defect depends on module, package, platform, or test-discovery boundaries.

No source ancestry is imported. No source repository is transferred or deleted. `github.com/tenthijeboonkkamp/*` is write-excluded.

Sources:

- `coenttb/swift-issue-testing-suite-discovery-generic-specialization`

## Exact Issue body draft

## Summary

@Suite and @Test compile inside extension Container<Int>, but swift test list omits the suite and the test never runs.

## Classification

Swift Testing discovery/runtime defect.

## Expected behavior

The specialized-extension suite is listed and executed.

## Observed behavior

Only the non-generic control suite appears; no warning is emitted.

## Minimal reproduction

The clean-copy dossier is commit-pinned at `https://github.com/swift-institute/Issues/tree/main/swift-issue-testing-suite-discovery-generic-specialization`.

```console
swift test list
```

## Environment matrix

Apple Swift 6.2.3; arm64-apple-macosx26.0; source discovery control verified.

## Impact and workaround

Tests can silently disappear when organized next to specialized generic types.

Workaround: Use a non-generic struct or enum as the suite container.

## Upstream

https://github.com/swiftlang/swift-testing/issues/1508

## Evidence and provenance

Original source rows:

- `coenttb/swift-issue-testing-suite-discovery-generic-specialization`

Each source is accounted for by `swift-issue-testing-suite-discovery-generic-specialization/evidence/source-provenance.json`, including repository identity, visibility, complete refs/tags, root/HEAD/tree OIDs, commit/tree counts, authors/license, releases/issues/PRs, and the SHA-256-verified cold archive locator. No source commit is imported into the `swift-institute/Issues` ancestry.

## Privacy/security screen

PUBLIC_SAFE. The public record contains no credentials, machine paths, private repository details, customer data, or embargoed material.

## Closure gate

Close only after the upstream fix or local resolution is verified on the required matrix, the workaround disposition is decided, and the reproducer is intentionally retained as a regression fixture or removed.

## Execution gate

Replace `18` only after the canonical Issue is created and read back. Replace `https://github.com/swift-institute/Issues/tree/main/swift-issue-testing-suite-discovery-generic-specialization` only after this dossier lands by normal push and the commit-pinned path is readable. Before any later source deletion, create and independently read back a cold archive bundle and update `evidence/source-provenance.json`; deletion is not authorized by this dossier.
