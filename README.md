# Issues

Minimal Swift packages reproducing toolchain and compiler bugs encountered while developing the [Swift Institute](https://swift-institute.org) ecosystem — public receipts for issues filed at [swiftlang/swift](https://github.com/swiftlang/swift) and related repositories.

## Overview

Each subdirectory is a standalone Swift package that fires a single bug under a documented platform / toolchain configuration. Reproducers are reduced to the minimum trigger: no package-internal types, no transitive dependencies, no special swiftSettings beyond what the bug requires.

When a bug catalog entry says "this code miscompiles on Linux release," the issue reproducer proves it — runnable from `swift test -c release` and verified by CI on every supported platform.

The companion research repository is at [swift-institute/Research](https://github.com/swift-institute/Research). The companion experiments repository is at [swift-institute/Experiments](https://github.com/swift-institute/Experiments).

## Building

Each issue is a standalone Swift package. Clone this repository and run `swift test` (or `swift test -c release`) inside the issue directory:

```
git clone https://github.com/swift-institute/Issues.git
cd Issues/{issue-name}
swift test -c release
```

Requires Swift 6.3 or newer.

## CI

Continuous integration runs the standard four-platform matrix per issue directory:

- macOS (Swift 6.3, release)
- Linux (Swift 6.3, release)
- Linux (Swift 6.4-dev nightly, release)
- Windows (Swift 6.3, release)

For an issue reproducer, **a permanently-red CI leg is the bug's running evidence**. When the upstream fix lands and the affected leg turns green, that's the signal to close the issue and remove the reproducer (or move it to a regression-fixture target).

## Index

Each issue subdirectory documents its bug in `README.md`:

- The filed `swiftlang/swift` issue (if any)
- Affected and unaffected toolchains
- Minimal reproducer code
- Workaround for consumers (if any)
- CI status table

## License

[Apache 2.0](LICENSE.md).
