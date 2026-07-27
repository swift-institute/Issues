# [Compiler][Rejects valid] @autoclosure prevents Never inference for typed throws

Issue number: `20`

Canonical Issue: `https://github.com/swift-institute/Issues/issues/20`

Labels: `bug`

## Staging contract

Exact source blobs from the frozen plan are clean-copied under `evidence/`. The original package topology remains authoritative because the defect depends on module, package, platform, or test-discovery boundaries.

No source ancestry is imported. No source repository is transferred or deleted. `github.com/tenthijeboonkkamp/*` is write-excluded.

Sources:

- `coenttb/swift-issue-typed-throws-autoclosure-inference`

## Exact Issue body draft

## Summary

The compiler cannot infer E == Never for a nonthrowing expression passed to @autoclosure () throws(E) -> T, while the explicit-closure form infers it.

## Classification

Type-inference rejects-valid defect.

## Expected behavior

The nonthrowing autoclosure infers Never and compiles.

## Observed behavior

The compiler reports generic parameter E could not be inferred.

## Minimal reproduction

The clean-copy dossier is commit-pinned at `https://github.com/swift-institute/Issues/tree/main/swift-issue-typed-throws-autoclosure-inference`.

```console
swift build
```

## Environment matrix

Swift 6.2.3; all platforms per source report.

## Impact and workaround

Makes generic typed-throws autoclosure APIs unusable for ordinary nonthrowing expressions.

Workaround: Use an explicit closure instead of @autoclosure.

## Upstream

Not filed.

## Evidence and provenance

Original source rows:

- `coenttb/swift-issue-typed-throws-autoclosure-inference`

Each source is accounted for by `swift-issue-typed-throws-autoclosure-inference/evidence/source-provenance.json`, including repository identity, visibility, complete refs/tags, root/HEAD/tree OIDs, commit/tree counts, authors/license, releases/issues/PRs, and the SHA-256-verified cold archive locator. No source commit is imported into the `swift-institute/Issues` ancestry.

## Privacy/security screen

PUBLIC_SAFE. The public record contains no credentials, machine paths, private repository details, customer data, or embargoed material.

## Closure gate

Close only after the upstream fix or local resolution is verified on the required matrix, the workaround disposition is decided, and the reproducer is intentionally retained as a regression fixture or removed.

## Execution gate

Replace `20` only after the canonical Issue is created and read back. Replace `https://github.com/swift-institute/Issues/tree/main/swift-issue-typed-throws-autoclosure-inference` only after this dossier lands by normal push and the commit-pinned path is readable. Before any later source deletion, create and independently read back a cold archive bundle and update `evidence/source-provenance.json`; deletion is not authorized by this dossier.
