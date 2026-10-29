# SwiftPM: a trait requested on an unused dependency leaves the dependency it guards unresolved

**Classification:** SwiftPM dependency resolution. The graph fails to resolve. Record: swift-institute/Issues#211.

A package declares a dependency with a trait, `.package(path: "../b", traits: ["T"])`, but none
of its targets uses a product of that dependency, or only targets that are guarded by traits that
are off use it. SwiftPM's trait computation still turns `T` on, so the dependency that `T` guards
is required. Resolution does not follow the unused edge, so it never fetches that dependency:

```
error: exhausted attempts to resolve the dependencies graph, with the following dependencies unresolved:
* 'c' at …/c
```

## Reproducer

[`repro.swift`](repro.swift) writes four packages to a temporary directory and runs
`swift package resolve` in the root:

- `c`: a plain library.
- `b`: trait `T` guards its product dependency on `c`.
- `m`: depends on `b` with `traits: ["T"]` and has no targets.
- `root`: depends on `b` and `m`.

```sh
swift repro.swift
```

It exits 1 with the error above while the bug is present. The test target
`swift-issue-spm-unused-dependency-trait-request-Tests` runs it (`withKnownIssue`).

## Minimal conditions (A/B, Swift 6.4.2, Xcode 27.2, arm64 macOS 27.2, 2026-10-29)

| Change from the reproducer | Result |
|---|---|
| none | fails |
| drop `condition: .when(traits: ["T"])` in `b` | resolves |
| drop `traits: ["T"]` in `m` | resolves |
| `root` does not depend on `b` | resolves |
| `root` itself asks for `b` with `traits: ["T"]` | resolves |
| `root` lists `m` before `b` | fails: no order dependence |
| `m` has a target that uses `B` only under its own trait `P`, which is off | fails |
| every dependency by `file://` URL at `from: "1.0.0"` (version-based) instead of `path:` | fails |

## Cause

Two parts of SwiftPM disagree about which dependency edges carry traits.

- `Workspace.updateEnabledTraits(for:)` (`Sources/Workspace/Workspace+Traits.swift`) records the
  traits a manifest requests on **every declared dependency**: `for dep in manifest.dependencies`.
  The workspace's `enabledTraitsMap` therefore has `T` on for `b`, and the required-package check
  after resolution (`DependencyManifests.missingPackages`) requires `c`.
- Resolution only follows the dependencies a manifest requires for its enabled traits,
  `Manifest.dependenciesRequired(for:_:)`. `m` uses none of `b`'s products, so `m → b` is never
  followed, `b` is resolved with its defaults only, and `c` is never fetched.

SwiftPM means such a request to apply: its functional test
`TraitTests.traits_whenTraitUnification_whenSecondTraitNotEnabled` requests a trait on an edge
that is guarded off, and expects the trait to be enabled. So resolution is the side that is wrong.
A local fix (not filed) gives the resolver the workspace's trait map as a minimum for every
package, and resolves again while packages are missing and loading manifests has enabled new
traits. Ignoring unused edges in `updateEnabledTraits` instead also makes the reproducer resolve,
but it breaks that test, so it was dropped.

## Where it was found

On 2026-10-29, `.when(traits:)` conditions were added to the integration dependencies of fifteen
swift-atoms packages ("Condition each integration dependency on the traits that guard its
imports") and reverted the same day. A fresh clone of swift-compositions/swift-file-system at
5a6a71b, with those fifteen packages mirrored to their pre-revert commits, fails with
`* 'swift-always' from https://github.com/swift-atoms/swift-always.git`, as reported. The edge is
swift-compositions/swift-kernel → swift-serializer with
`traits: ["Either", "Map", "Pair", "Repetition", "Always", "Byte"]`. No swift-kernel target uses a
swift-serializer product, so swift-serializer's `Always` trait, which now guards its dependency
on swift-always, is on for the workspace but not for resolution. With the local fix, the same graph resolves.

## Related

- [`swift-issue-spm-diamond-trait-conditional-dependency`](../swift-issue-spm-diamond-trait-conditional-dependency):
  a second, independent defect in the same failure family. It concerns branch-based and `path:`
  packages only, and still fails on Swift 6.4.2.
- swiftlang/swift-package-manager#10485 (open) is that second defect, not this one.
