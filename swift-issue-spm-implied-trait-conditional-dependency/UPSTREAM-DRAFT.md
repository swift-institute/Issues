# Draft for swiftlang/swift-package-manager (not filed)

Status: not to be filed. Coen ruled on 2026-10-11 that there are no new upstream filings; this record in swift-institute/Issues is the report. The text below is kept for reference.

Duplicate search (2026-10-11) of swiftlang/swift-package-manager issues and pull requests (open and closed) for "traits", "enabledTraits", "implied traits" and "conditional trait dependency". Also searched swiftlang/swift for "traits". None of the trait resolution reports involves an implied trait (`enabledTraits:`) feeding a conditional trait request:

- #9935: an unconditional trait request is not applied transitively.
- #10485, #10397, #9286 and swiftlang/swift#90253: one package is reached both with a trait request and without one.
- #10478: a resolution hang with a mixed trait request.

The fixes merged for 6.4.2 (#10547/#10569, #10550/#10570, #10579) deal with default-trait requests and the order of traversal, not with implication. They could not be tested here: the newest installed toolchain is older than those fixes.

---

**Title:** An implied trait does not activate a conditional trait request on a dependency

### Description

A package trait that is on only because another trait implies it (`.trait(name: "X", enabledTraits: ["Y"])`) does not satisfy `.when(traits: ["Y"])` on that package's trait requests to its dependencies. The dependency's trait-gated product dependency is then never added, and resolution fails.

Four local packages:

```swift
// c/Package.swift
// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "c",
    products: [.library(name: "C", targets: ["C"])],
    targets: [.target(name: "C")]
)
```

```swift
// b/Package.swift: trait Z gates the dependency on c
// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "b",
    products: [.library(name: "B", targets: ["B"])],
    traits: [.trait(name: "Z")],
    dependencies: [.package(url: "file:///tmp/implied/c", branch: "main")],
    targets: [
        .target(name: "B", dependencies: [
            .product(name: "C", package: "c", condition: .when(traits: ["Z"])),
        ]),
    ]
)
```

```swift
// a/Package.swift: X implies Y, and Y requests b's trait Z
// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "a",
    products: [.library(name: "A", targets: ["A"])],
    traits: [
        .trait(name: "X", enabledTraits: ["Y"]),
        .trait(name: "Y"),
    ],
    dependencies: [
        .package(
            url: "file:///tmp/implied/b",
            branch: "main",
            traits: [.trait(name: "Z", condition: .when(traits: ["Y"]))]
        ),
    ],
    targets: [.target(name: "A", dependencies: [.product(name: "B", package: "b")])]
)
```

```swift
// root/Package.swift
// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "root",
    dependencies: [.package(url: "file:///tmp/implied/a", branch: "main", traits: ["X"])],
    targets: [.target(name: "Root", dependencies: [.product(name: "A", package: "a")])]
)
```

Each package has one empty source file in `Sources/<Target>/` and is a git repository with one commit on `main`.

### Expected behavior

The graph resolves. Requesting `X` enables `Y`, `Y` requests `Z` on `b`, and `Z` adds `c`.

### Actual behavior

```
$ swift package resolve
error: exhausted attempts to resolve the dependencies graph, with the following dependencies unresolved:
* 'c' at /tmp/implied/c
```

The result does not depend on order and is the same from a clean `.build`. Requesting `["Y"]` or `["X", "Y"]` from `root` resolves. Writing the implication into the condition, `.when(traits: ["Y", "X"])`, also resolves.

### Steps to reproduce

1. Create the four packages above under `/tmp/implied`, each with an empty source file, then `git init -b main`, `git add -A` and `git commit`.
2. `cd /tmp/implied/root && swift package resolve`.

### Swift Package Manager version/commit hash

Swift 6.4 (Xcode)

### Swift & OS version (output of `swift --version ; uname -a`)

```
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.2.0
```
