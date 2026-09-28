# SwiftPM: an implied trait does not activate conditional dependency trait requests

**Classification:** SwiftPM dependency resolution. The graph fails to resolve.

A trait that is enabled only because another trait implies it (`enabledTraits`)
does not activate that package's conditional trait requests on its dependencies.
The dependency whose trait gates further dependencies then leaves them
unresolved, and resolution fails:

```
error: exhausted attempts to resolve the dependencies graph, with the following dependencies unresolved:
* 'c' from file://…/c
```

## Reproducer

Four packages, staged by [`Sources/Reproducer/main.swift`](Sources/Reproducer/main.swift)
from [`Sources/Reproducer/Fixture`](Sources/Reproducer/Fixture):

- `c`: a plain library.
- `b`: trait `Z` gates its product dependency on `c`.
- `a`: trait `X` implies `Y`; `Y` conditionally requests `b`'s trait `Z`
  (`.trait(name: "Z", condition: .when(traits: ["Y"]))`).
- `root`: depends on `a` with `traits: ["X"]`.

```sh
swift run swift-issue-spm-implied-trait-conditional-dependency-Repro
```

Expected: the graph resolves, since `X` enables `Y`, `Y` requests `Z`, and `Z` needs `c`.
Observed on Swift 6.4 (`swiftlang-6.4.0.34.1`, arm64 macOS 27): the error above.
Requesting `["Y"]` or `["X", "Y"]` from `root` resolves. Xcode 27.1 resolves the same graph.

## Workaround

Spell the implication out in every condition: a conditional request list names every
trait that implies the trait it depends on, e.g. `.when(traits: ["Y", "X"])`.
The Swift Institute packages that use `enabledTraits` do this
(first found through swift-finite's `Algebra`/`Comparison`/`Iterator` ⇒ `Tagged` ⇒ swift-ordinal `Tagged`).
