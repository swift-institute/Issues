# [Compiler][ICE] _read yielding a ~Escapable lifetime-dependent value fails SIL ownership verification

Issue number: `15`

Canonical Issue: `https://github.com/swift-institute/Issues/issues/15`

Labels: `bug`

## Staging contract

Exact source blobs from the frozen plan are clean-copied under `evidence/`. The original package topology remains authoritative because the defect depends on module, package, platform, or test-discovery boundaries.

No source ancestry is imported. No source repository is transferred or deleted. `github.com/tenthijeboonkkamp/*` is write-excluded.

Sources:

- `coenttb/swift-issue-sil-verifier-read-escapable-lifetime`

## Exact Issue body draft

## Summary

A mutating _read accessor yielding a ~Copyable, ~Escapable wrapper with @_lifetime(borrow) produces an over-consume.

## Classification

SIL ownership verifier crash.

## Expected behavior

The borrow-scoped yielded value passes SIL ownership verification.

## Observed behavior

Assertions toolchains report Found over consume and abort compilation.

## Minimal reproduction

The clean-copy dossier is commit-pinned at `https://github.com/swift-institute/Issues/tree/main/swift-issue-sil-verifier-read-escapable-lifetime`.

```console
swift build
```

## Environment matrix

Swift.org 6.2.3 assertions toolchain; arm64 macOS 26; Xcode-bundled toolchain is the negative control.

## Impact and workaround

Blocks command-line builds of lifetime-dependent _read APIs.

Workaround: Use the Xcode-bundled toolchain or avoid the exact lifetime-dependent yield shape.

## Upstream

https://github.com/swiftlang/swift/issues/87029

## Evidence and provenance

Original source rows:

- `coenttb/swift-issue-sil-verifier-read-escapable-lifetime`

Each source is accounted for by `swift-issue-sil-verifier-read-escapable-lifetime/evidence/source-provenance.json`, including repository identity, visibility, complete refs/tags, root/HEAD/tree OIDs, commit/tree counts, authors/license, releases/issues/PRs, and the SHA-256-verified cold archive locator. No source commit is imported into the `swift-institute/Issues` ancestry.

## Privacy/security screen

PUBLIC_SAFE. The public record contains no credentials, machine paths, private repository details, customer data, or embargoed material.

## Closure gate

Close only after the upstream fix or local resolution is verified on the required matrix, the workaround disposition is decided, and the reproducer is intentionally retained as a regression fixture or removed.

## Execution gate

Replace `15` only after the canonical Issue is created and read back. Replace `https://github.com/swift-institute/Issues/tree/main/swift-issue-sil-verifier-read-escapable-lifetime` only after this dossier lands by normal push and the commit-pinned path is readable. Before any later source deletion, create and independently read back a cold archive bundle and update `evidence/source-provenance.json`; deletion is not authorized by this dossier.
