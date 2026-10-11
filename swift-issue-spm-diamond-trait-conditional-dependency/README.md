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

## Upstream (2026-10-11)

This is swiftlang/swift-package-manager#10485 (open): the failure depends on order. With `root` listing `m` (requests `T`) before `n` (no traits), the same fixture resolves on Swift 6.4 (swiftlang-6.4.0.34.1). Listing `n` first fails as above. No new upstream report is needed.

A fix has merged: swiftlang/swift-package-manager#10550 on main (2026-09-21), cherry-picked to `release/6.4.2` as #10570. Its description matches this graph: one parent names a trait, the other names none, and the shared package's guarded dependency is dropped. The neighbouring 6.4.2 fixes #10569 (seed root manifest traits) and #10579 (repeat the trait pass until nothing changes) touch the same path. None of them is in Swift 6.4.0. Re-run this reproducer on the first 6.4.2 or later toolchain: when it resolves, the test flips and the `.when(traits:)` conditions listed in Issues#123 can come back.
