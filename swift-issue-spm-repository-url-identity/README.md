# [SwiftPM][Resolution] repository URL identity and redirects change package identity resolution

Issue number: `22`

Canonical Issue: `https://github.com/swift-institute/Issues/issues/22`

Labels: `bug`

## Staging contract

This is a parent metadata dossier. The three remote repositories are irreducible URL-identity fixtures and remain live while consumed. Their files are not clean-copied into this staging dossier.

No source ancestry is imported. No source repository is transferred or deleted. `github.com/tenthijeboonkkamp/*` is write-excluded.

Sources:

- `coenttb/test-algebra-primitives`
- `coenttb/test-buffer-foundations`
- `coenttb/test-buffer-primitives`

## Exact Issue body draft

## Summary

Three minimal remote repositories exercise URL-basename identity, redirects, and two distinct repository URLs that intentionally declare the same Package.name.

## Classification

SwiftPM repository-URL identity/redirect behavior.

## Expected behavior

SwiftPM resolves dependency identity from the repository location consistently and reports the intentional collision deterministically.

## Observed behavior

The current experiment relies on all three remote identities and tags; exact current behavior is recorded by the experiment assertions.

## Minimal reproduction

The clean-copy dossier is commit-pinned at `https://github.com/swift-institute/Issues/tree/main/swift-issue-spm-repository-url-identity`.

```console
Run swift-institute/Experiments/github-url-spm-resolution with all three dependencies at 0.1.0.
```

## Environment matrix

Three public remote fixtures; each has one main branch and tag 0.1.0 at the same OID. Toolchain matrix is owned by the experiment.

## Impact and workaround

Determines whether canonical URL rewrites and redirects preserve or change SwiftPM dependency identity.

Workaround: Use canonical, uniform repository URLs and avoid two locations for one logical identity.

## Upstream

**Upstream destination**: `swiftlang/swift-package-manager` (adjudicated
2026-07-30 under Issues#69/#79: SwiftPM reproducers stay in this repository;
only the upstream target differs from the compiler entries).

**Upstream search (2026-07-30, swiftlang/swift-package-manager issues)**:
"repository URL identity redirect" and `canonicalPackageLocation` — no issue
reports the URL-identity/redirect resolution behavior these fixtures
exercise; the closest hits are #7001 (closed; canonical-location checkout
paths, a different mechanism) and #8604 (open; same-name dependencies across
owners, an identity-collision UX report, not redirect behavior). **No match
recorded.**

**Eligibility: NOT YET ELIGIBLE for upstream filing.** The observed-behavior
section below is intentionally blank pending the experiment run
(`swift-institute/Experiments/github-url-spm-resolution` with all three
fixtures at 0.1.0); an upstream report without the recorded exact behavior
would not satisfy the general-report bar. The fixture contract stands
unchanged: the three remote repositories remain live and are not
clean-copied here. Filing remains principal-gated once the experiment's
assertions are recorded.

## Evidence and provenance

Original source rows:

- `coenttb/test-algebra-primitives`
- `coenttb/test-buffer-foundations`
- `coenttb/test-buffer-primitives`

Each source is accounted for by `swift-issue-spm-repository-url-identity/evidence/source-provenance.json`, including repository identity, visibility, complete refs/tags, root/HEAD/tree OIDs, commit/tree counts, authors/license, releases/issues/PRs, and the SHA-256-verified cold archive locator. No source commit is imported into the `swift-institute/Issues` ancestry.

## Privacy/security screen

PUBLIC_SAFE. The public record contains no credentials, machine paths, private repository details, customer data, or embargoed material.

## Closure gate

Close only after the upstream fix or local resolution is verified on the required matrix, the workaround disposition is decided, and the reproducer is intentionally retained as a regression fixture or removed.

## Execution gate

Replace `22` only after the canonical Issue is created and read back. Replace `https://github.com/swift-institute/Issues/tree/main/swift-issue-spm-repository-url-identity` only after this dossier lands by normal push and the commit-pinned path is readable. Before any later source deletion, create and independently read back a cold archive bundle and update `evidence/source-provenance.json`; deletion is not authorized by this dossier.
