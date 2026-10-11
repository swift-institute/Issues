# Swift: the `_Testing_Foundation` overlay picks up a package module named `System`

**Classification:** module lookup in an implicitly built cross-import overlay. A correct
package fails to build its tests on macOS when a test file imports both Testing and
Foundation, and the package graph contains a module named `System`.

The test file imports Testing and Foundation, so the driver builds the cross-import overlay
`_Testing_Foundation` (package `swift_testing`). That overlay is compiled for the
toolchain's own minimum (`arm64-apple-macos14.0`), with the package's products directory
on its search path. The `System` it imports resolves to the package's `System.swiftmodule`
instead of the SDK's System framework. The build stops with:

```
<unknown>:0: error: compiling for macOS 14.0, but module 'System' has a minimum deployment target of macOS 27.0: …/.build/out/Products/Debug/System.swiftmodule/arm64-apple-macos.swiftmodule
```

The same test file without `import Foundation` builds in under a second.

## Reproducer

One package, staged by [`Sources/Reproducer/main.swift`](Sources/Reproducer/main.swift)
from [`Sources/Reproducer/Fixture`](Sources/Reproducer/Fixture), with no dependencies:

- `System`: a library target with `public struct Marker`, platform floor macOS 27.
- `ClientTests`: a test target depending on `System`, whose file imports Foundation,
  Testing and System.

```sh
swift run swift-issue-testing-foundation-overlay-package-system-module-Repro
```

Expected: `swift build --build-tests` succeeds with and without `import Foundation`.
Observed on Apple Swift 6.4 (swiftlang-6.4.0.34.1, Xcode 27.1, arm64 macOS 27): the build
succeeds without `import Foundation` and fails with the error above when it is added.

Not filed upstream.

## Where it was found

swift-standards/swift-stripe-standard, whose graph contains swift-atoms/swift-system
(module `System`) through swift-dependencies. Its test targets "Stripe Types Shared Tests",
"Stripe Types Tests" and "Stripe Billing Types Tests" imported Foundation for
`JSONDecoder`, `JSONEncoder` and `Date`. Any Institute test target that imports Foundation
in a graph containing swift-system hits the same error on macOS.

## Workaround

Keep Foundation out of test targets in graphs that contain swift-system. The Stripe tests
now decode and encode through swift-json (`JSON.parse(_:).decode(_:)`,
`JSON(encoding:)`). The module keeps its name, per the ruling that Institute names are not
renamed to avoid clashes.
