# [Compiler][ICE] Windows debug-info mangling crashes for a cross-package existential type

Issue number: `21`

Canonical Issue: `https://github.com/swift-institute/Issues/issues/21`

Labels: `bug`

## Staging contract

Exact source blobs from the frozen plan are clean-copied under `evidence/`. The original package topology remains authoritative because the defect depends on module, package, platform, or test-discovery boundaries.

No source ancestry is imported. No source repository is transferred or deleted. `github.com/tenthijeboonkkamp/*` is write-excluded.

Sources:

- `coenttb/swift-issue-windows-existential-crash`
- `coenttb/swift-issue-windows-existential-crash-other-package`

## Exact Issue body draft

## Summary

Debug compilation crashes while mangling any HTML.View when the protocol extension and namespace typealias cross a package boundary.

## Classification

Windows-only IRGen/debug-info assertion failure.

## Expected behavior

The two-package source compiles with DWARF debug information on Windows.

## Observed behavior

Swift 6.0.3 assertions build fails isActuallyCanonicalOrNull while mangling the existential; macOS/Linux and -gnone controls pass.

## Minimal reproduction

The clean-copy dossier is commit-pinned at `https://github.com/swift-institute/Issues/tree/main/swift-issue-windows-existential-crash`.

```console
swift build -c debug
```

## Environment matrix

Swift 6.0.3+; x86_64-unknown-windows-msvc; macOS/Linux negative controls; three primary branches and companion tags 0.1.0/0.2.0 must remain archived.

## Impact and workaround

Blocks Windows debug builds of cross-package existential APIs.

Workaround: Disable debug info on Windows with -Xswiftc -gnone.

## Upstream

https://github.com/swiftlang/swift/issues/86202

## Evidence and provenance

Original source rows:

- `coenttb/swift-issue-windows-existential-crash`
- `coenttb/swift-issue-windows-existential-crash-other-package`

Each source is accounted for by `swift-issue-windows-existential-crash/evidence/source-provenance.json`, including repository identity, visibility, complete refs/tags, root/HEAD/tree OIDs, commit/tree counts, authors/license, releases/issues/PRs, and the SHA-256-verified cold archive locator. No source commit is imported into the `swift-institute/Issues` ancestry.

## Privacy/security screen

PUBLIC_SAFE. The public record contains no credentials, machine paths, private repository details, customer data, or embargoed material.

## Closure gate

Close only after the upstream fix or local resolution is verified on the required matrix, the workaround disposition is decided, and the reproducer is intentionally retained as a regression fixture or removed.

## Execution gate

Replace `21` only after the canonical Issue is created and read back. Replace `https://github.com/swift-institute/Issues/tree/main/swift-issue-windows-existential-crash` only after this dossier lands by normal push and the commit-pinned path is readable. Before any later source deletion, create and independently read back a cold archive bundle and update `evidence/source-provenance.json`; deletion is not authorized by this dossier.
