# SwiftPM: a package reached with and without a trait leaves its trait-gated dependency unresolved

**Classification:** SwiftPM dependency resolution. The graph fails to resolve.

When a graph reaches one package through two paths, one requesting none of its traits
and one requesting trait `T`, SwiftPM leaves the dependencies that `T` gates unresolved,
even though `T` is on in the merged graph:

```
error: exhausted attempts to resolve the dependencies graph, with the following dependencies unresolved:
* 'c' from file://…/c
```

When the gated dependency is also reached another way, the graph resolves but loading
fails later on the pruned product instead, e.g.
`product 'Cursor' required by package 'swift-ascii' target 'ASCII Parser Test Support' not found in package 'swift-cursor'`.

## Reproducer

Five packages, staged by [`Sources/Reproducer/main.swift`](Sources/Reproducer/main.swift)
from [`Sources/Reproducer/Fixture`](Sources/Reproducer/Fixture):

- `c`: a plain library.
- `b`: trait `T` gates its product dependency on `c`.
- `n`: depends on `b` without traits.
- `m`: depends on `b` with `traits: ["T"]`.
- `root`: depends on `n` and `m`.

```sh
swift run swift-issue-spm-diamond-trait-conditional-dependency-Repro
```

Expected: the graph resolves, since `m` turns `T` on and `T` needs `c`.
Observed on Swift 6.4 (arm64 macOS 27), deterministically from a clean `.build`: the error above.
Dropping `n` resolves. Adding `.package(url: …/b, branch: "main", traits: ["T"])` to `root` resolves.

## Workaround

A root that reaches a package through two paths requests the union of its traits itself.
First found through swift-sql, which reaches swift-ascii through swift-rfc-4122 (no traits)
and swift-iso-9075 → swift-iso-8601 (`["Parser"]`).

## Upstream (2026-10-29)

This is swiftlang/swift-package-manager#10485 (open). It is **not** fixed in Swift 6.4.2.
The record of 2026-10-11 expected swiftlang/swift-package-manager#10550 (cherry-picked to
`release/6.4.2` as #10570) to fix it. That was wrong: #10550 changes the PubGrub trait map,
and this graph never reaches it. The fixture still fails, from a clean `.build`, on Xcode 27.2
(Swift 6.4.2, `swiftlang-6.4.2.1.9`), on `6.4.x-snapshot-2026-10-23`, and with SwiftPM built
from `main` at 4a61be762 (2026-10-28).

**Cause.** Branch-based and `path:` dependencies are expanded before PubGrub runs, in
`PubGrubDependencyResolver.processInputs`
(`Sources/PackageGraph/Resolution/PubGrub/PubGrubDependencyResolver.swift`). Each such package's
dependencies are expanded once, with the traits of whichever request for it is processed first.
A later request that names more traits is lost in one of two ways:

1. `PackageContainerConstraint`'s `==` and `hash` ignore traits, so while `b` (defaults) is still
   queued, `b` with `T` is a duplicate in the `OrderedSet` of pending constraints and is dropped.
2. Once `b` has been expanded, a later constraint for it is skipped (`continue` in the revision
   phase, the `overriddenPackages` check in the unversioned phase).

That is why the result depends on order: whichever request is queued first wins. Version-based
dependencies go through PubGrub and are not affected: the same fixture with
`from: "1.0.0"` everywhere resolves.

**Minimal conditions (A/B, Xcode 27.2, 2026-10-29).** `root` → `b` (no traits) and `m` → `b`
(`traits: ["T"]`), `b`'s product dependency on `c` guarded by `T`, `root` and `m` using `B`:
fails with `branch: "main"` and with `path:` dependencies, in either order of `root`'s
dependencies; resolves with `from: "1.0.0"`, without the condition, or when `root` asks for `T`
itself. `c` may be version-based; `b` must be branch-based or `path:`. A version-based `m` that
asks for `T` on a branch-based `b` that `root` overrides also fails, through a different path
(PubGrub drops the overridden constraint's traits); the local fix below does not cover that case.

**Local fix (not filed).** Remember the traits each pre-expanded package was expanded with,
merge the traits of a duplicate queued constraint into the queued one, and expand a package
again with the union when a request brings new traits. With it, every branch and `path:`
variant above resolves.

Today's swift-atoms failure ("exhausted attempts … 'swift-always'") is mostly a different
defect: see [`swift-issue-spm-unused-dependency-trait-request`](../swift-issue-spm-unused-dependency-trait-request).
